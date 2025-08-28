//
//  PhotoDetailView.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/28/25.
//

import SwiftUI

struct PhotoDetailView: View {
    let photos: [Photo]
    let currentPhoto: Photo

    // Binding to manage navigation back
    @Binding var selectedPhoto: Photo?

    // State
    @State private var currentIndex: Int = 0

    // Managers
    private let photoManager = PhotoManager()
    private let sequenceManager = SequenceManager()

    private var currentPhotoIndex: Int {
        photos.firstIndex { $0.id == currentPhoto.id } ?? 0
    }

    private var photoCounterText: String {
        let total = photos.count
        let current = currentIndex + 1
        return "Photo \(current) of \(total)"
    }

    private var photoMetadata: (timestamp: String, sequence: String, session: String, location: String?) {
        let timestamp = currentPhoto.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"

        let sequence = "#\(photos[currentIndex].sequenceNumber)"

        let session = currentPhoto.sessionID ?? "Unknown Session"

        let location: String? = {
            let latitude = currentPhoto.latitude
            let longitude = currentPhoto.longitude
            return String(format: "%.6f, %.6f", latitude, longitude)
        }()

        return (timestamp, sequence, session, location)
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header with photo counter and navigation
                HStack {
                    Spacer()

                    Text(photoCounterText)
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: {
                        selectedPhoto = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title2)
                            .padding()
                    }
                }
                .padding(.horizontal)

                // Photo content
                TabView(selection: $currentIndex) {
                    ForEach(photos.indices, id: \.self) { index in
                        PhotoDetailItem(
                            photo: photos[index],
                            isCurrentPhoto: index == currentIndex,
                            metadata: {
                                let meta = photos[index].timestamp != nil ? getMetadata(for: photos[index]) : nil
                                let photoMeta = getPhotoMetadata(for: photos[index])
                                return (meta, photoMeta)
                            }(),
                            onPhotoSelected: {
                                // Handle photo selection if needed
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .onAppear {
            currentIndex = currentPhotoIndex
        }
    }

    private func getMetadata(for photo: Photo) -> (timestamp: String, sequence: String, session: String, location: String?) {
        let timestamp = photo.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"

        let sequence = "#\(photo.sequenceNumber)"

        let session = photo.sessionID ?? "Unknown Session"

        let location: String? = {
            let latitude = photo.latitude
            let longitude = photo.longitude
            return String(format: "%.6f, %.6f", latitude, longitude)
        }()

        return (timestamp, sequence, session, location)
    }

    private func getPhotoMetadata(for photo: Photo) -> (sequence: String, sessionName: String) {
        let sequence = "#\(photo.sequenceNumber)"
        let sessionName = sequenceManager.getPhotoMetadata(forSequence: Int64(photo.sequenceNumber)).sessionName
        return (sequence, sessionName)
    }
}

// MARK: - Photo Detail Item

struct PhotoDetailItem: View {
    let photo: Photo
    let isCurrentPhoto: Bool
    let metadata: ((timestamp: String, sequence: String, session: String, location: String?)?, (sequence: String, sessionName: String))?
    let onPhotoSelected: () -> Void

    @State private var imageToDisplay: UIImage? = nil
    @State private var isLoadingImage = true
    @State private var showMetadata = true
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero

    private let photoManager = PhotoManager()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full-size image or loading state
                if let image = imageToDisplay {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(imageScale)
                        .offset(imageOffset)
                        .gesture(
                            // Double tap to zoom
                            TapGesture(count: 2).onEnded {
                                withAnimation(.spring()) {
                                    imageScale = imageScale == 1.0 ? 2.0 : 1.0
                                    imageOffset = .zero
                                }
                            }
                        )
                        .gesture(
                            // Drag to pan when zoomed
                            DragGesture()
                                .onChanged { value in
                                    if imageScale > 1.0 {
                                        imageOffset = value.translation
                                    }
                                }
                                .onEnded { _ in
                                    if imageScale > 1.0 {
                                        withAnimation(.spring()) {
                                            // Clamp offset to reasonable bounds
                                            imageOffset.width = min(max(imageOffset.width, -100), 100)
                                            imageOffset.height = min(max(imageOffset.height, -100), 100)
                                        }
                                    }
                                }
                        )
                        .onTapGesture {
                            if imageScale == 1.0 {
                                withAnimation {
                                    showMetadata.toggle()
                                }
                            }
                        }
                } else if isLoadingImage {
                    // Individual loading indicator for this photo
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.0)
                        Text("Loading...")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Error state - photo couldn't be loaded
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.6))
                        Text("Failed to load photo")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.subheadline)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Metadata overlay
                if showMetadata {
                    VStack {
                        Spacer()

                        // Sequence indicator at top
                        if metadata != nil {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Photo \(photo.sequenceNumber)")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)

                                    if let metadataValue = metadata {
                                        Text(metadataValue.1.sessionName)
                                            .font(.title3)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .shadow(radius: 3)

                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.3), Color.clear]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                        }

                        // Bottom metadata panel
                        if let metadataValue = metadata, let meta = metadataValue.0 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "calendar")
                                    Text("Time: \(meta.timestamp)")
                                }

                                HStack {
                                    Image(systemName: "number.circle")
                                    Text("Sequence: \(meta.sequence)")
                                }

                                HStack {
                                    Image(systemName: "square.stack.3d.up")
                                    Text("Session: \(meta.session)")
                                }

                                if let location = meta.location {
                                    HStack {
                                        Image(systemName: "location")
                                        Text("Location: \(location)")
                                    }
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(16)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                        } else {
                            // Fallback metadata display
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Photo \(photo.sequenceNumber)")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                if let orientation = photo.deviceOrientation {
                                    Text("Orientation: \(orientation)")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(16)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                        }
                    }
                }
            }
        }
        .task {
            // Load full-resolution image immediately
            do {
                print("PhotoDetailItem: Loading image for photo \(photo.sequenceNumber)")
                let image = try await photoManager.loadImage(for: photo)

                // Set the loaded image
                await MainActor.run {
                    imageToDisplay = image
                    isLoadingImage = false
                }

                print("PhotoDetailItem: Successfully loaded image for photo \(photo.sequenceNumber)")
            } catch {
                print("PhotoDetailItem: Error loading image for photo \(photo.sequenceNumber): \(error)")
                await MainActor.run {
                    imageToDisplay = nil
                    isLoadingImage = false
                }
            }
        }
        .onDisappear {
            // Cleanup when swiping away from this photo
            imageToDisplay = nil
            isLoadingImage = true
        }
    }
}

// Preview temporarily disabled to resolve compilation issues
// #Preview {
//     // Create mock photo for preview
//     // TODO: Re-enable when Core Data setup is stable
// }
