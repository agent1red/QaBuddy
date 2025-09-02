//  TemplateLibraryView.swift
//  QA Buddy PU/NC Template System - Template Library View

import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TemplateLibraryView: View {
    @StateObject private var templateManager = TemplateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @State private var showingTemplateTypePicker = false
    @State private var showingTemplateBuilder = false
    @State private var selectedTemplateType = ""
    @State private var selectedTemplate: InspectionTemplate? = nil
    @State private var searchText = ""

    // Filter the templates based on search text
    private var filteredTemplates: [InspectionTemplate] {
        if searchText.isEmpty {
            return templateManager.templates
        }
        return templateManager.templates.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.templateType ?? "").localizedCaseInsensitiveContains(searchText) ||
            $0.decodedFieldConfigurations.contains { config in
                config.fieldName.localizedCaseInsensitiveContains(searchText) ||
                (config.defaultValue ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // Group templates by type for display
    private var groupedTemplates: [String: [InspectionTemplate]] {
        Dictionary(grouping: filteredTemplates) { template in
            template.templateType ?? "Unknown"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with Search and Create
                VStack(spacing: 0) {
                    HStack {
                        Text("Template Library")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        Button(action: {
                            showingTemplateTypePicker = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)

                        TextField("Search templates...", text: $searchText)
                            .padding(.vertical, 8)
                            .padding(.leading, 8)

                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.trailing, 12)
                        }
                    }
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .background(Color.primary.opacity(0.05))

                // Templates List
                List {
                    // Show empty state if no templates
                    if templateManager.templates.isEmpty {
                        emptyStateView
                    } else {
                        // Built-in Templates Section
                        let builtInVersions = groupedTemplates.values.flatMap({ $0 }).filter({ $0.isBuiltIn }).sorted(by: { ($0.templateType ?? "") < ($1.templateType ?? "") })
                        if !builtInVersions.isEmpty {
                            Section(header: Text("Built-in Templates")) {
                                ForEach(builtInVersions) { template in
                                    templateRow(for: template, isBuiltIn: true)
                                }
                            }
                        }

                        // Custom Templates Section
                        let customVersions = groupedTemplates.values.flatMap({ $0 }).filter({ !$0.isBuiltIn }).sorted(by: { ($0.name ?? "") < ($1.name ?? "") })
                        if !customVersions.isEmpty {
                            Section(header: Text("Custom Templates")) {
                                ForEach(customVersions) { template in
                                    templateRow(for: template, isBuiltIn: false)
                                }
                            }
                        }

                        // Show no results if search found nothing
                        if !searchText.isEmpty && filteredTemplates.isEmpty {
                            Section {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass.circle")
                                            .font(.largeTitle)
                                            .foregroundColor(.secondary)

                                        Text("No templates found")
                                            .font(.headline)
                                            .foregroundColor(.secondary)

                                        Text("Try a different search term")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 32)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Templates")

                // Template Statistics Footer
                if !templateManager.templates.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 16) {
                            Spacer()

                            Label("\(templateManager.builtInTemplateCount) Built-in",
                                  systemImage: "star")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Divider()
                                .frame(height: 20)

                            Label("\(templateManager.customTemplateCount) Custom",
                                  systemImage: "plus")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Divider()
                                .frame(height: 20)

                            Label("\(templateManager.totalTemplateCount) Total",
                                  systemImage: "square.stack.3d.down.right")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.05))
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedTemplate != nil },
                set: { if !$0 { selectedTemplate = nil } }
            )) {
                if let template = selectedTemplate {
                    TemplateDetailView(template: template)
                }
            }
            .sheet(isPresented: $showingTemplateTypePicker) {
                TemplateTypePicker { templateType in
                    selectedTemplateType = templateType
                    showingTemplateBuilder = true
                }
            }
            .sheet(isPresented: $showingTemplateBuilder) {
                TemplateBuilderView(templateType: selectedTemplateType)
            }
        }
        .task {
            await templateManager.loadTemplates()
        }
    }

    // MARK: - Private Views

    private var emptyStateView: some View {
        Section {
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No Templates Yet")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Create your first template to get started with inspection write-ups")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Button {
                        showingTemplateTypePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Create First Template")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                    }

                    Button {
                        // Add sample templates
                        addSampleTemplates()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Add Sample Templates")
                        }
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.vertical, 40)
        }
    }

    private func templateRow(for template: InspectionTemplate, isBuiltIn: Bool) -> some View {
        Button {
            selectedTemplate = template
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    // Template Icon
                    if isBuiltIn {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.title3)
                    } else {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Template Name and Type
                        HStack(alignment: .center) {
                            Text(template.name ?? "Unnamed Template")
                                .font(.headline)

                            Spacer()

                            // Template type badge
                            Text(templateTypeBadge(for: template))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(templateTypeColor(for: template).opacity(0.1))
                                .foregroundColor(templateTypeColor(for: template))
                                .cornerRadius(8)
                        }

                        // Field count and status
                        HStack(spacing: 12) {
                            Text(fieldCountText(for: template))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let lastModified = template.lastModified {
                                Text(lastModified.formatted(.relative(presentation: .named)))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Field preview badges
                        let configs = template.decodedFieldConfigurations
                        if !configs.isEmpty {
                            HStack(spacing: 6) {
                                fieldVisibilityIndicator(for: configs)
                                if configs.count > 3 {
                                    Text("+\(configs.count - 3)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: isBuiltIn ? .leading : .trailing) {
            if !isBuiltIn {
                Button(role: .destructive) {
                    Task {
                        await deleteTemplate(template)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func templateTypeBadge(for template: InspectionTemplate) -> String {
        switch template.templateType {
        case "PU": return "PU"
        case "NC": return "NC"
        default: return "UN"
        }
    }

    private func templateTypeColor(for template: InspectionTemplate) -> Color {
        switch template.templateType {
        case "PU": return .green
        case "NC": return .blue
        default: return .gray
        }
    }

    private func fieldCountText(for template: InspectionTemplate) -> String {
        let configs = template.decodedFieldConfigurations
        return "\(configs.count) field\(configs.count != 1 ? "s" : "")"
    }

    private func fieldVisibilityIndicator(for configs: [TemplateFieldConfiguration]) -> some View {
        HStack(spacing: 4) {
            let required = configs.filter { $0.visibility == .required }.count
            let visible = configs.filter { $0.visibility == .visible }.count
            let hidden = configs.filter { $0.visibility == .hidden }.count

            if required > 0 {
                Circle()
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 6, height: 6)
            }
            if visible > 0 {
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 6, height: 6)
            }
            if hidden > 0 {
                Circle()
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func addSampleTemplates() {
        Task {
            // Add FOD template
            if !templateManager.builtInTemplates.contains(where: { $0.name == "FOD Cleanup" }) {
                let fodConfig = [
                    TemplateFieldConfiguration(fieldName: "issue", visibility: .required, prefix: "FOD PRESENT. "),
                    TemplateFieldConfiguration(fieldName: "location", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "xCoordinate", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "yCoordinate", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "zCoordinate", visibility: .required)
                ]

                await templateManager.createBuiltInTemplate(name: "FOD Cleanup", templateType: "PU", fieldConfigs: fodConfig)
            }

            // Add QA Write-up template
            if !templateManager.builtInTemplates.contains(where: { $0.name == "Standard QA Write-up" }) {
                let qaConfig = [
                    TemplateFieldConfiguration(fieldName: "itemDescription", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "issue", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "shouldBe", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "location", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "xCoordinate", visibility: .visible),
                    TemplateFieldConfiguration(fieldName: "yCoordinate", visibility: .visible),
                    TemplateFieldConfiguration(fieldName: "zCoordinate", visibility: .visible)
                ]

                await templateManager.createBuiltInTemplate(name: "Standard QA Write-up", templateType: "PU", fieldConfigs: qaConfig)
            }

            // Add Equipment Defect template
            if !templateManager.builtInTemplates.contains(where: { $0.name == "Equipment Defect" }) {
                let defectConfig = [
                    TemplateFieldConfiguration(fieldName: "itemDescription", visibility: .required, defaultValue: "EQUIPMENT DEFECT"),
                    TemplateFieldConfiguration(fieldName: "irm", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "issue", visibility: .required, prefix: "EQUIPMENT DEFECT DISCOVERED. "),
                    TemplateFieldConfiguration(fieldName: "shouldBe", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "location", visibility: .required),
                    TemplateFieldConfiguration(fieldName: "xCoordinate", visibility: .visible),
                    TemplateFieldConfiguration(fieldName: "yCoordinate", visibility: .visible),
                    TemplateFieldConfiguration(fieldName: "zCoordinate", visibility: .visible)
                ]

                await templateManager.createBuiltInTemplate(name: "Equipment Defect", templateType: "NC", fieldConfigs: defectConfig)
            }

            await templateManager.loadTemplates()
        }
    }

    private func deleteTemplate(_ template: InspectionTemplate) async {
        if await templateManager.deleteTemplate(template) {
            print("✅ Deleted template: \(template.name ?? "Unknown")")
        } else {
            print("❌ Failed to delete template")
        }
    }
}

// MARK: - Template Type Picker Sheet

struct TemplateTypePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onTemplateTypeSelected: (String) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)

                    Text("New Template")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Choose the type of template you want to create")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                VStack(spacing: 24) {
                    // PU Template Option
                    Button(action: {
                        onTemplateTypeSelected("PU")
                        dismiss()
                    }) {
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Pickup (PU)")
                                            .font(.headline)
                                            .foregroundColor(.green)

                                        Text("Routine Inspections")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Text("• Daily quality assurance")
                                    Text("• Maintenance inspections")
                                    Text("• Routine compliance checks")
                                    Text("• Equipment inspections")

                                    Text("Where you pick up and address issues found during operations")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle")
                                    .font(.largeTitle)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }

                    // NC Template Option
                    Button(action: {
                        onTemplateTypeSelected("NC")
                        dismiss()
                    }) {
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Non-Conformance (NC)")
                                            .font(.headline)
                                            .foregroundColor(.blue)

                                        Text("Issue Resolution")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Text("• Equipment defects")
                                    Text("• Process non-compliance")
                                    Text("• Quality issues")
                                    Text("• Safety concerns")

                                    Text("Where you document and resolve non-conforming conditions")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .navigationTitle("Template Type")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            #endif
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            #endif
        }
    }
}

#Preview {
    TemplateLibraryView()
}
