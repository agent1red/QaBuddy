// TemplateEntitySchemas.swift
// Design Template Entity Schema for QA Buddy PU/NC Template System
// Subtask 1.1: Design Template Entity Schema - Phase 3.1

import Foundation
import CoreData 

/// Core Data Entity: InspectionTemplate
/// Master template definition supporting both Velocity and CMES coordinate systems
class InspectionTemplate: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var templateType: String // "PU" or "NC"
    @NSManaged var isBuiltIn: Bool
    @NSManaged var fieldConfigurations: Data? // JSON encoded [TemplateFieldConfiguration]
    @NSManaged var createdDate: Date
    @NSManaged var lastModified: Date

    // Relationships
    @NSManaged var writeups: Set<PUWriteup>

    // Convenience methods
    var decodedFieldConfigurations: [TemplateFieldConfiguration] {
        guard let data = fieldConfigurations,
              let configs = try? JSONDecoder().decode([TemplateFieldConfiguration].self, from: data) else {
            return []
        }
        return configs
    }

    func setFieldConfigurations(_ configs: [TemplateFieldConfiguration]) {
        fieldConfigurations = try? JSONEncoder().encode(configs)
    }
}

/// Core Data Entity: PUWriteup
/// Individual write-up records with coordinate system support
class PUWriteup: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var sessionId: UUID
    @NSManaged var coordinateSystem: String // "Velocity" or "CMES"
    @NSManaged var itemId: Int64
    @NSManaged var itemDescription: String
    @NSManaged var irm: String // International Repair Manual
    @NSManaged var partNumber: String
    @NSManaged var location: String
    @NSManaged var xCoordinate: String? // "X" (Velocity) or "STA" (CMES)
    @NSManaged var yCoordinate: String? // "Y" (Velocity) or "WL" (CMES)
    @NSManaged var zCoordinate: String? // "Z" (Velocity) or "BL" (CMES)
    @NSManaged var issue: String
    @NSManaged var shouldBe: String
    @NSManaged var photoIds: Data? // JSON encoded [UUID]
    @NSManaged var templateUsed: String?
    @NSManaged var status: String // Status enum as String
    @NSManaged var createdDate: Date

    // Relationships
    @NSManaged var template: InspectionTemplate?

    // Convenience methods
    var decodedPhotoIds: [UUID] {
        guard let data = photoIds,
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return ids
    }

    func setPhotoIds(_ ids: [UUID]) {
        photoIds = try? JSONEncoder().encode(ids)
    }

    // Computeds for coordinate labels based on system
    var coordinateLabels: CoordinateLabels {
        switch coordinateSystem {
        case "Velocity":
            return VelocityCoordinateLabels()
        case "CMES":
            return CMESCoordinateLabels()
        default:
            return VelocityCoordinateLabels() // Default fallback
        }
    }

    // Formatted location string
    var formattedLocation: String {
        let x = xCoordinate ?? "UNK"
        let y = yCoordinate ?? "UNK"
        let z = zCoordinate ?? "UNK"
        return "(\(coordinateLabels.xLabel): \(x) \(coordinateLabels.yLabel): \(y) \(coordinateLabels.zLabel): \(z))"
    }
}

/// Core Data Entity: ZoneConfiguration
/// Customizable zones and activity types for QA inspections
class ZoneConfiguration: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var zones: Data? // JSON encoded [String]
    @NSManaged var activityTypes: Data? // JSON encoded [String]
    @NSManaged var isDefault: Bool
    @NSManaged var lastModified: Date

    // Convenience methods
    var decodedZones: [String] {
        guard let data = zones,
              let zoneList = try? JSONDecoder().decode([String].self, from: data) else {
            return DefaultConfigurations.aircraftZones
        }
        return zoneList
    }

    var decodedActivityTypes: [String] {
        guard let data = activityTypes,
              let activityList = try? JSONDecoder().decode([String].self, from: data) else {
            return DefaultConfigurations.activityTypes
        }
        return activityList
    }

    func setZones(_ zoneList: [String]) {
        zones = try? JSONEncoder().encode(zoneList)
    }

    func setActivityTypes(_ activityList: [String]) {
        activityTypes = try? JSONEncoder().encode(activityList)
    }
}

