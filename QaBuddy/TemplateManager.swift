//  TemplateManager.swift
//  Template Manager for QA Buddy PU/NC Template System
//  Phase 3.1 - Task 6.1: Create Template Manager

import Foundation
import SwiftUI
import CoreData

/// Manager for inspection template configurations
/// Handles loading, saving, and managing inspection templates in Core Data
@MainActor
final class TemplateManager: ObservableObject {
    static let shared = TemplateManager()

    @Published var templates: [InspectionTemplate] = []
    @Published var builtInTemplates: [InspectionTemplate] = []
    @Published var customTemplates: [InspectionTemplate] = []

    private let context: NSManagedObjectContext
    private let userDefaultsKey = "lastTemplateFetch"

    private init() {
        self.context = PersistenceController.shared.container.viewContext
        Task {
            await loadTemplates()
            await ensureBuiltInTemplates()
        }
    }

    /// Load all templates from Core Data
    func loadTemplates() async {
        let fetchRequest = InspectionTemplate.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "isBuiltIn", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        do {
            let allTemplates = try context.fetch(fetchRequest)
            templates = allTemplates

            // Separate built-in and custom templates
            builtInTemplates = allTemplates.filter { $0.isBuiltIn }
            customTemplates = allTemplates.filter { !$0.isBuiltIn }

            print("TemplateManager: Loaded \(templates.count) templates (\(builtInTemplates.count) built-in, \(customTemplates.count) custom)")
        } catch {
            print("TemplateManager: Failed to load templates: \(error)")
            // Clear arrays on failure
            templates = []
            builtInTemplates = []
            customTemplates = []
        }
    }

    /// Ensure built-in templates exist in Core Data
    private func ensureBuiltInTemplates() async {
        var hasChanges = false

        // Check for FOD Template
        if !builtInTemplates.contains(where: { $0.name == "FOD Cleanup" }) {
            if await createBuiltInTemplate(name: "FOD Cleanup",
                                         templateType: "PU",
                                         fieldConfigs: [
                TemplateFieldConfiguration(fieldName: "itemDescription",
                                         visibility: .hidden,
                                         defaultValue: "FOD"),
                TemplateFieldConfiguration(fieldName: "irm",
                                         visibility: .hidden,
                                         defaultValue: "FOD"),
                TemplateFieldConfiguration(fieldName: "partNumber",
                                         visibility: .hidden,
                                         defaultValue: "FOD"),
                TemplateFieldConfiguration(fieldName: "issue",
                                         visibility: .required,
                                         prefix: "FOD PRESENT. "),
                TemplateFieldConfiguration(fieldName: "shouldBe",
                                         visibility: .hidden,
                                         defaultValue: "THERE SHOULD BE NO FOD PRESENT, AND CLEAN AS YOU GO IAW BPI-6533 AND PRO-1223."),
                TemplateFieldConfiguration(fieldName: "location",
                                         visibility: .required),
                TemplateFieldConfiguration(fieldName: "xCoordinate",
                                         visibility: .required),
                TemplateFieldConfiguration(fieldName: "yCoordinate",
                                         visibility: .required),
                TemplateFieldConfiguration(fieldName: "zCoordinate",
                                         visibility: .required)
            ]) {
                print("TemplateManager: Created built-in FOD template")
                hasChanges = true
            }
        }

        // Check for Standard QA Write-up Template
        if !builtInTemplates.contains(where: { $0.name == "Standard QA Write-up" }) {
            if await createBuiltInTemplate(name: "Standard QA Write-up",
                                         templateType: "PU",
                                         fieldConfigs: [
                TemplateFieldConfiguration(fieldName: "itemDescription", visibility: .required),
                TemplateFieldConfiguration(fieldName: "irm", visibility: .required),
                TemplateFieldConfiguration(fieldName: "partNumber", visibility: .required),
                TemplateFieldConfiguration(fieldName: "issue", visibility: .required),
                TemplateFieldConfiguration(fieldName: "shouldBe", visibility: .required),
                TemplateFieldConfiguration(fieldName: "location", visibility: .required),
                TemplateFieldConfiguration(fieldName: "xCoordinate", visibility: .visible),
                TemplateFieldConfiguration(fieldName: "yCoordinate", visibility: .visible),
                TemplateFieldConfiguration(fieldName: "zCoordinate", visibility: .visible)
            ]) {
                print("TemplateManager: Created built-in QA Write-up template")
                hasChanges = true
            }
        }

        // Check for Equipment Defect Template
        if !builtInTemplates.contains(where: { $0.name == "Equipment Defect" }) {
            if await createBuiltInTemplate(name: "Equipment Defect",
                                         templateType: "NC",
                                         fieldConfigs: [
                TemplateFieldConfiguration(fieldName: "itemDescription",
                                         visibility: .required,
                                         defaultValue: "EQUIPMENT DEFECT"),
                TemplateFieldConfiguration(fieldName: "irm", visibility: .required),
                TemplateFieldConfiguration(fieldName: "partNumber", visibility: .required),
                TemplateFieldConfiguration(fieldName: "issue",
                                         visibility: .required,
                                         prefix: "EQUIPMENT DEFECT DISCOVERED. "),
                TemplateFieldConfiguration(fieldName: "shouldBe",
                                         visibility: .required,
                                         defaultValue: "EQUIPMENT SHOULD BE OPERATIONAL WITH NO DEFECTS."),
                TemplateFieldConfiguration(fieldName: "location", visibility: .required),
                TemplateFieldConfiguration(fieldName: "xCoordinate", visibility: .visible),
                TemplateFieldConfiguration(fieldName: "yCoordinate", visibility: .visible),
                TemplateFieldConfiguration(fieldName: "zCoordinate", visibility: .visible)
            ]) {
                print("TemplateManager: Created built-in Equipment Defect template")
                hasChanges = true
            }
        }

        if hasChanges {
            await loadTemplates() // Refresh lists
        }
    }

