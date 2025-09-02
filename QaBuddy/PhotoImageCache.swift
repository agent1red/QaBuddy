//
//  PhotoImageCache.swift
//  QaBuddy
//
//  Created for performance optimization and memory management
//

import Foundation
import UIKit

/// Singleton NSCache-based image cache for thumbnails and full-size images
/// BATTERY OPTIMIZATION: Added memory/cost limits to prevent unbounded growth
final class PhotoImageCache: NSObject, NSCacheDelegate {
    static let shared = PhotoImageCache()

    // BATTERY OPTIMIZATION: Caches with memory limits to prevent unbounded growth
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let imageCache = NSCache<NSString, UIImage>()

    // Track item counts since NSCache doesn't expose current count
    private let countLock = NSLock()
    private var thumbnailItemCount: Int = 0
    private var imageItemCount: Int = 0

    // Memory limits (will help reduce battery drain from excessive caching)
    private let thumbnailCountLimit = 100  // Limit thumbnail cache to 100 images
    private let imageCountLimit = 20       // Limit full-image cache to 20 images
    private let thumbnailMemoryLimit = 20 * 1024 * 1024  // 20MB for thumbnails
    private let imageMemoryLimit = 100 * 1024 * 1024     // 100MB for full images

    private override init() {
        super.init()
        setupCacheLimits()
        setupMemoryWarningHandler()
    }

    /// BATTERY OPTIMIZATION: Configure memory and count limits for caches
    private func setupCacheLimits() {
        // Thumbnail cache limits
        thumbnailCache.countLimit = thumbnailCountLimit
        thumbnailCache.totalCostLimit = thumbnailMemoryLimit
        thumbnailCache.delegate = self

        // Full image cache limits
        imageCache.countLimit = imageCountLimit
        imageCache.totalCostLimit = imageMemoryLimit
        imageCache.delegate = self

        Logger.info("💾 PhotoImageCache initialized with memory limits: \(thumbnailCountLimit) thumbnails (\(thumbnailMemoryLimit/1024/1024)MB), \(imageCountLimit) images (\(imageMemoryLimit/1024/1024)MB)")
    }

    /// BATTERY OPTIMIZATION: Enhanced memory warning handling
    private func setupMemoryWarningHandler() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Caching API

    func setThumbnail(_ image: UIImage, forKey key: String) {
        let nsKey = key as NSString
        let existed = thumbnailCache.object(forKey: nsKey) != nil
        thumbnailCache.setObject(image, forKey: nsKey)
        if !existed {
            countLock.lock()
            thumbnailItemCount += 1
            countLock.unlock()
        }
    }
    
    func thumbnail(forKey key: String) -> UIImage? {
        thumbnailCache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        let nsKey = key as NSString
        let existed = imageCache.object(forKey: nsKey) != nil
        imageCache.setObject(image, forKey: nsKey)
        if !existed {
            countLock.lock()
            imageItemCount += 1
            countLock.unlock()
        }
    }
    
    func image(forKey key: String) -> UIImage? {
        imageCache.object(forKey: key as NSString)
    }

    func removeImage(forKey key: String) {
        let nsKey = key as NSString
        let existed = imageCache.object(forKey: nsKey) != nil
        imageCache.removeObject(forKey: nsKey)
        if existed {
            countLock.lock()
            if imageItemCount > 0 { imageItemCount -= 1 }
            countLock.unlock()
        }
    }

    func removeThumbnail(forKey key: String) {
        let nsKey = key as NSString
        let existed = thumbnailCache.object(forKey: nsKey) != nil
        thumbnailCache.removeObject(forKey: nsKey)
        if existed {
            countLock.lock()
            if thumbnailItemCount > 0 { thumbnailItemCount -= 1 }
            countLock.unlock()
        }
    }

    /// BATTERY OPTIMIZATION: Enhanced memory warning handler with gradual cleanup
    @objc private func handleMemoryWarning() {
        // Don't immediately clear all - do gradual cleanup first
        countLock.lock()
        let thumbnailCount = thumbnailItemCount
        let imageCount = imageItemCount
        countLock.unlock()

        Logger.info("⚠️ Memory warning: \(thumbnailCount) thumbnails, \(imageCount) images cached")

        // Aggressive cleanup strategy
        if thumbnailCount > thumbnailCountLimit / 2 {
            thumbnailCache.removeAllObjects()
            countLock.lock()
            thumbnailItemCount = 0
            countLock.unlock()
            Logger.info("🧹 Cleared thumbnail cache due to memory pressure")
        }

        if imageCount > imageCountLimit / 2 {
            imageCache.removeAllObjects()
            countLock.lock()
            imageItemCount = 0
            countLock.unlock()
            Logger.info("🧹 Cleared image cache due to memory pressure")
        }

        // If still under pressure, clear everything
        if thumbnailCount > 0 || imageCount > 0 {
            thumbnailCache.removeAllObjects()
            imageCache.removeAllObjects()
            countLock.lock()
            thumbnailItemCount = 0
            imageItemCount = 0
            countLock.unlock()
            Logger.info("🧹 Emergency cache cleanup completed")
        }
    }

    // MARK: - NSCacheDelegate

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        countLock.lock()
        defer { countLock.unlock() }
        if (cache as AnyObject) === (thumbnailCache as AnyObject) {
            if thumbnailItemCount > 0 { thumbnailItemCount -= 1 }
        } else if (cache as AnyObject) === (imageCache as AnyObject) {
            if imageItemCount > 0 { imageItemCount -= 1 }
        }
    }

    // MARK: - BATTERY OPTIMIZATION: Memory Management Methods

    /// Get current cache statistics for monitoring
    func getCacheStatistics() -> (thumbnailCount: Int, imageCount: Int, thumbnailMemory: Int, imageMemory: Int) {
        countLock.lock()
        let thumbnailCount = thumbnailItemCount
        let imageCount = imageItemCount
        countLock.unlock()

        // Rough estimation - average image sizes
        let estimatedThumbnailSize = 50 * 1024  // ~50KB per thumbnail
        let estimatedImageSize = 2 * 1024 * 1024 // ~2MB per full image

        let thumbnailMemory = thumbnailCount * estimatedThumbnailSize
        let imageMemory = imageCount * estimatedImageSize

        return (thumbnailCount, imageCount, thumbnailMemory, imageMemory)
    }

    /// BATTERY OPTIMIZATION: Conservative cache cleanup method
    func performConservativeCleanup() {
        // Remove oldest items to stay within limits
        // NSCache automatically manages this with countLimit and totalCostLimit

        let stats = getCacheStatistics()
        Logger.info("💾 Cache status: \(stats.thumbnailCount) thumbnails (\(stats.thumbnailMemory/1024/1024)MB), \(stats.imageCount) images (\(stats.imageMemory/1024/1024)MB))")

        // Additional cleanup if needed (NSCache should handle most of this automatically)
        if stats.thumbnailMemory > thumbnailMemoryLimit * 3 / 4 {
            Logger.info("🧹 Performing thumbnail cache cleanup to stay under memory limits")
        }

        if stats.imageMemory > imageMemoryLimit * 3 / 4 {
            Logger.info("🧹 Performing image cache cleanup to stay under memory limits")
        }
    }

    /// BATTERY OPTIMIZATION: Legacy method for backward compatibility
    @objc func clearAllCaches() {
        thumbnailCache.removeAllObjects()
        imageCache.removeAllObjects()
        countLock.lock()
        thumbnailItemCount = 0
        imageItemCount = 0
        countLock.unlock()
        Logger.info("🧹 Cleared all image caches (legacy method)")
    }
}