/// Core Data Entity: TemplateField
/// Field visibility and configuration for templates
class TemplateField: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var fieldName: String
    @NSManaged var visibility: String // FieldVisibility enum as String
    @NSManaged var defaultValue: String?
    @NSManaged var prefix: String?
    @NSManaged var suffix: String?
    @NSManaged var validation: String? // Regex pattern

    // Relationships
    @NSManaged var template: InspectionTemplate

    // Computed property for enum value
    var fieldVisibility: FieldVisibility {
        FieldVisibility(rawValue: visibility) ?? .visible
    }
}

// MARK: - Supporting Types

/// Coordinate system protocols and implementations
protocol CoordinateSystem: Sendable {
    var systemName: String { get }
    var xLabel: String { get } // "X" or "STA"
    var yLabel: String { get } // "Y" or "WL"
    var zLabel: String { get } // "Z" or "BL"
}

/// Coordinate labels protocol
protocol CoordinateLabels {
    var xLabel: String { get }
    var yLabel: String { get }
    var zLabel: String { get }
}

/// Velocity coordinate system (X:Y:Z)
struct VelocitySystem: CoordinateSystem {
    let systemName = "Velocity"
    let xLabel = "X"
    let yLabel = "Y"
    let zLabel = "Z"
}

struct VelocityCoordinateLabels: CoordinateLabels {
    let xLabel = "X"
    let yLabel = "Y"
    let zLabel = "Z"
}

/// CMES coordinate system (STA:WL:BL)
struct CMESSystem: CoordinateSystem {
    let systemName = "CMES"
    let xLabel = "STA"
    let yLabel = "WL"
    let zLabel = "BL"
}

struct CMESCoordinateLabels: CoordinateLabels {
    let xLabel = "STA"
    let yLabel = "WL"
    let zLabel = "BL"
}

/// Field visibility configuration
enum FieldVisibility: String, Codable, Sendable {
    case visible
    case hidden
    case required
}

/// Template field configuration struct
struct TemplateFieldConfiguration: Codable, Sendable {
    let fieldName: String
    var visibility: FieldVisibility
    var defaultValue: String?
    var prefix: String?
    var suffix: String?
    var validation: String? // Regex pattern

    init(fieldName: String,
         visibility: FieldVisibility = .visible,
         defaultValue: String? = nil,
         prefix: String? = nil,
         suffix: String? = nil) {
        self.fieldName = fieldName
        self.visibility = visibility
        self.defaultValue = defaultValue
        self.prefix = prefix
        self.suffix = suffix
        self.validation = nil
    }
}

/// Write-up status enum
enum WriteupStatus: String, Codable {
    case draft
    case pending
    case reviewed
    case approved
    case completed
}

/// Default configurations for aviation QA
struct DefaultConfigurations {
    /// Aircraft zones for inspection
    static let aircraftZones = [
        // Decks
        "A Deck",           // Passenger deck (top)
        "B Deck",           // Cargo deck (bottom)

        // Wings & Control Surfaces
        "Left Wing",
        "Right Wing",
        "Empennage",        // Tail section

        // Landing Gear
        "Left MLG",         // Main Landing Gear
        "Right MLG",
        "Left Wheel Well",
        "Right Wheel Well",
        "NLG",              // Nose Landing Gear

        // Cargo & Sections
        "Forward Cargo",
        "Aft Cargo",
        "48 Section",       // Aft pressure bulkhead area

        // Systems Bays
        "FW EE Bay",        // Forward Electronic Equipment
        "Aft EE Bay",       // Aft Electronic Equipment
        "Left AC Bay",      // Air Conditioning
        "Right AC Bay",
        "Flight Deck",

        // Power Units
        "Left Engine",
        "Right Engine",
        "APU"               // Auxiliary Power Unit
    ]

    /// Activity types for inspections
    static let activityTypes = [
        "Pre-Flight",
        "Post-Flight",
        "General Maintenance",
        "AOG"               // Aircraft On Ground
    ]
}
