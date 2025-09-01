//  QaBuddyQuickLookManager.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/31/25.
//  Phase 2 - Task 1: Core Quick Look Implementation with Core Data Integration

import SwiftUI
import UIKit
import QuickLook
import CoreData

// MARK: - Photo Extension for Annotation Support

extension Photo {
    // MARK: - Single-File Annotation Properties

    var isAnnotated: Bool {
        get {
            guard let notes = notes else { return false }
            return notes.contains("[MODIFIED]")
        }
        set {
            if newValue {
                if notes == nil || notes?.isEmpty == true {
                    let dateString = Date().formatted(date: .abbreviated, time: .shortened)
                    notes = "[MODIFIED] Annotated on \(dateString)"
                } else if !notes!.contains("[MODIFIED]") {
                    let dateString = Date().formatted(date: .abbreviated, time: .shortened)
                    notes = (notes ?? "") + "\n[MODIFIED] Annotated on \(dateString)"
                }
            } else {
                // Remove modification marker safely
                if let currentNotes = notes {
                    let parts = currentNotes.split(separator: "\n").filter { !$0.hasPrefix("[MODIFIED]") }
                    let cleanNotes = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    notes = cleanNotes.isEmpty ? nil : cleanNotes
                }
            }
            try? managedObjectContext?.save()
        }
    }

    // COMPATIBILITY PROPERTY: Required by existing UI components
    var hasAnnotations: Bool {
        return isAnnotated
    }

    // MARK: - Single-File Image Methods

    func loadImage() -> UIImage? {
        return loadOriginalImage()
    }

    func loadOriginalImage() -> UIImage? {
        guard let imageURL = imageURL,
              let image = UIImage(contentsOfFile: imageURL.path) else {
            Logger.warn("Failed to load image from URL: \(imageURL?.path ?? "unknown")")
            return nil
        }
        return image
    }

    // Main annotation method - replaces original file directly
    func replaceWithAnnotatedImage(_ image: UIImage) throws {
        guard let filename = imageFilename,
              let imageURL = imageURL,
              let data = image.jpegData(compressionQuality: 0.9) else {
            throw AnnotationError.imageConversionFailed
        }

        Logger.info("🔄 Replacing original photo file: \(filename)")
        try data.write(to: imageURL)

        // Mark as annotated
        isAnnotated = true

        // Save Core Data changes
        try managedObjectContext?.save()

        // Clear all related cache entries
        let cacheKeys = [
            imageFilename ?? "",
            id?.uuidString ?? "",
            thumbnailFilename ?? ""
        ].filter { !$0.isEmpty }

        for key in cacheKeys {
            PhotoImageCache.shared.removeImage(forKey: key)
            PhotoImageCache.shared.removeThumbnail(forKey: key)
        }

        Logger.info("✅ Photo \(sequenceNumber) successfully replaced with annotated version")
    }
}


// MARK: - FileManager Extension
extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

// MARK: - Annotation Error Types
enum AnnotationError: LocalizedError {
    case imageConversionFailed
    case saveFailure
    case tempFileCreationFailed
    case annotationCancelled

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image for annotation"
        case .saveFailure:
            return "Failed to save annotated image"
        case .tempFileCreationFailed:
            return "Failed to create temporary file for annotation"
        case .annotationCancelled:
            return "Annotation session was cancelled"
        }
    }
}

