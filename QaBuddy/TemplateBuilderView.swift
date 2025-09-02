//
//  TemplateBuilderView.swift
//  QA Buddy PU/NC Template System - Template Builder Interface
//  Phase 3.2 - Subtask 1.3: Complete Implementation with Drag-to-Reorder

import SwiftUI
import CoreData

struct TemplateBuilderView: View {
    let template: InspectionTemplate?

    @StateObject private var templateManager = TemplateManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var templateName = ""
    @State private var templateType = "PU"
    @State private var fieldConfigurations: [EditableFieldConfiguration] = []
    @State private var showingAddField = false
    @State private var isEditMode = false
    @State private var hasUnsavedChanges = false

    init(template: InspectionTemplate? = nil, templateType: String? = nil) {
        self.template = template
        _templateName = State(initialValue: template?.name ?? "")
        _templateType = State(initialValue: template?.templateType ?? templateType ?? "PU")
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    // Template Information Section
                    Section(header: HStack {
                        Text("Template Information")
                        Spacer()
                        if templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Template Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("e.g., 'Daily Inspection', 'FOD Checklist'", text: $templateName)
                                .onChange(of: templateName) {
                                    hasUnsavedChanges = true
                                    updateUnsavedChanges()
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Template Type")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            // Button-based template type selection with explicit state management
                            HStack(spacing: 16) {
                                Button(action: {
                                    // Update state
                                    templateType = "PU"
                                    hasUnsavedChanges = true
                                }) {
                                    VStack(alignment: .center, spacing: 4) {
                                        Image(systemName: templateType == "PU" ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(.blue)
                                        Text("PU")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text("(Pickup)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(templateType == "PU" ? Color.blue.opacity(0.1) : Color.clear)
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity)
                                }

                                Button(action: {
                                    // Update state
                                    templateType = "NC"
                                    hasUnsavedChanges = true
                                }) {
                                    VStack(alignment: .center, spacing: 4) {
                                        Image(systemName: templateType == "NC" ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(.red)
                                        Text("NC")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text("(Non-Conformance)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(templateType == "NC" ? Color.red.opacity(0.1) : Color.clear)
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, 8)
                            .onChange(of: templateType) { _, newValue in
                                // Ensure changes are properly registered
                                hasUnsavedChanges = true
                                updateUnsavedChanges()
                            }

                            // Template type description
                            Text(templateTypeDescription(for: templateType))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                        }

                        if let template = template {
                            HStack {
                                Text(template.isBuiltIn ? "Based on: Built-in Template" : "Editing: Custom Template")
                                Spacer()
                                if template.isBuiltIn {
                                    Text("✅ Built-in")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                } else {
                                    Text("✅ Custom")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }

                    // Field Configuration Section
                    Section(header: HStack {
                        HStack(spacing: 8) {
                            Text("Field Configuration (")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text("\(fieldConfigurations.count)")
                                .font(.headline)
                                .foregroundColor(.blue)

                            Text(fieldConfigurations.count == 1 ? "field)" : "fields)")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        Spacer()
                    }) {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading) {
                                Text("Add and configure fields for your inspection template")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            HStack(spacing: 12) {
                                Button(action: {
                                    withAnimation {
                                        isEditMode.toggle()
                                    }
                                }) {
                                    VStack(spacing: 2) {
                                        Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                                            .font(.title3)
                                        Text(isEditMode ? "Done" : "Edit")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.accentColor)
                                }

                                Button(action: { showingAddField = true }) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                        Text("Add")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.green)
                                }
                            }
                        }

                        if fieldConfigurations.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "text.append")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)

                                Text("No fields configured")
                                    .font(.headline)
                                    .foregroundColor(.secondary)

                                Text("Tap the + button to add your first field")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)

                                Button("Add Sample Fields") {
                                    addSampleFields()
                                    hasUnsavedChanges = true
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            // Drag-to-reorder ForEach using onMove modifier
                            ForEach(fieldConfigurations.indices, id: \.self) { index in
                                EditableFieldConfigurationRow(
                                    config: $fieldConfigurations[index],
                                    isEditMode: isEditMode,
                                    onDelete: {
                                        deleteField(fieldConfigurations[index])
                                    }
                                )
                            }
                            .onMove(perform: moveFields)
                            .moveDisabled(!isEditMode)
                            .animation(.default, value: fieldConfigurations)
                        }
                    }

                    // Template Statistics Section
                    if !fieldConfigurations.isEmpty {
                        Section(header: Text("Template Statistics")) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Fields: \(fieldConfigurations.count)")

                                    let requiredCount = fieldConfigurations.filter { $0.visibility == .required }.count
                                    let visibleCount = fieldConfigurations.filter { $0.visibility == .visible }.count
                                    let hiddenCount = fieldConfigurations.filter { $0.visibility == .hidden }.count

                                    Text("Required: \(requiredCount) | Visible: \(visibleCount) | Hidden: \(hiddenCount)")

                                    if fieldConfigurations.first(where: { !$0.validation.isEmpty }) != nil {
                                        Text("✅ Validation Rules Configured")
                                            .foregroundColor(.green)
                                    }

                                    if fieldConfigurations.first(where: { !$0.prefix.isEmpty || !$0.suffix.isEmpty }) != nil {
                                        Text("✅ Prefix/Suffix Formatters")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }

                    // Validation Summary
                    if let errors = validationErrors, !errors.isEmpty {
                        Section(header: Text("Validation Issues")) {
                            ForEach(errors, id: \.self) { error in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)

                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Button("Dismiss Issues") {
                                // Issues remain visible until fixed
                            }
                            .foregroundColor(.orange)
                        }
                    }
                } // end Form

                // Bottom toolbar for additional actions (kept inside VStack)
                if hasUnsavedChanges {
                    HStack {
                        Button("Reset") {
                            resetTemplate()
                            hasUnsavedChanges = false
                        }
                        .foregroundColor(.red)

                        Spacer()

                        Button("Save Draft") {
                            saveTemplate(draft: true)
                        }
                        .foregroundColor(.orange)

                        Button("Save & Close") {
                            saveTemplate(draft: false)
                        }
                        .foregroundColor(.green)
                        .disabled(!isTemplateValid)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .shadow(radius: 2)
                }
            } // end VStack
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismissWithConfirmation()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    // Navigation menu for additional actions
                    Menu {
                        if template != nil {
                            Button(action: duplicateTemplate) {
                                Label("Duplicate Template", systemImage: "doc.on.doc")
                            }
                        }

                        Button(action: { showingAddField = true }) {
                            Label("Add Field", systemImage: "plus.circle")
                        }

                        if !fieldConfigurations.isEmpty {
                            Button(role: .destructive, action: clearAllFields) {
                                Label("Clear All Fields", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
            .sheet(isPresented: $showingAddField) {
                AddFieldSheet(onAdd: addNewField)
            }
            .onAppear {
                initializeFieldsFromTemplate()
                updateUnsavedChanges()
            }
            .onDisappear {
                if hasUnsavedChanges && isTemplateValid {
                    autoSaveDraft()
                }
            }
        } // end NavigationView
    }

    // MARK: - Validation

    private var isTemplateValid: Bool {
        return !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !fieldConfigurations.isEmpty &&
               validationErrors == nil
    }

    private var validationErrors: [String]? {
        var errors: [String] = []

        if templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Template name is required")
        }

        if fieldConfigurations.isEmpty {
            errors.append("At least one field must be configured")
        }

        let requiredCount = fieldConfigurations.filter { $0.visibility == .required }.count
        if requiredCount == 0 {
            errors.append("At least one field must be marked as required")
        }

        // Check for duplicate field names
        let fieldNames = fieldConfigurations.map { $0.fieldName.lowercased() }
        if fieldNames.count != Set(fieldNames).count {
            errors.append("Field names must be unique")
        }

        return errors.isEmpty ? nil : errors
    }

    // MARK: - Actions

    private func initializeFieldsFromTemplate() {
        if let template = template {
            // Convert existing template fields to editable format
            fieldConfigurations = template.decodedFieldConfigurations.map {
                EditableFieldConfiguration(
                    fieldName: $0.fieldName,
                    visibility: $0.visibility,
                    defaultValue: $0.defaultValue,
                    prefix: $0.prefix ?? "",
                    suffix: $0.suffix ?? "",
                    validation: $0.validation ?? ""
                )
            }
        } else {
            // Start with no fields for new templates
            fieldConfigurations = []
        }
    }

    private func addSampleFields() {
        fieldConfigurations = [
            EditableFieldConfiguration(fieldName: "itemDescription", visibility: .required, defaultValue: nil),
            EditableFieldConfiguration(fieldName: "irm", visibility: .required, defaultValue: nil),
            EditableFieldConfiguration(fieldName: "partNumber", visibility: .visible, defaultValue: nil),
            EditableFieldConfiguration(fieldName: "issue", visibility: .required, defaultValue: nil),
            EditableFieldConfiguration(fieldName: "shouldBe", visibility: .visible, defaultValue: nil),
            EditableFieldConfiguration(fieldName: "location", visibility: .required, defaultValue: nil),
            EditableFieldConfiguration(fieldName: "xCoordinate", visibility: .visible, defaultValue: nil),
            EditableFieldConfiguration(fieldName: "yCoordinate", visibility: .visible, defaultValue: nil),
            EditableFieldConfiguration(fieldName: "zCoordinate", visibility: .visible, defaultValue: nil)
        ]
        hasUnsavedChanges = true
    }

    private func addNewField(_ config: EditableFieldConfiguration) {
        fieldConfigurations.append(config)
        hasUnsavedChanges = true
    }

    private func deleteField(_ config: EditableFieldConfiguration) {
        if let index = fieldConfigurations.firstIndex(where: { $0.id == config.id }) {
            fieldConfigurations.remove(at: index)
            hasUnsavedChanges = true
        }
    }

    private func moveFields(from source: IndexSet, to destination: Int) {
        fieldConfigurations.move(fromOffsets: source, toOffset: destination)
        hasUnsavedChanges = true
    }

    private func clearAllFields() {
        fieldConfigurations.removeAll()
        hasUnsavedChanges = true
    }

    private func duplicateTemplate() {
        // TODO: Implement template duplication
    }

    private func saveTemplate(draft: Bool) {
        Task {
            await saveTemplateAsync(draft: draft)
        }
    }

    @MainActor
    private func saveTemplateAsync(draft: Bool) async {
        guard isTemplateValid || draft else { return }

        // Convert editable configs to template field configurations
        let templateFields = fieldConfigurations.map { config in
            TemplateFieldConfiguration(
                fieldName: config.fieldName,
                visibility: config.visibility,
                defaultValue: config.defaultValue,
                prefix: config.prefix,
                suffix: config.suffix,
                validation: config.validation
            )
        }

        let templateName = self.templateName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingTemplate = template {
            // Update existing template
            let success = await templateManager.updateTemplate(existingTemplate,
                                                              name: templateName,
                                                              templateType: templateType,
                                                              fieldConfigs: templateFields)
            if success {
                hasUnsavedChanges = false
                if !draft {
                    dismiss()
                }
            }
        } else {
            // Create new template
            let newTemplate = await templateManager.createCustomTemplate(name: templateName,
                                                                        fieldConfigs: templateFields)
            if newTemplate != nil {
                hasUnsavedChanges = false
                if !draft {
                    dismiss()
                }
            }
        }
    }

    private func autoSaveDraft() {
        Task {
            await saveTemplateAsync(draft: true)
        }
    }

    private func resetTemplate() {
        if let template = template {
            templateName = template.name ?? ""
            templateType = template.templateType ?? "PU"
        } else {
            templateName = ""
            templateType = "PU"
        }
        initializeFieldsFromTemplate()
    }

    private func dismissWithConfirmation() {
        if hasUnsavedChanges {
            // TODO: Show confirmation dialog
            dismiss()
        } else {
            dismiss()
        }
    }

    private func updateUnsavedChanges() {
        hasUnsavedChanges = true
    }

    // MARK: - Helper Functions

    private func templateTypeDescription(for type: String) -> String {
        switch type {
        case "PU": return "• Routine inspections and maintenance activities"
        case "NC": return "• Findings that require corrective action"
        default: return "• Select template type"
        }
    }
}

// MARK: - Supporting Views

struct EditableFieldConfigurationRow: View {
    @Binding var config: EditableFieldConfiguration
    let isEditMode: Bool
    let onDelete: () -> Void
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main row content
            HStack(spacing: 8) {
                if isEditMode {
                    Image(systemName: "line.horizontal.3")
                        .foregroundColor(.gray)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        if isEditMode {
                            TextField("Field Name", text: $config.fieldName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(minWidth: 120)
                        } else {
                            Text(config.fieldName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Spacer()

                        // Always-visible visibility indicator with color coding
                        visibilityBadge(for: config.visibility)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(visibilityBackgroundColor(for: config.visibility))
                            .cornerRadius(12)

                        // Expand/collapse button for details
                        Button(action: { showDetails.toggle() }) {
                            Image(systemName: showDetails ? "chevron.up.circle" : "chevron.down.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                    }

                    // Quick properties summary (always visible)
                    HStack(spacing: 16) {
                        if let defaultValue = config.defaultValue, !defaultValue.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 10))
                                Text(defaultValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !config.prefix.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 10))
                                Text(config.prefix)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !config.suffix.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 10))
                                Text(config.suffix)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !config.validation.isEmpty {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)

                    // Preview of how field will appear
                    if !config.fieldName.isEmpty {
                        Text("Preview: \(config.prefix)\(config.fieldName.capitalized)\(config.suffix)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }

            // Expandable details section
            if showDetails {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        // Field Name editing (when not in edit mode)
                        if !isEditMode {
                            HStack {
                                Text("Field Name")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .leading)

                                TextField("", text: $config.fieldName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                            }
                        }

                        // Visibility selector (always editable)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Visibility Level")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Visibility", selection: $config.visibility) {
                                HStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.3))
                                        .frame(width: 12, height: 12)
                                    Text("Visible")
                                        .font(.caption)
                                }
                                .tag(FieldVisibility.visible)

                                HStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.3))
                                        .frame(width: 12, height: 12)
                                    Text("Required")
                                        .font(.caption)
                                }
                                .tag(FieldVisibility.required)

                                HStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: 12, height: 12)
                                    Text("Hidden")
                                        .font(.caption)
                                }
                                .tag(FieldVisibility.hidden)
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()

                            Text(visibilityDescription(for: config.visibility))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                        }

                        // Default Value
                        HStack {
                            Text("Default")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)

                            TextField("Optional default value", text: Binding(
                                get: { config.defaultValue ?? "" },
                                set: { config.defaultValue = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        }

                        // Prefix and Suffix
                        HStack(spacing: 8) {
                            VStack(alignment: .leading) {
                                Text("Prefix")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextField("Before field", text: $config.prefix)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                            }

                            VStack(alignment: .leading) {
                                Text("Suffix")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextField("After field", text: $config.suffix)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                            }
                        }

                        // Validation Pattern
                        HStack(alignment: .top) {
                            Text("Validation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)

                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Regex pattern (optional)", text: $config.validation)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)

                                if !config.validation.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                            .font(.system(size: 10))

                                        Text("Validation pattern set")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }

                                    if let commonPattern = commonPattern(for: config.validation) {
                                        Text("Matches: \(commonPattern.description)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Custom validation pattern")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                } else {
                                    Text("No validation - optional field")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.3), value: showDetails)
            }

            // Action buttons for edit mode
            if isEditMode {
                HStack {
                    Spacer()

                    Button(action: onDelete) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.caption)
                            Text("Delete")
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 4)
    }

    private func visibilityBadge(for visibility: FieldVisibility) -> Text {
        switch visibility {
        case .visible:
            return Text("Visible").foregroundColor(.green).font(.caption).fontWeight(.medium)
        case .required:
            return Text("Required").foregroundColor(.orange).font(.caption).fontWeight(.medium)
        case .hidden:
            return Text("Hidden").foregroundColor(.red).font(.caption).fontWeight(.medium)
        }
    }

    private func visibilityBackgroundColor(for visibility: FieldVisibility) -> Color {
        switch visibility {
        case .visible: return Color.green.opacity(0.2)
        case .required: return Color.orange.opacity(0.2)
        case .hidden: return Color.red.opacity(0.2)
        }
    }

    private func visibilityDescription(for visibility: FieldVisibility) -> String {
        switch visibility {
        case .visible: return "• Appears in write-up form - user can modify value"
        case .required: return "• Must be completed - highlighted in write-up form"
        case .hidden: return "• Not shown to user - uses default or calculated value"
        }
    }

    private func commonPattern(for pattern: String) -> (description: String, example: String)? {
        let patterns = [
            "^[A-Z]{3}-[0-9]{4}$": (description: "Aircraft Registration", example: "ABC-1234"),
            "^[0-9]{1,3}(\\.[0-9]{1,2})?$": (description: "Coordinate/Weight", example: "45.67"),
            ".+": (description: "Required Non-Empty", example: "any text"),
            "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z]{2,}$": (description: "Email Address", example: "user@domain.com"),
            "^[0-9]{6,}$": (description: "6+ Digit Numbers", example: "123456"),
            "^[0-9]+$": (description: "Whole Numbers Only", example: "12345"),
        ]

        return patterns[pattern]
    }
}

struct AddFieldSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fieldName = ""
    @State private var visibility: FieldVisibility = .visible
    @State private var defaultValue = ""
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var validation = ""
    @State private var showValidationExamples = false

    let onAdd: (EditableFieldConfiguration) -> Void

    private var previewText: String {
        let preview = (prefix + fieldName.capitalized + suffix)
        return "Preview: " + (preview.isEmpty ? fieldName : preview)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with preview
                    VStack(alignment: .leading, spacing: 8) {
                        if !fieldName.isEmpty {
                            HStack {
                                Text("Field Preview")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                Spacer()

                                visibilityIndicator(for: visibility)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(visibilityColor(for: visibility).opacity(0.2))
                                    .cornerRadius(6)
                            }

                            Text(previewText)
                                .font(.body)
                                .fontWeight(.medium)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)

                    // Basic Information Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Basic Information")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Field Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("Enter field name", text: $fieldName)

                                if fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }

                        Divider()

                        // Field Visibility with button-based selection (fixes the stuck picker)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Field Visibility")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            VStack(spacing: 8) {
                                Button(action: { visibility = .visible }) {
                                    HStack {
                                        Image(systemName: visibility == .visible ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(.green)
                                        Text("Visible")
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(visibility == .visible ? Color.green.opacity(0.1) : Color.clear)
                                    .cornerRadius(8)
                                }

                                Button(action: { visibility = .required }) {
                                    HStack {
                                        Image(systemName: visibility == .required ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(.orange)
                                        Text("Required")
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(visibility == .required ? Color.orange.opacity(0.1) : Color.clear)
                                    .cornerRadius(8)
                                }

                                Button(action: { visibility = .hidden }) {
                                    HStack {
                                        Image(systemName: visibility == .hidden ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(.red)
                                        Text("Hidden")
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(visibility == .hidden ? Color.red.opacity(0.1) : Color.clear)
                                    .cornerRadius(8)
                                }
                            }

                            Text(visibilityDescription(for: visibility))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding()

                    // Default Values Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Default Values")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Default Value (Optional)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("Enter default value", text: $defaultValue)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prefix (Added before field name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("e.g., 'FOD PRESENT. '", text: $prefix)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)

                            Text("Examples: 'IRR #', 'FOD - ', 'DEFECT: '")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suffix (Added after value)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("e.g., ' found', ' detected'", text: $suffix)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)

                            Text("Examples: ' (lbs)', ' required', ' checklist'")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()

                    // Validation Pattern Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Validation Pattern")
                                .font(.headline)
                            Spacer()
                            Button(action: { showValidationExamples.toggle() }) {
                                Image(systemName: showValidationExamples ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Regex Pattern (Optional)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("e.g., ^[A-Z]{3}-[0-9]{4}$", text: $validation)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)

                            if showValidationExamples {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Common Patterns:")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.top, 4)

                                    validationExample("^[A-Z]{3}-[0-9]{4}$", "Aircraft registration (ABC-1234)")
                                    validationExample("^[0-9]{1,3}(\\.[0-9]{1,2})?$", "Coordinates or weights")
                                    validationExample(".+", "Required non-empty field")
                                    validationExample("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z]{2,}$", "Email address")
                                    validationExample("^[0-9]{6,}$", "6+ digit numbers")

                                    Text("✓ Leave empty for no validation")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                        .padding(.top, 4)
                                }
                            } else {
                                Text("Tap help button above for examples")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding()

                    // Action Buttons Section at bottom
                    HStack(spacing: 16) {
                        Button(action: resetForm) {
                            Text("Reset")
                                .foregroundColor(.orange)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }

                        Button(action: addField) {
                            Text("Add Field")
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(isFormValid ? Color.blue : Color.gray)
                                .cornerRadius(8)
                        }
                        .disabled(!isFormValid)
                    }
                    .padding()
                }
                .padding(.bottom, 20) // Extra padding at bottom for comfortable scrolling

            }
            .navigationTitle("Add New Field")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func addField() {
        let config = EditableFieldConfiguration(
            fieldName: fieldName.trimmingCharacters(in: .whitespaces),
            visibility: visibility,
            defaultValue: defaultValue.isEmpty ? nil : defaultValue,
            prefix: prefix,
            suffix: suffix,
            validation: validation
        )
        onAdd(config)
        dismiss()
    }

    private func resetForm() {
        fieldName = ""
        visibility = .visible
        defaultValue = ""
        prefix = ""
        suffix = ""
        validation = ""
        showValidationExamples = false
    }

    private var isFormValid: Bool {
        !fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func validationExample(_ pattern: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func visibilityIndicator(for visibility: FieldVisibility) -> Text {
        switch visibility {
        case .visible: return Text("VISIBLE").foregroundColor(.green)
        case .required: return Text("REQUIRED").foregroundColor(.orange)
        case .hidden: return Text("HIDDEN").foregroundColor(.red)
        }
    }

    private func visibilityColor(for visibility: FieldVisibility) -> Color {
        switch visibility {
        case .visible: return .green
        case .required: return .orange
        case .hidden: return .red
        }
    }

    private func visibilityDescription(for visibility: FieldVisibility) -> String {
        switch visibility {
        case .visible: return "Field is shown in write-up form - user can enter custom value"
        case .required: return "Field must be filled in by user - marked with yellow in form"
        case .hidden: return "Field is not shown to user - uses default or computed value"
        }
    }
}

// MARK: - Editable Field Configuration

struct EditableFieldConfiguration: Identifiable, Equatable {
    var id = UUID()
    var fieldName: String
    var visibility: FieldVisibility
    var defaultValue: String?
    var prefix: String
    var suffix: String
    var validation: String

    init(fieldName: String,
         visibility: FieldVisibility = .visible,
         defaultValue: String? = nil,
         prefix: String = "",
         suffix: String = "",
         validation: String = "") {
        self.id = UUID()
        self.fieldName = fieldName
        self.visibility = visibility
        self.defaultValue = defaultValue
        self.prefix = prefix
        self.suffix = suffix
        self.validation = validation
    }
}

#Preview {
    TemplateBuilderView()
}