    /// Create a built-in template with field configurations
    private func createBuiltInTemplate(name: String, templateType: String, fieldConfigs: [TemplateFieldConfiguration]) async -> Bool {
        let newTemplate = InspectionTemplate(context: context)
        newTemplate.id = UUID()
        newTemplate.name = name
        newTemplate.templateType = templateType
        newTemplate.isBuiltIn = true
        newTemplate.createdDate = Date()
        newTemplate.lastModified = Date()

        // Create TemplateField entities for each field configuration
        for fieldConfig in fieldConfigs {
            let templateField = TemplateField(context: context)
            templateField.id = UUID()
            templateField.fieldName = fieldConfig.fieldName
            templateField.visibility = fieldConfig.visibility.rawValue
            templateField.defaultValue = fieldConfig.defaultValue
            templateField.prefix = fieldConfig.prefix
            templateField.suffix = fieldConfig.suffix
            templateField.validationPattern = fieldConfig.validation

            newTemplate.addToFields(templateField)
        }

        do {
            try context.save()
            return true
        } catch {
            print("TemplateManager: Failed to create built-in template \(name): \(error)")
            context.rollback()
            return false
        }
    }

    /// Create a custom template
    func createCustomTemplate(name: String,
                            basedOn: InspectionTemplate? = nil,
                            fieldConfigs: [TemplateFieldConfiguration]? = nil) async -> InspectionTemplate? {

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !templates.contains(where: { $0.name == trimmedName }),
              trimmedName.count <= 100 else {
            print("TemplateManager: Invalid template name or name already exists: \(name)")
            return nil
        }

        let newTemplate = InspectionTemplate(context: context)
        newTemplate.id = UUID()
        newTemplate.name = trimmedName
        newTemplate.templateType = basedOn?.templateType ?? "PU"
        newTemplate.isBuiltIn = false
        newTemplate.createdDate = Date()
        newTemplate.lastModified = Date()

        // Use provided field configs, or copy from base template
        let configsToUse: [TemplateFieldConfiguration]
        if let providedConfigs = fieldConfigs {
            configsToUse = providedConfigs
        } else if let baseTemplate = basedOn {
            // Copy existing fields from base template
            configsToUse = getFieldConfigurations(for: baseTemplate)
        } else {
            // Create minimal default configuration
            configsToUse = [
                TemplateFieldConfiguration(fieldName: "itemDescription", visibility: .required),
                TemplateFieldConfiguration(fieldName: "irm", visibility: .required),
                TemplateFieldConfiguration(fieldName: "partNumber", visibility: .required),
                TemplateFieldConfiguration(fieldName: "issue", visibility: .required),
                TemplateFieldConfiguration(fieldName: "shouldBe", visibility: .required),
                TemplateFieldConfiguration(fieldName: "location", visibility: .required),
                TemplateFieldConfiguration(fieldName: "xCoordinate", visibility: .visible),
                TemplateFieldConfiguration(fieldName: "yCoordinate", visibility: .visible),
                TemplateFieldConfiguration(fieldName: "zCoordinate", visibility: .visible)
            ]
        }

        // Create TemplateField entities for each field configuration
        for fieldConfig in configsToUse {
            let templateField = TemplateField(context: context)
            templateField.id = UUID()
            templateField.fieldName = fieldConfig.fieldName
            templateField.visibility = fieldConfig.visibility.rawValue
            templateField.defaultValue = fieldConfig.defaultValue
            templateField.prefix = fieldConfig.prefix
            templateField.suffix = fieldConfig.suffix
            templateField.validationPattern = fieldConfig.validation

            newTemplate.addToFields(templateField)
        }

        do {
            try context.save()
            await loadTemplates() // Refresh lists
            print("TemplateManager: Created custom template: \(name)")
            return newTemplate
        } catch {
            print("TemplateManager: Failed to create custom template \(name): \(error)")
            context.rollback()
            return nil
        }
    }

