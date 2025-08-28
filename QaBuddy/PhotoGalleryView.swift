//
//  PhotoGalleryView.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/28/25.
//

import SwiftUI
import CoreData

struct PhotoGalleryView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // State management
    @State private var photos: [Photo] = []
    @State private var isLoading = false
    @State private var viewMode: ViewMode = .grid
    @State private var selectedPhoto: Photo? = nil

    // Managers
    private let photoManager = PhotoManager()
    private let sequenceManager = SequenceManager()

    enum ViewMode {
        case grid
        case list
    }

    private var photoCountDisplay: String {
        // Get unique sequence numbers to show actual number of displayed photos
        let uniqueSequences = Set(photos.map { $0.sequenceNumber })
        let count = uniqueSequences.count

        switch count {
        case 0: return "No Photos"
        case 1: return "1 Photo"
        default: return "\(count) Photos"
        }
    }

    private var currentSessionName: String {
        sequenceManager.activeSessionName
    }

    // Grid columns
    private let gridColumns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // Gallery Content
                if viewMode == .grid {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 4) {
                            // Only show one photo per unique sequence number
                            let uniquePhotos = Dictionary(grouping: photos) { $0.sequenceNumber }
                                .compactMapValues { $0.first }
                                .sorted { $0.key < $1.key }
                                .map { $0.value }

                            ForEach(uniquePhotos, id: \.id) { photo in
                                PhotoGridItem(
                                    photo: photo,
                                    thumbnailImage: photoManager.loadThumbnail(for: photo)
                                )
                                .onTapGesture {
                                    selectedPhoto = photo
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(photos, id: \.id) { photo in
                                PhotoListItem(photo: photo)
                                    .onTapGesture {
                                        selectedPhoto = photo
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Loading overlay
                if isLoading {
                    ProgressView("Loading photos...")
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                }
            }
            .navigationTitle(photoCountDisplay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        withAnimation {
                            viewMode = viewMode == .grid ? .list : .grid
                        }
                    }) {
                        Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.3x3.fill")
                            .foregroundColor(.primary)
                    }
                }
            }
            // Photo detail navigation
            .navigationDestination(item: $selectedPhoto) { photo in
                PhotoDetailView(
                    photos: photos,
                    currentPhoto: photo,
                    selectedPhoto: $selectedPhoto
                )
            }
        }
        .task {
            await loadPhotos()
        }
        .refreshable {
            await loadPhotos()
        }
    }

    private func loadPhotos() async {
        isLoading = true
        do {
            // Load photos sorted by sequence number (most recent first)
            photos = try photoManager.fetchAllPhotos()
        } catch {
            print("Error loading photos: \(error)")
            // Could show error alert here
        }
        isLoading = false
    }
}

// MARK: - Photo Grid Item

struct PhotoGridItem: View {
    let photo: Photo
    let thumbnailImage: UIImage?

    @State private var imageOpacity: Double = 0.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Photo thumbnail
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
                    .opacity(imageOpacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.2)) {
                            imageOpacity = 1.0
                        }
                    }
            } else {
                // Placeholder for missing thumbnails
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                }
                .frame(height: 120)
                .aspectRatio(3/4, contentMode: .fill)
            }

            // Sequence number overlay (prominently displayed)
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .shadow(radius: 2)

                Text("\(photo.sequenceNumber)")
                    .font(.title3)
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .shadow(radius: 3)
            }
            .padding(6)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .padding(8)
        }
    }
}

// MARK: - Photo List Item

struct PhotoListItem: View {
    let photo: Photo

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            if let image = PhotoManager().loadThumbnail(for: photo) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 60)
                    .clipped()
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo \(photo.sequenceNumber)")
                    .font(.headline)
                    .foregroundColor(.primary)

                if let timestamp = photo.timestamp {
                    Text(timestamp, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Disclosure indicator
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    let persistence = PersistenceController()
    return PhotoGalleryView()
        .environment(\.managedObjectContext, persistence.container.viewContext)
}