// MARK: - Quick Look Coordinator for iOS 17+
// Removed @MainActor to fix Swift 6 isolation error - delegate methods are called from UIKit threads
class QuickLookCoordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    let photo: Photo
    var tempImageURL: URL?
    var onAnnotationComplete: ((UIImage) -> Void)?
    var onDismiss: (() -> Void)?

    init(photo: Photo) {
        self.photo = photo
        super.init()
    }

    deinit {
        // Clean up temp file directly in deinit to avoid MainActor conflicts
        if let url = tempImageURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func cleanupTempFiles() {
        if let url = tempImageURL {
            try? FileManager.default.removeItem(at: url)
            tempImageURL = nil
        }
    }

    // MARK: - Public Methods

    func prepareForAnnotation() -> Bool {
        // Prepare temp file for Quick Look using only the original image
        guard let image = photo.loadOriginalImage(),
              let data = image.jpegData(compressionQuality: 1.0) else {
            Logger.warn("Failed to prepare image for annotation")
            return false
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(photo.id?.uuidString ?? UUID().uuidString)_annotation.jpg")

        do {
            try data.write(to: tempURL)
            tempImageURL = tempURL
            Logger.info("Prepared temp file for annotation: \(tempURL.path)")
            return true
        } catch {
            Logger.error("Failed to create temp file: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - QLPreviewControllerDataSource

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return tempImageURL != nil ? 1 : 0
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        Logger.info("Providing preview item: \(tempImageURL?.path ?? "nil")")
        return tempImageURL! as QLPreviewItem
    }

    // MARK: - QLPreviewControllerDelegate

    func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        // Enable markup tools in iOS 17+
        Logger.info("Enabling markup editing mode for photo \(photo.sequenceNumber)")
        return .updateContents
    }

    func previewController(_ controller: QLPreviewController, didUpdateContentsOf previewItem: QLPreviewItem) {
        Logger.info("Quick Look contents updated for photo \(photo.sequenceNumber)")
        guard let url = previewItem.previewItemURL else {
            Logger.warn("No preview item URL received")
            return
        }

        Task { @MainActor in
            do {
                // Short delay to ensure annotated file is fully written to disk
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

                let imageData = try Data(contentsOf: url)
                guard let annotatedImage = UIImage(data: imageData) else {
                    throw AnnotationError.imageConversionFailed
                }

                // Replace the original file with the annotated image (SINGLE-FILE APPROACH)
                try photo.replaceWithAnnotatedImage(annotatedImage)

                Logger.info("Successfully saved annotated image for photo \(photo.sequenceNumber)")
                Logger.info("� Original file replaced with annotated version")
                onAnnotationComplete?(annotatedImage)
            } catch {
                Logger.error("Error saving annotation for photo \(photo.sequenceNumber): \(error.localizedDescription)")
                // Still notify completion to close the view
                onAnnotationComplete?(photo.loadOriginalImage() ?? UIImage())
            }
        }
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        Logger.info("Quick Look dismissed for photo \(photo.sequenceNumber)")
        // Clean up temp files
        cleanupTempFiles()
        onDismiss?()
    }

    func previewController(_ controller: QLPreviewController, didFailWithError error: Error) {
        Logger.error("Quick Look failed with error: \(error.localizedDescription)")
        cleanupTempFiles()
        onDismiss?()
    }
}

// MARK: - Quick Look Annotation View for SwiftUI (iOS 17+)

struct QuickLookAnnotationView: UIViewControllerRepresentable {
    let photo: Photo
    @Binding var isPresented: Bool
    let onAnnotationComplete: (UIImage) -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> QuickLookCoordinator {
        let coordinator = QuickLookCoordinator(photo: photo)
        coordinator.onAnnotationComplete = { annotatedImage in
            Logger.info("Annotation complete callback triggered")
            onAnnotationComplete(annotatedImage)
        }
        coordinator.onDismiss = {
            Logger.info("Annotation dismiss callback triggered")
            isPresented = false
        }
        return coordinator
    }

    func makeUIViewController(context: Context) -> UIViewController {
        Logger.info("Creating Quick Look UIViewController for photo \(photo.sequenceNumber)")
        return UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented && uiViewController.presentedViewController == nil {
            presentQuickLook(from: uiViewController, context: context)
        } else if !isPresented && uiViewController.presentedViewController != nil {
            Logger.info("Dismissing Quick Look")
            uiViewController.dismiss(animated: true)
        }
    }

    private func presentQuickLook(from viewController: UIViewController, context: Context) {
        Logger.info("Attempting to present Quick Look for photo \(photo.sequenceNumber)")

        // Ensure image is prepared for annotation
        guard context.coordinator.prepareForAnnotation() else {
            Logger.error("Failed to prepare for annotation - dismissing")
            isPresented = false
            return
        }

        let qlController = QLPreviewController()
        qlController.dataSource = context.coordinator
        qlController.delegate = context.coordinator

        // iOS 17+ specific configurations
        if #available(iOS 17.0, *) {
            qlController.navigationItem.rightBarButtonItems = []
            qlController.modalPresentationStyle = .fullScreen
        }

        viewController.present(qlController, animated: true)

        Logger.info("Quick Look presented successfully")
    }
}

// MARK: - Debug Extension for Quick Look (Single-File Architecture)
extension QuickLookAnnotationView {
    /// Helper method to verify annotation setup for single-file architecture
    static func debugAnnotationInfo(for photo: Photo) -> String {
        let singleFilePath = PhotoStorage.imageDirectoryURL?.appendingPathComponent(photo.imageFilename ?? "") ?? URL(fileURLWithPath: "")
        let cacheKey = photo.imageFilename ?? photo.id?.uuidString ?? ""

        return """
        DEBUG: Single-File Photo Annotation Info
        - Photo ID: \(photo.id?.uuidString ?? "No ID")
        - Sequence #: \(photo.sequenceNumber)
        - Single File: \(singleFilePath.path)
        - Has Annotations: \(photo.hasAnnotations)
        - Is Annotated: \(photo.isAnnotated)
        - Cache Key: \(cacheKey)
        - File Exists: \(FileManager.default.fileExists(atPath: singleFilePath.path))
        """
    }
}

// MARK: - Preview Extension for Testing
extension QuickLookCoordinator {
    /// Creates a mock photo for preview/testing
    static func createMockPhotoForTesting() -> Photo {
        let context = PersistenceController.shared.container.viewContext
        let photo = Photo(context: context)
        photo.id = UUID()
        photo.sequenceNumber = 1
        photo.imageFilename = "mock_image.jpg"
        photo.timestamp = Date()
        photo.sessionID = UUID().uuidString
        photo.notes = "Test photo for annotation"
        return photo
    }
}
