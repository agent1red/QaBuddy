// ValidationFramework.swift
// Comprehensive validation system for QA Buddy PU/NC Template System
// Phase 3.1 - Subtask 7.1: Create Validation Framework

import Foundation
import CoreData

/// Comprehensive validation errors for QA Buddy template system
/// Implements LocalizedError for user-friendly error messages
enum TemplateValidationError: LocalizedError {
    // Field validation errors
    case missingRequiredField(String)
    case missingRequiredCoordForLocation
    case invalidCoordinateRange(String, expected: String)

    // Template validation errors
    case duplicateTemplateName(String)
    case invalidTemplateConfiguration(String)
    case invalidTemplateType(String)

    // PUWriteup validation errors
    case invalidCoordinateSystem(String)
    case mismatchedCoordinateFields(String)
    case invalidDateRange
    case missingSessionId
    case invalidPhotoIds

    // Aviation-specific errors
    case invalidZoneLocation(String)
    case invalidActivityType(String)

    /// Localized error description for user display
    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Required field missing: \(field)"
        case .missingRequiredCoordForLocation:
            return "Location provided but coordinates are missing. Coordinate fields must be filled when location is specified."
        case .invalidCoordinateRange(let coord, let expected):
            return "Invalid coordinate value '\(coord)'. Expected format: \(expected)"
        case .duplicateTemplateName(let name):
            return "A template with name '\(name)' already exists"
        case .invalidTemplateConfiguration(let details):
            return "Template configuration error: \(details)"
        case .invalidTemplateType(let type):
            return "Invalid template type: \(type). Must be 'PU' or 'NC'"
        case .invalidCoordinateSystem(let system):
            return "Invalid coordinate system: \(system). Must be 'Velocity' or 'CMES'"
        case .mismatchedCoordinateFields(let details):
            return "Coordinate system mismatch: \(details)"
        case .invalidDateRange:
            return "Invalid date range. Creation date must be before or equal to the last modified date"
        case .missingSessionId:
            return "Session ID is required for write-ups"
        case .invalidPhotoIds:
            return "Invalid photo IDs. Must be valid UUIDs"
        case .invalidZoneLocation(let zone):
            return "Invalid zone location: \(zone)"
        case .invalidActivityType(let activity):
            return "Invalid activity type: \(activity)"
        }
    }

    /// Detailed failure reason
    var failureReason: String? {
        switch self {
        case .missingRequiredField:
            return "A required field in the inspection template is empty"
        case .missingRequiredCoordForLocation:
            return "Aviation standards require coordinates when location is specified"
        case .invalidCoordinateRange:
            return "Coordinate format doesn't match aviation standards"
        case .duplicateTemplateName:
            return "Template names must be unique within the system"
        case .invalidTemplateConfiguration:
            return "Template configuration is malformed"
        case .invalidTemplateType:
            return "Template type must follow aviation documentation standards"
        case .invalidCoordinateSystem:
            return "Coordinate system must be supported by the application"
        case .mismatchedCoordinateFields:
            return "All coordinate fields must use the same coordinate system"
        case .invalidDateRange:
            return "Write-up dates must follow chronological order"
        case .missingSessionId:
            return "All write-ups must be associated with an inspection session"
        case .invalidPhotoIds:
            return "Photo references must be valid identifiers"
        case .invalidZoneLocation:
            return "Zone must be specified in aircraft configuration"
        case .invalidActivityType:
            return "Activity type must match maintenance workflow"
        }
    }

    /// Recovery suggestions for users
    var recoverySuggestion: String? {
        switch self {
        case .missingRequiredField:
            return "Fill in the required field or change the template to make it optional"
        case .missingRequiredCoordForLocation:
            return "Either provide all coordinate values or leave location field empty"
        case .invalidCoordinateRange:
            return "Check coordinate format matches Velocity (X:Y:Z) or CMES (STA:WL:BL) system"
        case .duplicateTemplateName:
            return "Choose a different name for the template"
        case .invalidTemplateConfiguration:
            return "Verify template field configurations and try again"
        case .invalidTemplateType:
            return "Change to 'PU' for Positive write-ups or 'NC' for Non-Conformance"
        case .invalidCoordinateSystem:
            return "Switch between Velocity (X:Y:Z) and CMES (STA:WL:BL) systems"
        case .mismatchedCoordinateFields:
            return "Clear all coordinates and set them consistently"
        case .invalidDateRange:
            return "Ensure creation date is not in the future"
        case .missingSessionId:
            return "Start a new inspection session or select an existing one"
        case .invalidPhotoIds:
            return "Remove invalid photo references"
        case .invalidZoneLocation:
            return "Select a valid aircraft zone from configuration"
        case .invalidActivityType:
            return "Choose a valid activity type from current configuration"
        }
    }

    /// Help anchor for further reading
    var helpAnchor: String? {
        switch self {
        case .missingRequiredField, .invalidTemplateConfiguration:
            return "template-configuration"
        case .missingRequiredCoordForLocation, .invalidCoordinateRange, .mismatchedCoordinateFields, .invalidCoordinateSystem:
            return "coordinate-systems"
        case .invalidTemplateType:
            return "pu-nc-standards"
        case .invalidZoneLocation:
            return "aircraft-zones"
        case .invalidActivityType:
            return "activity-types"
        default:
            return "validation-errors"
        }
    }
}

