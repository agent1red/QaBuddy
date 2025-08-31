//
//  PhotoManager.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/27/25.
//

import Foundation
import CoreData
import UIKit
import CoreLocation


// MARK: - Photo Metadata Structure

struct PhotoMetadata {
    let sequenceNumber: Int64
    let sessionID: String
    let location: CLLocationCoordinate2D?
    let deviceOrientation: String
    let notes: String?

    init(sequenceNumber: Int64 = 1,
         sessionID: String = "default",
         location: CLLocationCoordinate2D? = nil,
         deviceOrientation: String = UIDevice.current.orientation.description,
         notes: String? = nil) {
        self.sequenceNumber = sequenceNumber
        self.sessionID = sessionID
        self.location = location
        self.deviceOrientation = deviceOrientation
        self.notes = notes
    }
}

// MARK: - PhotoManager Class

class PhotoManager: @unchecked Sendable {
    private let context: NSManagedObjectContext
    private let photoStorage = PhotoStorage()

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    // MARK: - CRUD Operations

    /// Save a new photo to Core Data and storage
    func savePhoto(image: UIImage, metadata: PhotoMetadata) async throws {
        // Generate unique filenames
        let uuid = UUID()
        let imageFilename = "photo_\(uuid.uuidString).jpg"
        let thumbnailFilename = "thumb_\(uuid.uuidString).jpg"

        // Save the full-size image asynchronously
        // Thumbnail creation and saving is done in a detached task to avoid blocking the current task
        // Both image saving and thumbnail generation/saving are awaited concurrently for efficiency

        async let saveThumbnail: Void = Task.detached(priority: .userInitiated) {
            // Generate thumbnail on background thread
            let thumbnail = ThumbnailGenerator.generate(image: image, size: .medium)
            // Save thumbnail asynchronously within the detached task
            try await self.photoStorage.saveThumbnail(thumbnail, filename: thumbnailFilename)
            // Cache the thumbnail after saving
            PhotoImageCache.shared.setThumbnail(thumbnail, forKey: thumbnailFilename)
        }.value

        // Save image directly and await thumbnail in parallel
        try await photoStorage.saveImage(image, filename: imageFilename)
        try await saveThumbnail

        // Cache the saved full-size image after saving
        PhotoImageCache.shared.setImage(image, forKey: imageFilename)

        print("Photo saved to storage successfully:")
        print("  Image: \(imageFilename)")
        print("  Thumbnail: \(thumbnailFilename)")
        print("  Sequence: \(metadata.sequenceNumber)")
        print("  Session: \(metadata.sessionID)")

        // --- Core Data persist ---
        var saveError: Error?
        context.performAndWait { [self] in
            do {
                // Insert
                let photo = Photo(context: context)
                photo.id = uuid
                photo.imageFilename = imageFilename
                photo.thumbnailFilename = thumbnailFilename
                photo.sequenceNumber = metadata.sequenceNumber
                photo.timestamp = Date()
                photo.sessionID = metadata.sessionID
                if let loc = metadata.location {
                    photo.latitude = loc.latitude
                    photo.longitude = loc.longitude
                }
                photo.deviceOrientation = metadata.deviceOrientation
                photo.notes = metadata.notes

                try context.save()
                #if DEBUG
                print("✅ Core Data: saved Photo \(uuid.uuidString)")
                #endif
            } catch {
                saveError = error
            }
        }
        if let e = saveError { throw e }
    }


    // TODO: Uncomment these methods after Core Data model is created:

    // Fetch photos for a specific session
     func fetchPhotos(forSession sessionID: String) throws -> [Photo] {
         let request = Photo.fetchRequest()
         request.predicate = NSPredicate(format: "sessionID == %@", sessionID)
         request.sortDescriptors = [NSSortDescriptor(key: "sequenceNumber", ascending: true)]
         request.fetchBatchSize = 40
         request.returnsObjectsAsFaults = true
         let photos = try context.fetch(request)
         return photos
       }

    // Fetch all photos
     func fetchAllPhotos() throws -> [Photo] {
         let request = Photo.fetchRequest()
         request.sortDescriptors = [
             NSSortDescriptor(key: "timestamp", ascending: false),
             NSSortDescriptor(key: "sequenceNumber", ascending: true)
         ]
         request.fetchBatchSize = 40
         request.returnsObjectsAsFaults = true
         let photos = try context.fetch(request)
         return photos
       }

