// TemplateTypes.swift
// Shared type definitions for QA Buddy template system
// Contains FieldVisibility and TemplateFieldConfiguration types

import Foundation

/// Field visibility configuration
enum FieldVisibility: String, Codable, Sendable {
    case visible
    case hidden
    case required
} 

/// Template field configuration struct
struct TemplateFieldConfiguration: Codable, Sendable {
    public let fieldName: String
    public var visibility: FieldVisibility
    public var defaultValue: String?
    public var prefix: String?
    public var suffix: String?
    public var validation: String? // Regex pattern

    public init(fieldName: String,
                visibility: FieldVisibility = .visible,
                defaultValue: String? = nil,
                prefix: String? = nil,
                suffix: String? = nil,
                validation: String? = nil) {
        self.fieldName = fieldName
        self.visibility = visibility
        self.defaultValue = defaultValue
        self.prefix = prefix
        self.suffix = suffix
        self.validation = validation
    }
}
