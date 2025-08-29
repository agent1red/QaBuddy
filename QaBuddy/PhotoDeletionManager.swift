//
//  PhotoDeletionManager.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/28/25.
//

import Foundation
import CoreData
import UIKit

/// Manages permanent photo deletion operations with automatic renumbering
class PhotoDeletionManager {
    private let context: NSManagedObjectContext
    private let photoManager: PhotoManager
    private let sequenceManager: SequenceManager

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
         photoManager: PhotoManager = PhotoManager(),
         sequenceManager: SequenceManager = SequenceManager()) {
        self.context = context
        self.photoManager = photoManager
        self.sequenceManager = sequenceManager
    }

    // MARK: - Public Interface

    /// Delete a single photo with permanent deletion and renumbering
    func deletePhoto(_ photo: Photo) async throws {
        try await performDeletion([photo])
    }

    /// Delete multiple photos with permanent deletion and renumbering
    func deletePhotos(_ photos: [Photo]) async throws {
        try await performDeletion(photos)
    }

    // MARK: - Private Methods

    private func performDeletion(_ photos: [Photo]) async throws {
        // Sort by sequence number for proper renumbering
        let sortedPhotos = photos.sorted { $0.sequenceNumber < $1.sequenceNumber }

        // Perform all operations on MainActor (Core Data is not Sendable)
        try await MainActor.run {
            // Delete all photos from database and files
            for photo in sortedPhotos {
                print("🗑️ Deleting photo \(photo.sequenceNumber) from session \(photo.sessionID ?? "unknown")")

                // Delete files immediately
                deletePhotoFiles(photo)

                // Delete database record
                context.delete(photo)

                // Renumber subsequent photos in this session
                try renumberPhotosAfter(deletionOf: photo.sequenceNumber, in: photo.sessionID ?? "unknown")
            }

            // Save all changes in a single transaction
            try context.save()
            print("✅ Permanently deleted \(sortedPhotos.count) photos - no recovery possible")
        }
    }

    private func deletePhotoFiles(_ photo: Photo) {
        // Delete image file
        if let imageURL = photo.imageURL {
            do {
                try FileManager.default.removeItem(at: imageURL)
                print("🗂️ Deleted: \(imageURL.lastPathComponent)")
            } catch {
                print("⚠️ Could not delete image file: \(error)")
            }
        }

        // Delete thumbnail file
        if let thumbnailURL = photo.thumbnailURL {
            do {
                try FileManager.default.removeItem(at: thumbnailURL)
                print("🗂️ Deleted: \(thumbnailURL.lastPathComponent)")
            } catch {
                print("⚠️ Could not delete thumbnail file: \(error)")
            }
        }
    }

    private func renumberPhotosAfter(deletionOf deletedSequence: Int64, in sessionID: String) throws {
        // Find all photos in this session with higher sequence numbers
        let request = Photo.fetchRequest()
        request.predicate = NSPredicate(format: "sessionID == %@ AND sequenceNumber > %d", sessionID, deletedSequence)
        request.sortDescriptors = [NSSortDescriptor(key: "sequenceNumber", ascending: true)]

        let photosToRenumber = try context.fetch(request)

        print("🔢 Renumbering \(photosToRenumber.count) photos after deleting sequence #\(deletedSequence)")

        // Decrement sequence numbers
        for photo in photosToRenumber {
            let oldSequence = photo.sequenceNumber
            photo.sequenceNumber -= 1
            print("📝 Renumbered: Sequence \(oldSequence) → \(photo.sequenceNumber)")
        }

        // Update sequence manager if needed
        let nextSequence = try photoManager.getNextSequenceNumber(forSession: sessionID)
        if nextSequence > sequenceManager.currentSequence {
            sequenceManager.setSequence(nextSequence)
            print("🔢 Updated sequence manager to \(nextSequence)")
        }
    }
}

enum PhotoDeletionError: Error, LocalizedError {
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .deletionFailed(let reason):
            return "Failed to delete photos: \(reason)"
        }
    }
}
