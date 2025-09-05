//
//  TemplateDetailView.swift
//  QA Buddy PU/NC Template System - Template Detail View
//  Phase 3.2 - Subtask 1.2: Build Template Detail View

import SwiftUI
import CoreData

// Import statements for missing types
// (Add once we know the correct import paths)

struct TemplateDetailView: View {
    @ObservedObject var template: InspectionTemplate
    @StateObject private var templateManager = TemplateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    // Single sheet driver to serialize presentations
    private enum ActiveSheet: Identifiable, Equatable {
        case edit(InspectionTemplate)
        case duplicate
        case writeup

        var id: String {
            switch self {
            case .edit(let t): return "edit_\(t.objectID.uriRepresentation().absoluteString)"
            case .duplicate: return "duplicate"
            case .writeup: return "writeup"
            }
        }
    }
    @State private var activeSheet: ActiveSheet? = nil
    // Delete confirmation separate to avoid conflicts
    @State private var showingDeleteConfirmation = false
    @State private var duplicateName = ""
    @State private var stableFieldConfigurations: [TemplateFieldConfiguration] = []
    @State private var sessionTitle: String = ""
    // write-up now driven via activeSheet
    @State private var selectedTab: Int? = nil // For navigation callback
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Template Information Section
                Section(header: Text("Template Information")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(template.name ?? "Untitled Template")
                                    .font(.headline)

                                if template.isBuiltIn {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                } else {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                            }

                            HStack {
                                Text(templateTypeBadge)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(templateTypeColor.opacity(0.2))
                                    )
                                    .foregroundColor(templateTypeColor)

                                Spacer()

                                if let fieldCount = fieldCountText {
                                    Text(fieldCount)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let lastModified = template.lastModified {
                                Text("Modified \(lastModified.formatted(.relative(presentation: .named)))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if let createdDate = template.createdDate {
                                Text("Created \(createdDate.formatted(.dateTime.month().day().year()))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

            // Field Configuration Section
            Section(header: Text("Field Configuration")) {
                if !stableFieldConfigurations.isEmpty {
                    ForEach(Array(stableFieldConfigurations.enumerated()), id: \.element.fieldName) { (index, config) in
                        FieldConfigurationRow(
                            config: config,
                            index: index + 1
                        )
                    }
                    .animation(.none, value: stableFieldConfigurations) // Prevents rapid field movement animations
                } else {
                    Text("No field configurations found")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            // Session Integration Section
            if sessionManager.hasActiveSession {
                Section(header: Text("Session Integration")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Session: \(sessionTitle)")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if sessionManager.isZoneBasedSession {
                                Text("Zone-based inspection detected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Activity-based inspection")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }

            // Action Buttons Section
            Section(header: Text("Actions")) {
                // Use Template Button (always available)
                Button(action: useTemplate) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Use Template")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sessionManager.hasActiveSession)

                if !sessionManager.hasActiveSession {
                    Text("Start a session to use this template")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Custom Template Actions
                if !template.isBuiltIn {
                    // Horizontal action bar at bottom: Edit | Duplicate | Delete
                    HStack(spacing: 12) {
                        Button(action: { presentEdit() }) {
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                Text("Edit Template")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.blue)

                        Button(action: { presentDuplicate() }) {
                            HStack {
                                Image(systemName: "doc.on.doc.fill")
                                Text("Duplicate Template")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.green)

                        Button(action: { presentDeleteConfirmation() }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Delete Template")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.red)
                    }
                } else {
                    // Built-in template notice
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This is a built-in template")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text("Built-in templates cannot be modified or deleted. You can duplicate this template to create a custom version.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)

                    // Quick duplicate option for built-in templates
                    Button(action: presentDuplicate) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Create Custom Copy")
                        }
                    }
                    .foregroundColor(.accentColor)
                }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .navigationTitle("Template Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !template.isBuiltIn {
                    Menu {
                        Button(action: presentDuplicate) {
                            Label("Duplicate Template", systemImage: "doc.on.doc")
                        }

                        Button(role: .destructive, action: {
                            presentDeleteConfirmation()
                        }) {
                            Label("Delete Template", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        // Single sheet for edit, duplicate, and write-up
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit(let editTarget):
                TemplateBuilderView(template: editTarget)
            case .duplicate:
                NavigationView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Enter a name for the duplicated template")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Template Name", text: $duplicateName)
                            .textFieldStyle(.roundedBorder)

                        Spacer()

                        HStack {
                            Button("Cancel") { activeSheet = nil }
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Duplicate") { Task { await duplicateTemplate() } }
                                .foregroundColor(.accentColor)
                                .disabled(duplicateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding()
                    .navigationTitle("Duplicate Template")
                    .navigationBarTitleDisplayMode(.inline)
                }
            case .writeup:
                WriteupFormView(template: template, selectedTab: $selectedTab)
            }
        }
        // Delete confirmation using confirmationDialog to avoid alert conflicts
        .confirmationDialog("Delete Template", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteTemplate() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete '\(template.name ?? "this template")'? This action cannot be undone.")
        }
        .onAppear {
            // Capture stable field configurations on view appear to prevent rapid recalculation
            // This fixes the rapid animation issue researched from SwiftUI/Core Data ForEach problems
            stableFieldConfigurations = template.decodedFieldConfigurations

            // Refresh session info for accurate real-time data
            Task {
                await refreshSessionTitle()
            }
        }
    }

    // MARK: - Computed Properties

    private var fieldConfigurations: [TemplateFieldConfiguration]? {
        template.decodedFieldConfigurations
    }

    private var templateTypeColor: Color {
        switch template.templateType {
        case "PU": return .green
        case "NC": return .blue
        default: return .primary
        }
    }

    private var templateTypeBadge: String {
        template.templateTypeDisplay
    }

    private var fieldCountText: String? {
        guard !stableFieldConfigurations.isEmpty else { return nil }

        let required = stableFieldConfigurations.filter { $0.visibility == .required }.count
        let visible = stableFieldConfigurations.filter { $0.visibility == .visible }.count
        let hidden = stableFieldConfigurations.filter { $0.visibility == .hidden }.count

        var components: [String] = []
        if required > 0 { components.append("\(required) required") }
        if visible > 0 { components.append("\(visible) visible") }
        if hidden > 0 { components.append("\(hidden) hidden") }

        return components.joined(separator: ", ") + " fields"
    }

    // MARK: - Actions

    private func useTemplate() {
        activeSheet = .writeup
    }

    private func showDuplicateDialog() {
        duplicateName = "\(template.name ?? "Template") (Copy)"
        activeSheet = .duplicate
    }

    // Centralized presentation helpers to avoid modal race conditions
    private func presentEdit() {
        showingDeleteConfirmation = false
        activeSheet = .edit(template)
    }

    private func presentDuplicate() {
        showingDeleteConfirmation = false
        duplicateName = "\(template.name ?? "Template") (Copy)"
        activeSheet = .duplicate
    }

    private func presentDeleteConfirmation() {
        if activeSheet != nil {
            activeSheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.showingDeleteConfirmation = true
            }
        } else {
            showingDeleteConfirmation = true
        }
    }

    private func duplicateTemplate() async {
        let name = duplicateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        // Ensure no sheet is active when switching to edit of the new copy
        activeSheet = nil

        if let newTemplate = await templateManager.createCustomTemplate(name: name,
                                                                        basedOn: template,
                                                                        fieldConfigs: nil) {
            // Open the builder on the new copy for immediate edits
            DispatchQueue.main.async {
                activeSheet = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                activeSheet = .edit(newTemplate)
            }
        }
    }

    private func deleteTemplate() async {
        // Ensure no conflicting sheets are active
        activeSheet = nil
        showingDeleteConfirmation = false

        if await templateManager.deleteTemplate(template) {
            // Explicitly dismiss to clear navigation selection and avoid re-presentations
            dismiss()
        }
    }

    private func refreshSessionTitle() async {
        sessionTitle = await sessionManager.getCurrentSessionInfo()
    }
}


// MARK: - Supporting Views

struct FieldConfigurationRow: View {
    let config: TemplateFieldConfiguration
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                // Field number and name
                HStack(spacing: 6) {
                    Text("#\(index)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 24, alignment: .center)

                    Text(config.fieldName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()
                }

                // Visibility badge
                Text(visibilityText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Circle()
                            .fill(visibilityColor.opacity(0.2))
                    )
                    .foregroundColor(visibilityColor)
            }

            // Default value
            if let defaultValue = config.defaultValue {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Default: \(defaultValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            } else {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "minus.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("No default value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Validation pattern
            if let validation = config.validation {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text("Validation: \(validation)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Prefix/Suffix formatting
            if config.prefix != nil || config.suffix != nil {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "textformat")
                        .font(.caption)
                        .foregroundColor(.purple)

                    if let prefix = config.prefix {
                        Text("Prefix: \"\(prefix)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let suffix = config.suffix {
                        if config.prefix != nil { Text("•").foregroundColor(.secondary) }
                        Text("Suffix: \"\(suffix)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var visibilityColor: Color {
        switch config.visibility {
        case .required: return .red
        case .visible: return .orange
        case .hidden: return .gray
        }
    }

    private var visibilityText: String {
        switch config.visibility {
        case .required: return "REQ"
        case .visible: return "VIS"
        case .hidden: return "HID"
        }
    }
}

#Preview {
    let template = InspectionTemplate()
    template.name = "Preview Template"
    template.templateType = "PU"
    template.isBuiltIn = false

    return TemplateDetailView(template: template)
}

// MARK: - Extensions

// Template field name casing extension for better display
extension String {
    var fieldDisplayName: String {
        switch self {
        case "itemDescription": return "Item Description"
        case "irm": return "IRM"
        case "partNumber": return "Part Number"
        case "shouldBe": return "Should Be"
        case "xCoordinate": return "X Coordinate"
        case "yCoordinate": return "Y Coordinate"
        case "zCoordinate": return "Z Coordinate"
        default: return self.capitalized
        }
    }
}
