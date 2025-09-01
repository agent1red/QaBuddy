//
//  PhotoDetailView.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/28/25.
//

import SwiftUI
import CoreData
import UIKit
import QuickLook

struct PhotoDetailView: View {
    let photos: [Photo]
    let currentPhoto: Photo

    // Binding to manage navigation back
    @Binding var selectedPhoto: Photo?

    // State
    @State private var currentIndex: Int = 0
    @State private var showingQuickLook = false
    @State private var forceImageRefresh: Bool = false // Force refresh after annotation
    @State private var quickLookCoordinator: QuickLookCoordinator?

    // Managers
    private let photoManager = PhotoManager()

    // Cache resolved session names by sessionID string
    @State private var sessionNameCache: [String: String] = [:]

    // Pre-computed values to avoid state modification during view updates
    private var currentPhotoIndex: Int {
        photos.firstIndex { $0.id == currentPhoto.id } ?? 0
    }

    private var photoCounterText: String {
        let total = photos.count
        let current = currentIndex + 1
        return "\(current) of \(total)"
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

                    // Annotation button for iOS 17+
                    if #available(iOS 17.0, *) {
                        Button(action: {
                            if let currentPhoto = photos.indices.contains(currentIndex) ? photos[currentIndex] : nil {
                                Logger.info("Opening QuickView annotation for photo #\(currentPhoto.sequenceNumber)")
                                quickLookCoordinator = QuickLookCoordinator(photo: currentPhoto)
                                DispatchQueue.main.async {
                                    quickLookCoordinator?.onAnnotationComplete = { image in
                                        Logger.info("Annotation completed, clearing caches and refreshing UI")
                                        // Clear caches to ensure fresh image load
                                        let cacheKey = currentPhoto.imageFilename ?? currentPhoto.id?.uuidString ?? ""
                                        if !cacheKey.isEmpty {
                                            PhotoImageCache.shared.removeImage(forKey: cacheKey)
                                            PhotoImageCache.shared.removeThumbnail(forKey: cacheKey)
                                        }

                                        // Clear URL cache to prevent system-level caching
                                        URLCache.shared.removeAllCachedResponses()

                                        // Force complete refresh
                                        currentIndex = currentIndex + 1 // Trigger TabView to recreate
                                        currentIndex = currentIndex - 1 // Return to current photo

                                        forceImageRefresh.toggle()
                                        showingQuickLook = false
                                    }
                                    quickLookCoordinator?.onDismiss = {
                                        Logger.info("QuickView dismissed")
                                        showingQuickLook = false
                                    }
                                    showingQuickLook = true
                                }
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                Image(systemName: currentPhoto.hasAnnotations ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.trailing, 8)
                    }

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

                // Photo content - moved expensive metadata computation to avoid state updates during view body
                TabView(selection: $currentIndex) {
                    ForEach(photos.indices, id: \.self) { index in
                        PhotoDetailItemView(
                            photo: photos[index],
                            isCurrentPhoto: index == currentIndex,
                            refreshTrigger: forceImageRefresh,
                            inspectionType: resolvedInspectionType(for: photos[index]) ?? "Inspection"
                        )
                        .id("\(photos[index].id ?? UUID())-\(forceImageRefresh)") // Dynamic ID for refresh
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }

            // QuickLook overlay when annotation is active
            if showingQuickLook, #available(iOS 17.0, *) {
                if let _ = quickLookCoordinator, let currentPhoto = photos.indices.contains(currentIndex) ? photos[currentIndex] : nil {
                    QuickLookAnnotationView(
                        photo: currentPhoto,
                        isPresented: $showingQuickLook,
                        onAnnotationComplete: { image in
                            Logger.info("QuickView annotation completed")
                            forceImageRefresh.toggle()
                        }
                    )
                    .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            currentIndex = currentPhotoIndex
        }
        .onChange(of: forceImageRefresh) { _, _ in
            Logger.info("🔄 Force image refresh triggered")
        }
    }

    // MARK: - Metadata Builders

    private func getMetadata(for photo: Photo) -> (timestamp: String, sequence: String, session: String, location: String?) {
        let timestamp = photo.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"
        let sequence = "#\(photo.sequenceNumber)"
        let sessionName = resolvedSessionName(for: photo) ?? "Unknown Session"

        let location: String? = {
            let latitude = photo.latitude
            let longitude = photo.longitude
            return String(format: "%.6f, %.6f", latitude, longitude)
        }()

        return (timestamp, sequence, sessionName, location)
    }

    private func getPhotoMetadata(for photo: Photo) -> (sequence: String, sessionName: String) {
        let sequence = "#\(photo.sequenceNumber)"
        let sessionName = resolvedSessionName(for: photo) ?? "Unknown Session"
        return (sequence, sessionName)
    }

        // MARK: - Session Name Resolution

    private func resolvedSessionName(for photo: Photo) -> String? {
        guard let sessionID = photo.sessionID, !sessionID.isEmpty else { return nil }

        // Return from cache if available
        if let cached = sessionNameCache[sessionID] {
            return cached
        }

        // Resolve via Core Data
        if let uuid = UUID(uuidString: sessionID) {
            let context = PersistenceController.shared.container.viewContext
            let request = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.fetchLimit = 1

            do {
                if let session = try context.fetch(request).first {
                    let name = session.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = (name?.isEmpty == false) ? name! : "Unknown Session"
                    // Cache and return
                    sessionNameCache[sessionID] = finalName
                    return finalName
                }
            } catch {
                print("❌ Error resolving session name for \(sessionID): \(error)")
            }
        }

        // Cache negative result to avoid repeat fetches
        sessionNameCache[sessionID] = "Unknown Session"
        return "Unknown Session"
    }

    private func resolvedInspectionType(for photo: Photo) -> String? {
        guard let sessionID = photo.sessionID, !sessionID.isEmpty else { return nil }

        // Resolve via Core Data
        if let uuid = UUID(uuidString: sessionID) {
            let context = PersistenceController.shared.container.viewContext

            do {
                let request = Session.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                request.fetchLimit = 1

                if let session = try context.fetch(request).first {
                    // Map InspectionType enum to display string
                    if let inspectionTypeString = session.inspectionType,
                       let inspectionType = InspectionType(rawValue: inspectionTypeString) {
                        return inspectionType.displayName
                    }
                }
            } catch {
                print("❌ Error resolving inspection type for session \(sessionID): \(error)")
            }
        }

        return "Inspection" // Default for photos without session or unknown type
    }
}

// MARK: - Photo Detail Item View (Photo Detail Tab View)

struct PhotoDetailItemView: View {
    let photo: Photo
    let isCurrentPhoto: Bool
    let refreshTrigger: Bool // When this changes, force fresh image load
    let inspectionType: String // Pre-computed inspection type display name

    @State private var imageToDisplay: UIImage? = nil
    @State private var isLoadingImage = true
    @State private var showMetadata = true
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var showLoadingSpinner = false

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
                } else if isLoadingImage && showLoadingSpinner {
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
                } else if !isLoadingImage {
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

                        // Sequence indicator and session name
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Photo #\(photo.sequenceNumber)")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .shadow(radius: 3)

                                Text("Session") // Simplified session display
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.8))
                                    .shadow(radius: 3)
                            }

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