    /// Duplicate an existing template
    func duplicateTemplate(_ template: InspectionTemplate) async -> InspectionTemplate? {
        let newName = "\(template.name ?? "Template") (Copy)"
        return await createCustomTemplate(name: newName,
                                        basedOn: template,
                                        fieldConfigs: nil)
    }

    /// Update an existing template
    func updateTemplate(_ template: InspectionTemplate,
                       name: String? = nil,
                       templateType: String? = nil,
                       fieldConfigs: [TemplateFieldConfiguration]? = nil) async -> Bool {

        var hasChanges = false

        // Update name if provided
        if let newName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !newName.isEmpty,
           newName != template.name,
           !templates.contains(where: { $0.name == newName && $0.id != template.id }) {

            template.name = newName
            hasChanges = true
        }

        // Update template type if provided and different
        if let newType = templateType,
           newType != template.templateType {

            template.templateType = newType
            hasChanges = true
        }

        // Update field configurations if provided
        if let newConfigs = fieldConfigs {
            // Remove existing fields properly
            if let existingFields = template.fields as? Set<TemplateField> {
                for field in existingFields {
                    // Remove relationship manually since generated methods may not be available
                    template.mutableSetValue(forKey: "fields").remove(field)
                    context.delete(field)
                }
            }

            // Add new fields
            for fieldConfig in newConfigs {
                let templateField = TemplateField(context: context)
                templateField.id = UUID()
                templateField.fieldName = fieldConfig.fieldName
                templateField.visibility = fieldConfig.visibility.rawValue
                templateField.defaultValue = fieldConfig.defaultValue
                templateField.prefix = fieldConfig.prefix
                templateField.suffix = fieldConfig.suffix
                templateField.validationPattern = fieldConfig.validation

                // Add to template's fields relationship
                template.mutableSetValue(forKey: "fields").add(templateField)
            }
            hasChanges = true
        }

        if hasChanges {
            template.lastModified = Date()
        }

        do {
            try context.save()
            await loadTemplates() // Refresh lists
            print("TemplateManager: Updated template: \(template.name ?? "Unknown")")
            return true
        } catch {
            print("TemplateManager: Failed to update template: \(error)")
            context.rollback()
            return false
        }
    }