    // Delete a photo and its associated files
     func deletePhoto(_ photo: Photo) async throws {
         if let imageURL = photo.imageURL {
             try? FileManager.default.removeItem(at: imageURL)
         }
         if let thumbnailURL = photo.thumbnailURL {
             try? FileManager.default.removeItem(at: thumbnailURL)
         }
         context.delete(photo)
         try context.save()
     }

    /// Update photo metadata
     func updatePhoto(_ photo: Photo, notes: String?) throws {
         photo.notes = notes
         try context.save()
     }

    /// Get next sequence number for a session
     func getNextSequenceNumber(forSession sessionID: String) throws -> Int64 {
         let photos = try fetchPhotos(forSession: sessionID)
         let maxSequence = photos.map { $0.sequenceNumber }.max() ?? 0
         return maxSequence + 1
     }

    /// Renumber photos in a session after deleting a specific sequence number
    func renumberPhotosAfter(deletionOf deletedSequence: Int64, in sessionID: String) throws {
        let request = Photo.fetchRequest()
        request.predicate = NSPredicate(format: "sessionID == %@ AND sequenceNumber > %d", sessionID, deletedSequence)
        request.sortDescriptors = [NSSortDescriptor(key: "sequenceNumber", ascending: true)]

        let photos = try context.fetch(request)

        // Decrement sequence numbers for photos after the deleted one
        for photo in photos {
            photo.sequenceNumber -= 1
        }

        try context.save()

        print("📝 Renumbered \(photos.count) photos in session '\(sessionID)' after deleting sequence #\(deletedSequence)")
    }

    /// Renumber all photos in a session to ensure consecutive sequence numbers
    func renumberSessionPhotos(in sessionID: String) throws {
        let photos = try fetchPhotos(forSession: sessionID).sorted { $0.sequenceNumber < $1.sequenceNumber }

        var expectedSequence: Int64 = 1
        for photo in photos {
            if photo.sequenceNumber != expectedSequence {
                photo.sequenceNumber = expectedSequence
                print("🔢 Renumbered photo \(photo.id?.uuidString ?? "unknown") to sequence #\(expectedSequence)")
            }
            expectedSequence += 1
        }

        try context.save()
    }

    /// Bulk delete photos with renumbering
    func deletePhotosWithRenumbering(_ photos: [Photo]) async throws {
        guard !photos.isEmpty else { return }

        // Group photos by session for efficient renumbering
        let sessionGroups = Dictionary(grouping: photos) { $0.sessionID ?? "unknown" }

        for (sessionID, sessionPhotos) in sessionGroups {
            // Sort by sequence number in descending order to delete highest first
            let sortedPhotos = sessionPhotos.sorted { $0.sequenceNumber > $1.sequenceNumber }

            for photo in sortedPhotos {
                try await deletePhoto(photo)
            }

            // Renumber remaining photos in this session
            try renumberSessionPhotos(in: sessionID)
        }
    }

    // TODO: Uncomment these methods after Core Data model is created:

    // MARK: - Image Loading

    /// Load full-size image asynchronously
     func loadImage(for photo: Photo) async throws -> UIImage {
         // Progressive loading: first load low-res via loadThumbnail(for:) before calling loadImage(for:)
         
         // Attempt to get cached image using photo.imageFilename or photo.id.uuidString
         let key = photo.imageFilename ?? photo.id?.uuidString ?? ""
         if let cachedImage = PhotoImageCache.shared.image(forKey: key) {
             return cachedImage
         }

         guard let imageURL = photo.imageURL else {
             throw PhotoManagerError.fileNotFound
         }
    
         return try await withCheckedThrowingContinuation { continuation in
             DispatchQueue.global(qos: .background).async {
                 do {
                     let imageData = try Data(contentsOf: imageURL)
                     guard let image = UIImage(data: imageData) else {
                         continuation.resume(throwing: PhotoManagerError.invalidImageData)
                         return
                     }
                     PhotoImageCache.shared.setImage(image, forKey: key)
                     continuation.resume(returning: image)
                 } catch {
                     continuation.resume(throwing: error)
                 }
             }
         }
     }

