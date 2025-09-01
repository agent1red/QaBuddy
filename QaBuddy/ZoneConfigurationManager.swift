//  ZoneConfigurationManager.swift
//  Zone Configuration Manager for QA Buddy PU/NC Template System
//  Phase 3.1 - Subtask 3.2: Implement Zone Configuration Manager
//

import Foundation
import SwiftUI
import CoreData

/// Manager for aircraft zone and activity type configurations
/// Handles loading, saving, and managing custom zone configurations in Core Data
@MainActor
final class ZoneConfigurationManager: ObservableObject {
    static let shared = ZoneConfigurationManager()

    @Published var currentZones: [String] = []
    @Published var currentActivityTypes: [String] = []

    private let context: NSManagedObjectContext
    private let userDefaultsKey = "lastZoneConfigurationFetch"

    // Default configurations (hard-coded to avoid scope issues)
    private let defaultAircraftZones = [
        "A Deck", "B Deck", "Left Wing", "Right Wing", "Empennage",
        "Left MLG", "Right MLG", "Left Wheel Well", "Right Wheel Well", "NLG",
        "Forward Cargo", "Aft Cargo", "48 Section",
        "FW EE Bay", "Aft EE Bay", "Left AC Bay", "Right AC Bay", "Flight Deck",
        "Left Engine", "Right Engine", "APU"
    ]

    private let defaultActivityTypes = [
        "Pre-Flight", "Post-Flight", "General Maintenance", "AOG"
    ]

    private init() {
        self.context = PersistenceController.shared.container.viewContext
        Task {
            await loadConfiguration()
        }
    }

    /// Load zone configuration from Core Data or create default
    func loadConfiguration() async {
        let fetchRequest = ZoneConfiguration.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "lastModified", ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            let configurations = try context.fetch(fetchRequest)
            if let config = configurations.first {
                // Decode zones from JSON string
                if let zonesString = config.zones {
                    currentZones = decodeStringArray(from: zonesString) ?? defaultAircraftZones
                } else {
                    currentZones = defaultAircraftZones
                }

                // Decode activity types from JSON string
                if let activitiesString = config.activityTypes {
                    currentActivityTypes = decodeStringArray(from: activitiesString) ?? defaultActivityTypes
                } else {
                    currentActivityTypes = defaultActivityTypes
                }
            } else {
                await createDefaultConfiguration()
            }

            // Update UserDefaults timestamp
            UserDefaults.standard.set(Date(), forKey: userDefaultsKey)

        } catch {
            print("Failed to load zone configuration: \(error)")
            // Fall back to defaults
            currentZones = defaultAircraftZones
            currentActivityTypes = defaultActivityTypes
        }
    }

    /// Create and save default configuration
    private func createDefaultConfiguration() async {
        currentZones = defaultAircraftZones
        currentActivityTypes = defaultActivityTypes
        await saveConfiguration()
    }

    /// Add a custom zone if it doesn't already exist
    /// - Parameter zone: Zone name to add
    func addCustomZone(_ zone: String) async {
        let trimmedZone = zone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedZone.isEmpty,
              !currentZones.contains(trimmedZone),
              trimmedZone.count <= 100 else { return }

        currentZones.append(trimmedZone)
        await saveConfiguration()
    }

    /// Remove a custom zone (only if it's not a built-in default)
    /// - Parameter zone: Zone name to remove
    func removeZone(_ zone: String) async {
        guard currentZones.contains(zone),
              !defaultAircraftZones.contains(zone) else { return }

        currentZones.removeAll { $0 == zone }
        await saveConfiguration()
    }

    /// Add a custom activity type
    /// - Parameter activity: Activity type to add
    func addCustomActivity(_ activity: String) async {
        let trimmedActivity = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedActivity.isEmpty,
              !currentActivityTypes.contains(trimmedActivity),
              trimmedActivity.count <= 100 else { return }

        currentActivityTypes.append(trimmedActivity)
        await saveConfiguration()
    }

    /// Remove a custom activity type
    /// - Parameter activity: Activity type to remove
    func removeActivity(_ activity: String) async {
        guard currentActivityTypes.contains(activity),
              !defaultActivityTypes.contains(activity) else { return }

        currentActivityTypes.removeAll { $0 == activity }
        await saveConfiguration()
    }

    /// Get custom zones only (excluding defaults)
    var customZones: [String] {
        currentZones.filter { !defaultAircraftZones.contains($0) }
    }

    /// Get custom activity types only (excluding defaults)
    var customActivityTypes: [String] {
        currentActivityTypes.filter { !$0.isEmpty && !defaultActivityTypes.contains($0) }
    }

    /// Check if configuration has custom zones
    var hasCustomZones: Bool {
        !customZones.isEmpty
    }

    /// Check if configuration has custom activity types
    var hasCustomActivityTypes: Bool {
        !customActivityTypes.isEmpty
    }

    /// Save current configuration to Core Data
    private func saveConfiguration() async {
        // Remove existing configuration
        let deleteRequest = ZoneConfiguration.fetchRequest()
        do {
            let existingConfigs = try context.fetch(deleteRequest)
            for config in existingConfigs {
                context.delete(config)
            }
        } catch {
            print("Failed to delete existing configurations: \(error)")
        }

        // Create new configuration
        let newConfig = ZoneConfiguration(context: context)
        newConfig.id = UUID()

        // Encode zones array as JSON string for Core Data
        if let zonesString = encodeStringArray(currentZones) {
            newConfig.zones = zonesString
        }

        // Encode activity types array as JSON string for Core Data
        if let activitiesString = encodeStringArray(currentActivityTypes) {
            newConfig.activityTypes = activitiesString
        }

        newConfig.isDefault = false
        newConfig.lastModified = Date()

        do {
            try context.save()
            print("Zone configuration saved successfully")
        } catch {
            print("Failed to save zone configuration: \(error)")
            context.rollback()
        }
    }

    /// Reset to default configuration
    func resetToDefaults() async {
        currentZones = defaultAircraftZones
        currentActivityTypes = defaultActivityTypes
        await saveConfiguration()
    }

    // MARK: - JSON Encoding/Decoding Helpers

    /// Decode string array from JSON string
    private func decodeStringArray(from jsonString: String) -> [String]? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode([String].self, from: jsonData)
        } catch {
            print("Failed to decode string array from JSON: \(error)")
            return nil
        }
    }

    /// Encode string array to JSON string
    private func encodeStringArray(_ array: [String]) -> String? {
        do {
            let jsonData = try JSONEncoder().encode(array)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("Failed to encode string array to JSON: \(error)")
            return nil
        }
    }
}
