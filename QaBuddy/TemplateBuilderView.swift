//
//  TemplateBuilderView.swift
//  QA Buddy PU/NC Template System - Template Builder Interface
//  Phase 3.2 - Subtask 1.3: Complete Implementation with Drag-to-Reorder

import SwiftUI
import CoreData

struct TemplateBuilderView: View {
    let template: InspectionTemplate?

    @State private var templateManager = TemplateManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var templateName = ""
    @State private var templateType = "PU"
    @State private var fieldConfigurations: [EditableFieldConfiguration] = []
    @State private var showingAddField = false
    @State private var isEditMode = false
    @State private var hasUnsavedChanges = false

    init(template: InspectionTemplate? = nil) {
        self.template = template
        _templateName = State(initialValue: template?.name ?? "")
        _templateType = State(initialValue: template?.templateType ?? "PU")
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    Form {
                        // Template Information Section
                        Section(header: Text("Template Information")) {
                            TextField("Template Name", text: $templateName)
                                .onChange(of: templateName) { _ in
                                    hasUnsavedChanges = true
                                    updateUnsavedChanges()
                                }

                            Picker("Template Type", selection: $templateType) {
                                Text("Pickup (PU)").tag("PU")
                                Text("Non-Conformance (NC)").tag("NC")
                            }



                            if let template = template {
                                HStack {
                                    Text("Built-in Template:")
                                    Spacer()
                                    if template.isBuiltIn {
                                        Text("Yes - Creating Custom Copy")
                                            .foregroundColor(.blue)
                                            .fontWeight(.medium)
                                    } else {
                                        Text("Custom Template")
                                            .foregroundColor(.green)
                                            .fontWeight(.medium)
                                    }
                                }
                            }
                        }

                        // Field Configuration Section
                        Section {
                            HStack {
                                Text("Field Configuration")
                                    .font(.headline)

                                Spacer()

                                Button(action: {
                                    withAnimation {
                                        isEditMode.toggle()
                                    }
                                }) {
                                    Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                                        .foregroundColor(.accentColor)
                                        .font(.title3)
                                }

                                Button(action: { showingAddField = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title3)
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

                                        if let hasValidation = fieldConfigurations.first(where: { !$0.validation.isEmpty }) {
                                            Text("✅ Validation Rules Configured")
                                                .foregroundColor(.green)
                                        }

                                        if let hasPrefixSuffix = fieldConfigurations.first(where: { !$0.prefix.isEmpty || !$0.suffix.isEmpty }) {
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
                    }
                }

                // Bottom toolbar for additional actions
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
            }
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
        }
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
}

// MARK: - Supporting Views

struct EditableFieldConfigurationRow: View {
    @Binding var config: EditableFieldConfiguration
    let isEditMode: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isEditMode {
                    Image(systemName: "line.horizontal.3")
                        .foregroundColor(.gray)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Field Name", text: $config.fieldName)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Picker("", selection: $config.visibility) {
                            Text("▶️").tag(FieldVisibility.visible)
                            Text("🟡").tag(FieldVisibility.required)
                            Text("⚫").tag(FieldVisibility.hidden)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        .disabled(isEditMode)
                    }

                    HStack(spacing: 12) {
                        TextField("Default Value (Optional)", text: Binding(
                            get: { config.defaultValue ?? "" },
                            set: { config.defaultValue = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("Prefix", text: $config.prefix)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)

                        TextField("Suffix", text: $config.suffix)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    .font(.caption)

                    if !config.validation.isEmpty {
                        Text("Validation: \(config.validation)")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }

            if isEditMode {
                HStack {
                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                    }
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
        .padding(.vertical, 8)
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

    let onAdd: (EditableFieldConfiguration) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Field Definition")) {
                    TextField("Field Name", text: $fieldName)

                    Picker("Visibility", selection: $visibility) {
                        Text("Visible").tag(FieldVisibility.visible)
                        Text("Required").tag(FieldVisibility.required)
                        Text("Hidden").tag(FieldVisibility.hidden)
                    }
                }

                Section(header: Text("Default Configuration")) {
                    TextField("Default Value (Optional)", text: Binding(
                        get: { defaultValue },
                        set: { defaultValue = $0 }
                    ))
                    TextField("Prefix", text: $prefix)
                    TextField("Suffix", text: $suffix)
                }

                Section(header: Text("Validation")) {
                    TextField("Regex Pattern (Optional)", text: $validation)
                    Text("Common examples: email, required, [0-9]+")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button("Add Field") {
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
                    .disabled(fieldName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Add Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
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