    /// Load thumbnail image synchronously (for faster gallery display)
     func loadThumbnail(for photo: Photo) -> UIImage? {
         let key = photo.thumbnailFilename ?? photo.id?.uuidString ?? ""
         if let cachedThumbnail = PhotoImageCache.shared.thumbnail(forKey: key) {
             return cachedThumbnail
         }

         guard let thumbnailURL = photo.thumbnailURL else {
             return nil
         }
    
         do {
             let data = try Data(contentsOf: thumbnailURL)
             if let thumbnail = UIImage(data: data) {
                 PhotoImageCache.shared.setThumbnail(thumbnail, forKey: key)
                 return thumbnail
             }
             return nil
         } catch {
             print("Failed to load thumbnail: \(error)")
             return nil
         }
     }
}

// MARK: - Supporting Classes

class PhotoStorage {
    static let imageDirectoryURL: URL? = {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let imagesDirectory = documentsDirectory.appendingPathComponent("Photos")
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        return imagesDirectory
    }()

    static let thumbnailDirectoryURL: URL? = {
        guard let imageDir = imageDirectoryURL else { return nil }
        let thumbnailsDirectory = imageDir.appendingPathComponent("Thumbnails")
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        return thumbnailsDirectory
    }()

    func saveImage(_ image: UIImage, filename: String) async throws {
        guard let imageURL = PhotoStorage.imageDirectoryURL?.appendingPathComponent(filename) else {
            throw PhotoManagerError.invalidPath
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoManagerError.jpegConversionFailed
        }

        try await Task {
            try jpegData.write(to: imageURL)
        }.value
    }

    func saveThumbnail(_ thumbnail: UIImage, filename: String) async throws {
        guard let thumbnailURL = PhotoStorage.thumbnailDirectoryURL?.appendingPathComponent(filename) else {
            throw PhotoManagerError.invalidPath
        }

        guard let jpegData = thumbnail.jpegData(compressionQuality: 0.75) else {
            throw PhotoManagerError.jpegConversionFailed
        }

        try await Task {
            try jpegData.write(to: thumbnailURL)
        }.value
    }
}

class ThumbnailGenerator {
    enum ThumbnailSize {
        case small  // 100x100
        case medium // 200x200
        case large  // 300x300

        var cgSize: CGSize {
            switch self {
            case .small: return CGSize(width: 100, height: 100)
            case .medium: return CGSize(width: 200, height: 200)
            case .large: return CGSize(width: 300, height: 300)
            }
        }
    }

    static func generate(image: UIImage, size: ThumbnailSize) -> UIImage {
        let targetSize = size.cgSize

        // Note: Background queueing for this operation is handled by PhotoManager (see savePhoto implementation).

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let thumbnail = renderer.image { context in
            let imageSize = image.size

            // Calculate aspect ratio
            let aspectRatio = min(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
            let scaledSize = CGSize(width: imageSize.width * aspectRatio, height: imageSize.height * aspectRatio)

            let origin = CGPoint(
                x: (targetSize.width - scaledSize.width) / 2.0,
                y: (targetSize.height - scaledSize.height) / 2.0
            )

            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }

        return thumbnail
    }
}



// MARK: - Extensions

extension UIDeviceOrientation {
    var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .portrait:
            return "Portrait"
        case .portraitUpsideDown:
            return "PortraitUpsideDown"
        case .landscapeLeft:
            return "LandscapeLeft"
        case .landscapeRight:
            return "LandscapeRight"
        case .faceUp:
            return "FaceUp"
        case .faceDown:
            return "FaceDown"
        @unknown default:
            return "Unknown"
        }
    }
}

// TODO: Uncomment this extension after Core Data model is created:

// MARK: - Core Data Extensions

 extension Photo {
     public var location: CLLocationCoordinate2D? {
         if latitude != 0.0 || longitude != 0.0 {
             return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
         }
         return nil
     }

     public var imageURL: URL? {
         guard let imageFilename = imageFilename,
               !imageFilename.isEmpty else {
             return nil
         }
         return PhotoStorage.imageDirectoryURL?.appendingPathComponent(imageFilename)
     }

     public var thumbnailURL: URL? {
         guard let thumbnailFilename = thumbnailFilename,
               !thumbnailFilename.isEmpty else {
             return nil
         }
         return PhotoStorage.thumbnailDirectoryURL?.appendingPathComponent(thumbnailFilename)
     }
 }

// MARK: - Errors

enum PhotoManagerError: Error {
    case fileNotFound
    case invalidImageData
    case jpegConversionFailed
    case invalidPath
    case saveFailed
    case initializeCoreDataFirst(String)
}