                        // Bottom metadata panel
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "calendar")
                                Text("Time: \(photo.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")")
                            }

                            HStack {
                                Image(systemName: "number.circle")
                                Text("Sequence: #\(photo.sequenceNumber)")
                            }

                            HStack {
                                Image(systemName: "square.stack.3d.up")
                                Text("Session: \(inspectionType)")
                            }

                            if photo.latitude != 0 || photo.longitude != 0 {
                                HStack {
                                    Image(systemName: "location")
                                    Text("Location: \(String(format: "%.4f, %.4f", photo.latitude, photo.longitude))")
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
                    }
                }
            }
        }
        .task {
            // Load photo asynchronously with progressive loading
            await loadPhoto()
        }
        .onChange(of: refreshTrigger) { _, _ in
            Logger.info("Refresh triggered for photo #\(photo.sequenceNumber), reloading...")
            Task {
                await MainActor.run {
                    imageToDisplay = nil
                    isLoadingImage = true
                    showLoadingSpinner = false
                }
                await loadPhoto(forceRefresh: true)
            }
        }
        .onDisappear {
            // Cleanup when swiping away from this photo
            imageToDisplay = nil
            isLoadingImage = true
            showLoadingSpinner = false
        }
    }

    private func loadPhoto(forceRefresh: Bool = false) async {
        // Skip cache if we're forcing a refresh (e.g., after annotation)
        if !forceRefresh {
            let cacheKey = photo.imageFilename ?? photo.id?.uuidString ?? ""
            if !cacheKey.isEmpty {
                if let cachedImage = PhotoImageCache.shared.image(forKey: cacheKey) {
                    Logger.info("Loaded photo from cache for #\(photo.sequenceNumber)")
                    await MainActor.run {
                        imageToDisplay = cachedImage
                        isLoadingImage = false
                    }
                    return
                }
            }
        } else {
            Logger.info("Forced refresh - skipping cache for photo #\(photo.sequenceNumber)")
        }

        // Show loading after delay
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            if isLoadingImage && imageToDisplay == nil {
                await MainActor.run {
                    showLoadingSpinner = true
                }
            }
        }

        // Load full-res image via PhotoManager
        do {
            Logger.info("Loading full-res image for photo #\(photo.sequenceNumber)")
            let image = try await photoManager.loadImage(for: photo)

            // Cache the loaded image (even on forced refresh, we want to cache the fresh version)
            let cacheKey = photo.imageFilename ?? photo.id?.uuidString ?? ""
            if !cacheKey.isEmpty {
                PhotoImageCache.shared.setImage(image, forKey: cacheKey)
            }

            await MainActor.run {
                imageToDisplay = image
                isLoadingImage = false
                showLoadingSpinner = false
            }

            Logger.info("Successfully loaded photo #\(photo.sequenceNumber)")
        } catch {
            Logger.error("Failed to load photo #\(photo.sequenceNumber): \(error.localizedDescription)")
            await MainActor.run {
                imageToDisplay = nil
                isLoadingImage = false
                showLoadingSpinner = false
            }
        }
    }
}
