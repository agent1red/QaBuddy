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
    @ObservedObject var sessionManager = SessionManager.shared

    // State management
    @State private var photos: [Photo] = []
    @State private var isLoading = false
    @State private var viewMode: ViewMode = .grid
    @State private var selectedPhoto: Photo? = nil
    @State private var showingSessionHistory = false

    // Deletion management
    @State private var deletionManager: PhotoDeletionManager
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var photoToDelete: Photo? = nil
    @State private var selectedPhotosForBulkDelete: Set<NSObject> = []
    @State private var isBulkSelectionMode = false

    // Managers
    private let photoManager = PhotoManager()
    
    // Delayed loading indicator control
    @State private var showLoadingOverlay = false

    // Session title for navigation bar
    @State private var sessionTitle: String = "All Photos"

    init() {
        _deletionManager = State(initialValue: PhotoDeletionManager(
            context: PersistenceController.shared.container.viewContext
        ))
    }

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

    // Grid columns
    private let gridColumns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    // MARK: - Computed Views

    private var galleryContent: some View {
        Group {
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
                                isBulkSelectionMode: isBulkSelectionMode,
                                isSelected: selectedPhotosForBulkDelete.contains(photo),
                                onSelectionToggle: { togglePhotoSelection(photo) },
                                onDeleteSingle: { confirmDelete(for: photo) }
                            )
                            .onTapGesture {
                                if isBulkSelectionMode {
                                    togglePhotoSelection(photo)
                                } else {
                                    selectedPhoto = photo
                                }
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
        }
    }

    private var loadingOverlay: some View {
        Group {
            if showLoadingOverlay {
                // Show loading spinner only if loading takes longer than 0.5 seconds to avoid flickering
                ProgressView("Loading photos...")
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
            }
        }
    }

    private var toolbarItems: some ToolbarContent {
        Group {
            ToolbarItem(placement: .topBarLeading) {
                if isBulkSelectionMode {
                    Button(action: {
                        withAnimation {
                            exitBulkSelectionMode()
                        }
                    }) {
                        Text("Cancel")
                            .foregroundColor(.blue)
                    }
                } else {
                    Button(action: {
                        withAnimation {
                            enterBulkSelectionMode()
                        }
                    }) {
                        Text("Select")
                            .foregroundColor(.blue)
                    }
                }
            }

            ToolbarItem(placement: .principal) {
                if isBulkSelectionMode {
                    let uniquePhotos = getUniquePhotos()
                    Button(action: {
                        selectAllPhotos()
                    }) {
                        Text(selectedPhotosForBulkDelete.count == uniquePhotos.count ? "Deselect All" : "Select All")
                            .foregroundColor(.blue)
                            .font(.headline)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isBulkSelectionMode {
                    Text("\(selectedPhotosForBulkDelete.count) Selected")
                        .foregroundColor(.primary)
                        .font(.body)
                } else if viewMode == .grid {
                    Button(action: {
                        withAnimation {
                            viewMode = .list
                        }
                    }) {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.primary)
                    }
                } else {
                    Button(action: {
                        withAnimation {
                            viewMode = .grid
                        }
                    }) {
                        Image(systemName: "square.grid.3x3.fill")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }

    private var bulkDeleteActionBar: some View {
        Group {
            if isBulkSelectionMode && !selectedPhotosForBulkDelete.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Spacer()
                        Button(action: {
                            showingBulkDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.white)
                                Text("Delete \(selectedPhotosForBulkDelete.count) \(selectedPhotosForBulkDelete.count == 1 ? "Photo" : "Photos")")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .background(Color.red)
                            .cornerRadius(12)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color(.secondarySystemBackground))
                }
            }
        }
    }



    var body: some View {
        NavigationStack {
            ZStack {
                galleryContent
                loadingOverlay
            }
            .navigationTitle(sessionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarItems
            }
            .safeAreaInset(edge: .bottom) {
                bulkDeleteActionBar
            }
            .navigationDestination(item: $selectedPhoto) { photo in
                PhotoDetailView(
                    photos: photos,
                    currentPhoto: photo,
                    selectedPhoto: $selectedPhoto
                )
            }
        }
        .alert("Delete Photo", isPresented: $showingDeleteConfirmation, presenting: photoToDelete) { photo in
            Button("Delete", role: .destructive) {
                Task {
                    await performDelete(photo: photo)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { photo in
            Text("Are you sure you want to delete Photo \(photo.sequenceNumber)?\n\n**PERMANENT DELETION:** This will permanently delete the photo file and cannot be undone.")
        }
        .alert("Delete Photos", isPresented: $showingBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await performBulkDelete()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(selectedPhotosForBulkDelete.count) \(selectedPhotosForBulkDelete.count == 1 ? "photo" : "photos")?\n\n**PERMANENT DELETION:** This will permanently delete all selected photo files and cannot be undone.")
        }

        .task {
            await refreshSessionTitle()
            await loadPhotos()
        }
        .refreshable {
            await refreshSessionTitle()
            await loadPhotos()
        }
        .onReceive(sessionManager.objectWillChange) { _ in
            Task {
                await refreshSessionTitle()
                await loadPhotos()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            PhotoImageCache.shared.clearAllCaches()
        }
    }

    // MARK: - Bulk Selection Methods

    private func enterBulkSelectionMode() {
        isBulkSelectionMode = true
        selectedPhotosForBulkDelete.removeAll()
    }

    private func exitBulkSelectionMode() {
        isBulkSelectionMode = false
        selectedPhotosForBulkDelete.removeAll()
    }

    private func togglePhotoSelection(_ photo: Photo) {
        if selectedPhotosForBulkDelete.contains(photo) {
            selectedPhotosForBulkDelete.remove(photo)
        } else {
            selectedPhotosForBulkDelete.insert(photo)
        }
    }

    // MARK: - Deletion Methods

    private func performBulkDelete() async {
        // Convert selected photos to array
        let photosToDelete = Array(selectedPhotosForBulkDelete.compactMap { $0 as? Photo })

        do {
            try await deletionManager.deletePhotos(photosToDelete)

            // Exit bulk selection mode and refresh
            exitBulkSelectionMode()
            await loadPhotos()

            print("✅ \(photosToDelete.count) photos deleted permanently")
        } catch {
            print("❌ Error deleting photos: \(error)")

            // Reset UI state on error to avoid stuck condition
            exitBulkSelectionMode()
        }
    }

    private func confirmDelete(for photo: Photo) {
        photoToDelete = photo
        showingDeleteConfirmation = true
    }

    private func performDelete(photo: Photo) async {
        do {
            try await deletionManager.deletePhoto(photo)

            // Refresh photos after deletion
            await loadPhotos()

            print("✅ Photo \(photo.sequenceNumber) deleted permanently")
        } catch {
            print("❌ Error deleting photo: \(error)")
        }
    }



    private func loadPhotos() async {
        // Start loading
        isLoading = true
        showLoadingOverlay = false

        // Delay showing loading indicator if loading takes more than 0.5 seconds to avoid flickering UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if isLoading {
                showLoadingOverlay = true
            }
        }

        do {
            // Load photos based on session filtering
            if let activeSessionId = sessionManager.activeSessionIdString {
                // Load photos for active session only
                photos = try photoManager.fetchPhotos(forSession: activeSessionId)
            } else {
                // No active session - show all photos
                photos = try photoManager.fetchAllPhotos()
            }
        } catch {
            print("❌ Error loading photos: \(error)")
            photos = []
        }
        // Loading complete
        isLoading = false
        showLoadingOverlay = false
    }

    // MARK: - Helper Methods

    private func getUniquePhotos() -> [Photo] {
        Dictionary(grouping: photos) { $0.sequenceNumber }
            .compactMapValues { $0.first }
            .map { $0.value }
    }

    private func selectAllPhotos() {
        let uniquePhotos = getUniquePhotos()
        if selectedPhotosForBulkDelete.count == uniquePhotos.count {
            // Deselect all
            selectedPhotosForBulkDelete.removeAll()
        } else {
            // Select all
            selectedPhotosForBulkDelete.formUnion(Set(uniquePhotos))
        }
    }

    private func refreshSessionTitle() async {
        let info = await sessionManager.getCurrentSessionInfo()
        await MainActor.run {
            sessionTitle = (info == "No Active Session") ? "All Photos" : info
        }
    }
}

// MARK: - Photo Grid Item

struct PhotoGridItem: View {
    let photo: Photo
    let isBulkSelectionMode: Bool
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    let onDeleteSingle: () -> Void

    @State private var imageOpacity: Double = 0.0
    @State private var displayedImage: UIImage? = nil
    @State private var isHighResLoaded = false

    private let photoManager = PhotoManager()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Photo thumbnail with overlay
            mainContent

            // Checkbox overlay (only when in bulk selection mode)
            if isBulkSelectionMode {
                ZStack {
                    // Semi-transparent overlay when selected
                    if isSelected {
                        Color.blue.opacity(0.3)
                            .frame(height: 120)
                            .cornerRadius(8)
                    }

                    // Checkbox button
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: 24, height: 24)
                                    .shadow(radius: 2)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title2)
                                } else {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.8), lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .padding(8)
                        }
                        Spacer()
                    }
                }
            }

            // Sequence number overlay (bottom-left corner)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .onAppear {
            loadThumbnailOrCache()
            loadHighResImageAsync()
        }
    }

    private var mainContent: some View {
        Group {
            if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
                    .opacity(imageOpacity)
                    .cornerRadius(8)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.2)) {
                            imageOpacity = 1.0
                        }
                    }
            } else {
                // Placeholder for missing thumbnails
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                        .font(.largeTitle)
                }
                .frame(height: 120)
                .aspectRatio(3/4, contentMode: .fit)
            }
        }
    }

    private func loadThumbnailOrCache() {
        // Use photo.thumbnailFilename or photo.id?.uuidString as cache key
        let cacheKey = photo.thumbnailFilename ?? photo.id?.uuidString ?? ""

        if let cachedImage = PhotoImageCache.shared.image(forKey: cacheKey) {
            displayedImage = cachedImage
            imageOpacity = 1.0
        } else {
            if let thumb = photoManager.loadThumbnail(for: photo) {
                displayedImage = thumb
                imageOpacity = 1.0
                PhotoImageCache.shared.setImage(thumb, forKey: cacheKey)
            }
        }
    }

    private func loadHighResImageAsync() {
        // Stub for progressive loading: after appear, try to load high-res image async and update if available
        guard !isHighResLoaded else { return }
        
        isHighResLoaded = true

        Task {
            do {
                let highResImage = try await photoManager.loadImage(for: photo)
                let cacheKey = photo.thumbnailFilename ?? photo.id?.uuidString ?? ""
                PhotoImageCache.shared.setImage(highResImage, forKey: cacheKey)
                // Update UI on main thread
                await MainActor.run {
                    displayedImage = highResImage
                    withAnimation(.easeIn(duration: 0.3)) {
                        imageOpacity = 1.0
                    }
                }
            } catch {
                // Optionally handle error (ignore for now)
            }
        }
    }
}

// MARK: - Photo List Item

struct PhotoListItem: View {
    let photo: Photo

    private let photoManager = PhotoManager()
    @State private var displayedImage: UIImage? = nil

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            Group {
                if let image = displayedImage {
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
        .onAppear {
            loadThumbnailOrCache()
        }
    }

    private func loadThumbnailOrCache() {
        let cacheKey = photo.thumbnailFilename ?? photo.id?.uuidString ?? ""
        if let cachedImage = PhotoImageCache.shared.image(forKey: cacheKey) {
            displayedImage = cachedImage
        } else {
            if let thumb = photoManager.loadThumbnail(for: photo) {
                displayedImage = thumb
                PhotoImageCache.shared.setImage(thumb, forKey: cacheKey)
            }
        }
    }
}



#Preview {
    let persistence = PersistenceController()
    return PhotoGalleryView()
        .environment(\.managedObjectContext, persistence.container.viewContext)
}
