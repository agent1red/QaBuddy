// DefaultTemplates.swift
// Default template implementations for QA Buddy PU/NC Template System
// Phase 3.1 - Subtask 1.1: Design Template Entity Schema

import Foundation

/// Data structure for template definitions (used before Core Data creation)
struct InspectionTemplateData {
    let name: String
    let templateType: String
    let fieldConfigurations: [TemplateFieldConfiguration]
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

/// Built-in template definitions with their field configurations
struct BuiltInTemplates {

    /// FOD Cleanup Template - The primary template for FOD documentation
    static let fodTemplate = InspectionTemplateData(
        name: "FOD Cleanup",
        templateType: "PU",
        fieldConfigurations: [
            TemplateFieldConfiguration(
                fieldName: "itemDescription",
                visibility: .hidden,
                defaultValue: "FOD"
            ),
            TemplateFieldConfiguration(
                fieldName: "irm",
                visibility: .hidden,
                defaultValue: "FOD"
            ),
            TemplateFieldConfiguration(
                fieldName: "partNumber",
                visibility: .hidden,
                defaultValue: "FOD"
            ),
            TemplateFieldConfiguration(
                fieldName: "issue",
                visibility: .required,
                prefix: "FOD PRESENT. "
            ),
            TemplateFieldConfiguration(
                fieldName: "shouldBe",
                visibility: .hidden,
                defaultValue: "THERE SHOULD BE NO FOD PRESENT, AND CLEAN AS YOU GO IAW BPI-6533 AND PRO-1223."
            ),
            TemplateFieldConfiguration(
                fieldName: "location",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "xCoordinate",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "yCoordinate",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "zCoordinate",
                visibility: .required
            )
        ]
    )

    /// Standard QA Write-up Template - General purpose template
    static let qaWriteupTemplate = InspectionTemplateData(
        name: "Standard QA Write-up",
        templateType: "PU",
        fieldConfigurations: [
            TemplateFieldConfiguration(
                fieldName: "itemDescription",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "irm",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "partNumber",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "issue",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "shouldBe",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "location",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "xCoordinate",
                visibility: .visible
            ),
            TemplateFieldConfiguration(
                fieldName: "yCoordinate",
                visibility: .visible
            ),
            TemplateFieldConfiguration(
                fieldName: "zCoordinate",
                visibility: .visible
            )
        ]
    )

    /// Equipment Defect Template
    static let equipmentDefectTemplate = InspectionTemplateData(
        name: "Equipment Defect",
        templateType: "NC",
        fieldConfigurations: [
            TemplateFieldConfiguration(
                fieldName: "itemDescription",
                visibility: .required,
                defaultValue: "EQUIPMENT DEFECT"
            ),
            TemplateFieldConfiguration(
                fieldName: "irm",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "partNumber",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "issue",
                visibility: .required,
                prefix: "EQUIPMENT DEFECT DISCOVERED. "
            ),
            TemplateFieldConfiguration(
                fieldName: "shouldBe",
                visibility: .required,
                defaultValue: "EQUIPMENT SHOULD BE OPERATIONAL WITH NO DEFECTS."
            ),
            TemplateFieldConfiguration(
                fieldName: "location",
                visibility: .required
            ),
            TemplateFieldConfiguration(
                fieldName: "xCoordinate",
                visibility: .visible
            ),
            TemplateFieldConfiguration(
                fieldName: "yCoordinate",
                visibility: .visible
            ),
            TemplateFieldConfiguration(
                fieldName: "zCoordinate",
                visibility: .visible
            )
        ]
    )
}
