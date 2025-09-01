//  PhotoDetailViewAnnotation.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/31/25.
//  Phase 2 - Task 1: Photo Detail View with Quick Look Integration

import SwiftUI
import CoreData
import UIKit

struct PhotoDetailViewAnnotation: View {
    let photo: Photo
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // Annotation State
    @State private var showingQuickLook = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false

    // Image Display
    @State private var currentImage: UIImage? = nil
    @State private var isLoadingImage = true
    @State private var showLoadingSpinner = false

    // Managers
    private let photoManager = PhotoManager()

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header with back button and actions
                HStack {
                    Button(action: {
                        Logger.info("Photo detail: Dismiss requested")
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                            .font(.title2)
                            .padding(12)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("Photo #\(photo.sequenceNumber)")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text(resolvedSessionInfo(for: photo))
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                    }
                    .padding(.vertical, 8)

                    Spacer()

                    Menu {
                        Button(action: sharePhoto) {
                            Label("Share Photo", systemImage: "square.and.arrow.up")
                        }

                        if photo.hasAnnotations {
                            Divider()
                            Button(action: { showingDeleteConfirmation = true }) {
                                Label("Delete Annotations", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                            .font(.title2)
                            .padding(12)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                }
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

                // Main Image Area
                GeometryReader { geometry in
                    ZStack {
                        // Annotation Control Overlay
                        if #available(iOS 17.0, *) {
                            VStack {
                                Spacer()

                                HStack {
                                    annotationButton

                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                            }
                        }

                        // Image or loading state
                        photoDisplayArea
                    }
                }
            }
        }
        .task {
            await loadPhoto()
        }
        .overlay(
            // Quick Look overlay when annotation is in progress
            Group {
                if showingQuickLook {
                    if #available(iOS 17.0, *) {
                        QuickLookAnnotationView(
                            photo: photo,
                            isPresented: $showingQuickLook,
                            onAnnotationComplete: { annotatedImage in
                                Logger.info("Annotation completed, updating display")
                                currentImage = annotatedImage
                                isLoadingImage = false
                                showLoadingSpinner = false
                            }
                        )
                        .ignoresSafeArea()
                    }
                }
            }
        )
        .alert("Delete Annotations", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAnnotations()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all annotations for this photo.")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = currentImage {
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - UI Components

    private var annotationButton: some View {
        if #available(iOS 17.0, *) {
            return Button(action: {
                Logger.info("Annotation button tapped for photo #\(photo.sequenceNumber)")
                showingQuickLook = true
            }) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)

                        Image(systemName: photo.hasAnnotations ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)

                        if photo.hasAnnotations {
                            Circle()
                                .stroke(Color.green, lineWidth: 2)
                                .frame(width: 62, height: 62)
                        }
                    }

                    Text(photo.hasAnnotations ? "Edit\nAnnotations" : "Add\nAnnotations")
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 5)
            }
        } else {
            return Button(action: {}) {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.red)

                    Text("iOS 17+\nRequired")
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var photoDisplayArea: some View {
        Group {
            if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(photoBadges, alignment: .topTrailing)
            } else if isLoadingImage {
                if showLoadingSpinner {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.5)
                        Text("Loading...")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                            .padding(.top, 16)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.white.opacity(0.5))
                    Text("Photo could not be loaded")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                }
            }
        }
    }

    private var photoBadges: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if photo.hasAnnotations {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Annotated")
                        .font(.caption2)
                        .multilineTextAlignment(.trailing)
                }
                .padding(6)
                .background(Color.green.opacity(0.9))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(radius: 3)
            }
        }
        .padding(12)
    }

    // MARK: - Helper Methods

    private func loadPhoto() async {
        Logger.info("Loading photo for annotation view: #\(photo.sequenceNumber)")

        let cacheKey = photo.imageFilename ?? photo.id?.uuidString ?? ""
        if !cacheKey.isEmpty {
            if let cachedImage = PhotoImageCache.shared.image(forKey: cacheKey) {
                Logger.info("Loaded photo from cache")
                await MainActor.run {
                    currentImage = cachedImage
                    isLoadingImage = false
                }
                return
            }
        }

        // Show loading spinner after delay
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            if isLoadingImage && currentImage == nil {
                await MainActor.run {
                    showLoadingSpinner = true
                }
            }
        }

        do {
            let image = try await photoManager.loadImage(for: photo)

            // Cache the image
            if !cacheKey.isEmpty {
                PhotoImageCache.shared.setImage(image, forKey: cacheKey)
            }

            await MainActor.run {
                currentImage = image
                isLoadingImage = false
                showLoadingSpinner = false
            }

            Logger.info("Successfully loaded photo for annotation")
        } catch {
            Logger.error("Failed to load photo: \(error.localizedDescription)")
            await MainActor.run {
                isLoadingImage = false
                showLoadingSpinner = false
            }
        }
    }

    private func deleteAnnotations() {
        Logger.info("Deleting annotations for photo #\(photo.sequenceNumber)")

        // Single-file approach: Just clear the [MODIFIED] marker from notes
        photo.isAnnotated = false

        // Clear the image cache to reflect the change
        let cacheKey = photo.imageFilename ?? photo.id?.uuidString ?? ""
        if !cacheKey.isEmpty {
            PhotoImageCache.shared.removeImage(forKey: cacheKey)
        }

        Logger.info("Annotations cleared for photo #\(photo.sequenceNumber)")
    }

    private func sharePhoto() {
        Logger.info("Sharing photo #\(photo.sequenceNumber)")
        showingShareSheet = true
    }

    private func resolvedSessionName(for photo: Photo) -> String? {
        guard let sessionID = photo.sessionID, !sessionID.isEmpty else { return nil }

        if let uuid = UUID(uuidString: sessionID) {
            if let session = try? viewContext.fetch(Session.fetchRequest()).first(where: { $0.id == uuid }) {
                return session.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return "Unknown Session"
    }

    private func resolvedSessionInfo(for photo: Photo) -> String {
        guard let sessionID = photo.sessionID, !sessionID.isEmpty else {
            return "No Session"
        }

        if let uuid = UUID(uuidString: sessionID) {
            if let session = try? viewContext.fetch(Session.fetchRequest()).first(where: { $0.id == uuid }) {
                let sessionName = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Session"

                // Get inspection type if available
                if let inspectionTypeString = session.inspectionType,
                   let inspectionType = InspectionType(rawValue: inspectionTypeString) {
                    return "Session: \(inspectionType.displayName)"
                } else {
                    return sessionName
                }
            }
        }

        return "No Session"
    }
}

// MARK: - Share Sheet Helper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.shared.container.viewContext
    let photo = Photo(context: context)
    photo.id = UUID()
    photo.sequenceNumber = 1
    photo.imageFilename = "test.jpg"
    photo.timestamp = Date()
    photo.sessionID = UUID().uuidString
    photo.notes = "Annotated: Test photo for preview"

    return PhotoDetailViewAnnotation(photo: photo)
}
