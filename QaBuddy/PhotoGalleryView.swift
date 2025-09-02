//
//  PhotoGalleryView.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/28/25.
//

import SwiftUI
import CoreData

/// Enhanced Photo Gallery with integrated write-up management
/// Supports photos, drafts, and complete write-ups with smart filtering
struct PhotoGalleryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var sessionManager = SessionManager.shared

    // Content filtering
    @State private var contentType: ContentType = .all
    @State private var selectedPhoto: Photo? = nil
    @State private var selectedWriteup: PUWriteup? = nil
    @State private var showingSessionHistory = false

    // UI State
    @State private var viewMode: ViewMode = .grid

    // Deletion management
    @State private var deletionManager: PhotoDeletionManager
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var photoToDelete: Photo? = nil
    @State private var selectedPhotosForBulkDelete: Set<NSObject> = []
    @State private var isBulkSelectionMode = false

    // Write-up navigation
    @State private var showingWriteupForm = false
    @State private var writeupToResume: PUWriteup? = nil

    // Managers
    private let photoManager = PhotoManager()

    // Session title for navigation bar
    @State private var sessionTitle: String = "All Photos"

    // Dynamic fetch requests responsive to UI changes
    @FetchRequest var allPhotos: FetchedResults<Photo>
    @FetchRequest var allWriteups: FetchedResults<PUWriteup>

    // Computed properties for legacy compatibility
    private var photos: [Photo] {
        Array(allPhotos)
    }

    init() {
        _deletionManager = State(initialValue: PhotoDeletionManager(
            context: PersistenceController.shared.container.viewContext
        ))

        // Initialize fetch requests (fetch broadly; we'll filter by session in-memory)
        let photoRequest = Photo.fetchRequest()
        photoRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        self._allPhotos = FetchRequest(fetchRequest: photoRequest, animation: .default)

        let writeupRequest = PUWriteup.fetchRequest()
        writeupRequest.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: false)]
        self._allWriteups = FetchRequest(fetchRequest: writeupRequest, animation: .default)
    }

    enum ContentType: String, CaseIterable, Identifiable {
        case all = "All"
        case photos = "Photos"
        case writeups = "Write-ups"
        case drafts = "Drafts"

        var id: Self { self }

        var icon: String {
            switch self {
            case .all: return "square.stack.3d.up"
            case .photos: return "photo.stack"
            case .writeups: return "doc.text"
            case .drafts: return "pencil.circle"
            }
        }
    }

    enum ViewMode {
        case grid
        case list
    }

    private var photoCountDisplay: String {
        // Get unique sequence numbers to show actual number of displayed photos
        let uniqueSequences = Set(filteredPhotos.map { $0.sequenceNumber })
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

    // MARK: - Content Filtering and Display

    private var filteredPhotos: [Photo] {
        // Apply session filtering first
        let sessionFiltered: [Photo] = {
            if let sessionId = sessionManager.activeSessionIdString {
                return Array(allPhotos).filter { $0.sessionID == sessionId }
            } else {
                return Array(allPhotos)
            }
        }()

        switch contentType {
        case .all, .photos:
            // Get unique photos by sequence number
            return Dictionary(grouping: sessionFiltered) { $0.sequenceNumber }
                .compactMapValues { $0.first }
                .sorted { $0.key < $1.key }
                .map { $0.value }
        case .writeups, .drafts:
            // Only show photos attached to write-ups (also filtered by session)
            let writeupPhotoIds = getAttachedPhotoIds()
            return sessionFiltered.filter { photo in
                guard let photoId = photo.id?.uuidString else { return false }
                return writeupPhotoIds.contains(photoId)
            }
        }
    }

    private var filteredWriteups: [PUWriteup] {
        // Apply session filtering first
        let sessionFiltered: [PUWriteup] = {
            if let sessionIdString = sessionManager.activeSessionIdString,
               let sessionUUID = UUID(uuidString: sessionIdString) {
                return Array(allWriteups).filter { $0.session?.id == sessionUUID }
            } else {
                return Array(allWriteups)
            }
        }()

        switch contentType {
        case .all:
            return sessionFiltered.sorted { ($0.createdDate ?? Date()) > ($1.createdDate ?? Date()) }
        case .writeups:
            return sessionFiltered.filter { $0.status != "draft" }.sorted { ($0.createdDate ?? Date()) > ($1.createdDate ?? Date()) }
        case .drafts:
            return sessionFiltered.filter { $0.status == "draft" }.sorted { ($0.createdDate ?? Date()) > ($1.createdDate ?? Date()) }
        case .photos:
            return []
        }
    }

    private func getAttachedPhotoIds() -> Set<String> {
        var photoIds = Set<String>()
        // Limit to session-filtered writeups to avoid scanning all
        let writeups = filteredWriteups
        for writeup in writeups {
            if let photoIdsString = writeup.photoIds {
                let ids = photoIdsString.components(separatedBy: ",").filter { !$0.isEmpty }
                photoIds.formUnion(ids)
            }
        }
        return photoIds
    }

    private var contentTypePicker: some View {
        Picker("Content Type", selection: $contentType) {
            ForEach(ContentType.allCases, id: \.self) { type in
                Label(type.rawValue, systemImage: type.icon)
                    .tag(type as ContentType)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var galleryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Show write-ups first (when applicable)
                if contentType == .all || contentType == .writeups || contentType == .drafts {
                    let writeups = filteredWriteups
                    if !writeups.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(contentType == .drafts ? "DRAFTS" : "WRITE-UPS")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            ForEach(writeups, id: \.id) { writeup in
                                WriteupCard(writeup: writeup)
                                    .onTapGesture {
                                        resumeWriteup(writeup)
                                    }
                            }
                        }
                    }
                }

                // Show photos (when applicable)
                if contentType == .all || contentType == .photos {
                    let photos = filteredPhotos
                    if !photos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PHOTOS")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            // Photo grid layout
                            LazyVGrid(columns: gridColumns, spacing: 4) {
                                ForEach(photos, id: \.id) { photo in
                                    PhotoGridItem(
                                        photo: photo,
                                        isBulkSelectionMode: isBulkSelectionMode,
                                        isSelected: selectedPhotosForBulkDelete.contains(photo),
                                        onSelectionToggle: { togglePhotoSelection(photo) },
                                        onDeleteSingle: { confirmDelete(for: photo) },
                                        onAnnotationRequested: {
                                            selectedPhoto = photo
                                        }
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
                        }
                    }
                }

                // Empty state
                let hasAnyContent = !filteredPhotos.isEmpty || !filteredWriteups.isEmpty
                if !hasAnyContent {
                    emptyContentView
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var emptyContentView: some View {
        VStack(spacing: 20) {
            Image(systemName: contentType.icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))

            Text("No \(contentType.rawValue.lowercased()) found")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if contentType == .drafts {
                Text("Drafts will appear here when you save incomplete write-ups")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Start by taking photos or creating write-ups")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Write-up Management

    private func resumeWriteup(_ writeup: PUWriteup) {
        writeupToResume = writeup
        showingWriteupForm = true
        print("🗂️ Resuming write-up: \(writeup.template?.name ?? "Unknown")")
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
            VStack(spacing: 0) {
                // Modern SwiftUI Segmented Control with icons
                contentTypePicker

                galleryContent
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
            .sheet(isPresented: $showingWriteupForm, onDismiss: {
                writeupToResume = nil
            }) {
                if let writeup = writeupToResume {
                    // Resume existing write-up
                    WriteupFormView(template: writeup.template!, selectedTab: nil)
                }
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            PhotoImageCache.shared.clearAllCaches()
        }
        // @FetchRequest will auto-update on Core Data changes; no need to recreate the requests.
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

            // Exit bulk selection mode (Core Data @FetchRequest will handle UI updates automatically)
            exitBulkSelectionMode()

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

            // Core Data @FetchRequest will handle UI updates automatically
            print("✅ Photo \(photo.sequenceNumber) deleted permanently")
        } catch {
            print("❌ Error deleting photo: \(error)")
        }
    }



    // MARK: - Helper Methods

    private func getUniquePhotos() -> [Photo] {
        Dictionary(grouping: filteredPhotos) { $0.sequenceNumber }
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
}

// MARK: - Write-up Card Component

struct WriteupCard: View {
    let writeup: PUWriteup

    @State private var attachedPhotos: [Photo] = []
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status badge and Template Type
            HStack {
                // Draft badge if status is draft
                if writeup.status == "draft" {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil.circle.fill")
                        Text("Draft")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                    .font(.caption)
                }

                Spacer()

                // Template name
                if let templateName = writeup.template?.name {
                    Text(templateName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Main Content Preview
            VStack(alignment: .leading, spacing: 4) {
                // Issue description (primary content)
                if let issue = writeup.issue, !issue.isEmpty {
                    Text(issue)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                } else {
                    Text("No issue description")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .italic()
                }

                // Location
                if let location = writeup.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text(location)
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
            }

            // Photo Attachment Preview
            if let photoIdsString = writeup.photoIds, !photoIdsString.isEmpty {
                // Calculate photo count for display
                let photoIds = photoIdsString.components(separatedBy: ",").filter { !$0.isEmpty }
                let photoCount = photoIds.count

                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "photo.stack.fill")
                            .font(.caption)
                        Text("\(photoCount) photo\(photoCount == 1 ? "" : "s")")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)

                    Spacer()

                    // Modified timestamp
                    if let modifiedDate = writeup.createdDate {
                        Text(modifiedDate.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            } else {
                // No photos attached - just show timestamp
                HStack {
                    Spacer()
                    if let modifiedDate = writeup.createdDate {
                        Text(modifiedDate.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Photo Grid Item

struct PhotoGridItem: View {
    let photo: Photo
    let isBulkSelectionMode: Bool
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    let onDeleteSingle: () -> Void
    let onAnnotationRequested: () -> Void

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

            // Green annotation badge (top-right corner) - Aviation-style markup indicator
            if photo.hasAnnotations {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "pencil.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.green)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Circle())
                            .shadow(radius: 2)
                            .padding(4)
                    }
                    Spacer()
                }
            }
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
