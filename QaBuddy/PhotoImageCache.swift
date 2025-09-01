//
//  PhotoImageCache.swift
//  QaBuddy
//
//  Created for performance optimization and memory management
//

import Foundation
import UIKit

/// Singleton NSCache-based image cache for thumbnails and full-size images
final class PhotoImageCache {
    static let shared = PhotoImageCache()
    
    // Caches for thumbnails and full-size images
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let imageCache = NSCache<NSString, UIImage>()

    private init() {
        // Clear caches on memory warning
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearAllCaches),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Caching API

    func setThumbnail(_ image: UIImage, forKey key: String) {
        thumbnailCache.setObject(image, forKey: key as NSString)
    }
    
    func thumbnail(forKey key: String) -> UIImage? {
        thumbnailCache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        imageCache.setObject(image, forKey: key as NSString)
    }
    
    func image(forKey key: String) -> UIImage? {
        imageCache.object(forKey: key as NSString)
    }

    func removeImage(forKey key: String) {
        imageCache.removeObject(forKey: key as NSString)
    }

    func removeThumbnail(forKey key: String) {
        thumbnailCache.removeObject(forKey: key as NSString)
    }

    @objc func clearAllCaches() {
        thumbnailCache.removeAllObjects()
        imageCache.removeAllObjects()
        print("🧹 Cleared image caches due to memory warning.")
    }
}