    /// Delete a custom template
    func deleteTemplate(_ template: InspectionTemplate) async -> Bool {
        guard !template.isBuiltIn else {
            print("TemplateManager: Cannot delete built-in template: \(template.name ?? "Unknown")")
            return false
        }

        context.delete(template)

        do {
            try context.save()
            await loadTemplates() // Refresh lists
            print("TemplateManager: Deleted template: \(template.name ?? "Unknown")")
            return true
        } catch {
            print("TemplateManager: Failed to delete template: \(error)")
            context.rollback()
            return false
        }
    }

    /// Get field configurations for a template
    func getFieldConfigurations(for template: InspectionTemplate) -> [TemplateFieldConfiguration] {
        guard let templateFields = template.fields as? Set<TemplateField> else { return [] }

        return templateFields.map { getFieldConfiguration(from: $0) }
    }

    /// Validate template field configuration
    func validateTemplateConfiguration(_ template: InspectionTemplate) -> Bool {
        let configs = getFieldConfigurations(for: template)

        // Must have at least one field configuration
        guard !configs.isEmpty else { return false }

        // Must have required fields for basic inspection
        let requiredFields = ["issue", "location"]
        for requiredField in requiredFields {
            guard configs.contains(where: { $0.fieldName == requiredField && $0.visibility == .required }) else {
                return false
            }
        }

        return true
    }

    /// Helper method to convert TemplateField to TemplateFieldConfiguration
    private func getFieldConfiguration(from templateField: TemplateField) -> TemplateFieldConfiguration {
        return TemplateFieldConfiguration(
            fieldName: templateField.fieldName ?? "",
            visibility: FieldVisibility(rawValue: templateField.visibility ?? "visible") ?? .visible,
            defaultValue: templateField.defaultValue,
            prefix: templateField.prefix,
            suffix: templateField.suffix,
            validation: templateField.validationPattern
        )
    }

    // MARK: - Computed Properties

    /// Check if any custom templates exist
    var hasCustomTemplates: Bool {
        !customTemplates.isEmpty
    }

    /// Get template count by type
    var templateCountByType: [String: Int] {
        Dictionary(grouping: templates) {
            ($0.templateType ?? "Unknown")
        }.mapValues { $0.count }
    }

    /// Get total template count
    var totalTemplateCount: Int {
        templates.count
    }

    /// Get built-in template count
    var builtInTemplateCount: Int {
        builtInTemplates.count
    }

    /// Get custom template count
    var customTemplateCount: Int {
        customTemplates.count
    }
}

@MainActor
extension InspectionTemplate {
    /// Computed property to get decoded field configurations
    var decodedFieldConfigurations: [TemplateFieldConfiguration] {
        guard let templateFields = self.fields as? Set<TemplateField> else { return [] }

        return templateFields.map { field in
            TemplateFieldConfiguration(
                fieldName: field.fieldName ?? "",
                visibility: FieldVisibility(rawValue: field.visibility ?? "visible") ?? .visible,
                defaultValue: field.defaultValue,
                prefix: field.prefix,
                suffix: field.suffix,
                validation: field.validationPattern
            )
        }
    }

    /// Computed property to get template type display string
    var templateTypeDisplay: String {
        switch templateType {
        case "PU": return "Positive Report"
        case "NC": return "Non-Conformance"
        default: return templateType ?? "Unknown"
        }
    }

    /// Check if template has valid field configurations
    var isValid: Bool {
        TemplateManager.shared.validateTemplateConfiguration(self)
    }
}