/// Validation result structure for comprehensive validation reporting
struct ValidationResult {
    let isValid: Bool
    let errors: [TemplateValidationError]
    let warnings: [String]

    /// Convenience initialization for valid results
    static var valid: ValidationResult {
        ValidationResult(isValid: true, errors: [], warnings: [])
    }

    /// Convenience initialization for invalid results with a single error
    static func invalid(_ error: TemplateValidationError) -> ValidationResult {
        ValidationResult(isValid: false, errors: [error], warnings: [])
    }

    /// Add additional error to result
    func addingError(_ error: TemplateValidationError) -> ValidationResult {
        ValidationResult(isValid: false, errors: errors + [error], warnings: warnings)
    }

    /// Add warning to result
    func addingWarning(_ warning: String) -> ValidationResult {
        ValidationResult(isValid: isValid, errors: errors, warnings: warnings + [warning])
    }

    /// Generate user-friendly validation summary
    var summary: String {
        let errorCount = errors.count
        let warningCount = warnings.count

        if errorCount == 0 && warningCount == 0 {
            return "Validation successful"
        }

        var summary = ""
        if errorCount > 0 {
            summary += "\(errorCount) validation error\(errorCount == 1 ? "" : "s")"
        }
        if warningCount > 0 {
            if !summary.isEmpty {
                summary += " and "
            }
            summary += "\(warningCount) warning\(warningCount == 1 ? "" : "s")"
        }
        return summary
    }
}

/// Main template validator implementing comprehensive validation logic
/// Conforms to Sendable for Swift 6 compatibility
@MainActor
final class TemplateValidator: Sendable {
    // MARK: - Validation Methods

    /// Validate template field configurations
    /// - Parameter fieldConfigs: Array of field configuration entities to validate
    /// - Returns: ValidationResult indicating configuration issues
    static func validateFieldConfigurations(_ fieldConfigs: [TemplateFieldConfiguration]) -> ValidationResult {
        var result = ValidationResult.valid

        for config in fieldConfigs {
            if config.fieldName.isEmpty {
                result = result.addingError(.invalidTemplateConfiguration("Empty field name in configuration"))
            }
        }

        return result
    }

    /// Validate template type
    /// - Parameter templateType: The template type string to validate
    /// - Returns: ValidationResult with type validation
    static func validateTemplateType(_ templateType: String) -> ValidationResult {
        if templateType != "PU" && templateType != "NC" {
            return ValidationResult.invalid(.invalidTemplateType(templateType))
        }
        return .valid
    }

    /// Validate coordinate system string
    /// - Parameter coordinateSystem: The coordinate system name to validate
    /// - Returns: ValidationResult with system validation
    static func validateCoordinateSystem(_ coordinateSystem: String) -> ValidationResult {
        if coordinateSystem != "Velocity" && coordinateSystem != "CMES" {
            return ValidationResult.invalid(.invalidCoordinateSystem(coordinateSystem))
        }
        return .valid
    }

    // MARK: - Core Validation Methods

    /// Validate individual coordinate value for Velocity system (X:Y:Z)
    /// - Parameters:
    ///   - coord: The coordinate value to validate
    ///   - system: The coordinate system (Velocity/CMES)
    /// - Returns: ValidationResult with coordinate validation
    static func validateCoordinate(_ coord: String, forCoordinateSystem system: any CoordinateSystem) -> ValidationResult {
        guard !coord.isEmpty else { return .valid }

        if coord == "UNK" { return .valid }

        if system.systemName == "Velocity" {
            // Velocity uses numeric values
            if Double(coord) == nil {
                return ValidationResult.invalid(.invalidCoordinateRange(coord, expected: "Numeric value (X:Y:Z format) or UNK"))
            }
        } else if system.systemName == "CMES" {
            // CMES should use string format, warn if purely numeric
            if Double(coord) != nil {
                return ValidationResult.valid.addingWarning("CMES coordinate '\(coord)' should use STATIONATION format (e.g., 'STA 1.2')")
            }
        }

        return .valid
    }

    /// Validate location against aircraft zone configuration
    /// - Parameters:
    ///   - location: The location string to validate
    ///   - zones: Available aircraft zones
    /// - Returns: ValidationResult with location validation
    static func validateLocation(_ location: String, againstZones zones: [String]) -> ValidationResult {
        guard !location.isEmpty else { return .valid }

        if !zones.contains(location) {
            return ValidationResult.invalid(.invalidZoneLocation(location))
        }

        return .valid
    }

    /// Validate template field name
    /// - Parameter fieldName: The field name to validate
    /// - Returns: ValidationResult with field name validation
    static func validateFieldName(_ fieldName: String) -> ValidationResult {
        if fieldName.isEmpty {
            return ValidationResult.invalid(.invalidTemplateConfiguration("Field name cannot be empty"))
        }

        let validFieldNames = ["itemDescription", "irm", "partNumber", "issue", "shouldBe", "location", "xCoordinate", "yCoordinate", "zCoordinate", "date", "sessionId"]

        if !validFieldNames.contains(fieldName) {
            return ValidationResult.invalid(.invalidTemplateConfiguration("Unknown field name: \(fieldName)"))
        }

        return .valid
    }
}

// MARK: - Extensions

/// String extension for nil/empty validation
extension String? {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
