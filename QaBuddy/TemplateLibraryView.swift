//
//  TemplateLibraryView.swift
//  QA Buddy PU/NC Template System - Template Library View
//  Phase 3.2 - Subtask 1.1: Create Template Library View

import SwiftUI
import CoreData

// MARK: - Template References (implemented in separate files)

struct TemplateLibraryView: View {
    @StateObject private var templateManager = TemplateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @State private var searchText = ""
    @State private var selectedType: TemplateTypeFilter = .all
    @State private var showingTemplateDetail = false
    @State private var selectedTemplate: InspectionTemplate?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Header
                VStack(spacing: 16) {
                    HStack {
                        Text("Template Library")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        if templateManager.hasCustomTemplates {
                            NavigationLink(destination: TemplateBuilderView()) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.title3)
                            }
                        }
                    }

                    // Type Filter Buttons
                    HStack(spacing: 12) {
                        FilterButton(title: "All", count: templateManager.templates.count,
                                   isSelected: selectedType == .all) {
                            selectedType = .all
                        }

                        FilterButton(title: "PU", count: puTemplateCount,
                                   isSelected: selectedType == .pu,
                                   color: .green) {
                            selectedType = .pu
                        }

                        FilterButton(title: "NC", count: ncTemplateCount,
                                   isSelected: selectedType == .nc,
                                   color: .blue) {
                            selectedType = .nc
                        }

                        Spacer()
                    }
                }
                .padding()
                .background(Color(.systemBackground))

                // Template List
                List {
                    // Built-in Templates Section
                    if !builtInFiltered.isEmpty {
                        Section(header: Text("Built-in Templates")) {
                            ForEach(builtInFiltered, id: \.id) { template in
                                TemplateRowView(template: template, isBuiltIn: true)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedTemplate = template
                                        showingTemplateDetail = true
                                    }
                            }
                        }
                    }

                    // Custom Templates Section
                    if !customFiltered.isEmpty {
                        Section(header: Text("Custom Templates")) {
                            ForEach(customFiltered, id: \.id) { template in
                                TemplateRowView(template: template, isBuiltIn: false)
                                    .contentShape(Rectangle())
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            // Delete action
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            // Duplicate action
                                        } label: {
                                            Label("Duplicate", systemImage: "doc.on.doc")
                                        }
                                        .tint(.blue)
                                    }
                                    .onTapGesture {
                                        selectedTemplate = template
                                        showingTemplateDetail = true
                                    }
                            }
                        }
                    }

                    // Empty State
                    if filteredTemplates.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "clipboard")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)

                            Text("No templates found")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            if templateManager.templates.isEmpty {
                                Text("Templates will appear here once loaded from the system.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            } else {
                                Text("Try adjusting your search or filters.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            if !searchText.isEmpty || selectedType != .all {
                                Button("Clear Filters") {
                                    searchText = ""
                                    selectedType = .all
                                }
                                .foregroundColor(.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search templates...")
                .navigationBarTitleDisplayMode(.inline)
                .refreshable {
                    await templateManager.loadTemplates()
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingTemplateDetail) {
                if let template = selectedTemplate {
                    TemplateDetailView(template: template)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredTemplates: [InspectionTemplate] {
        let templates: [InspectionTemplate]
        switch selectedType {
        case .all:
            templates = templateManager.templates
        case .pu:
            templates = templateManager.templates.filter { $0.templateType == "PU" }
        case .nc:
            templates = templateManager.templates.filter { $0.templateType == "NC" }
        }

        if searchText.isEmpty {
            return templates
        } else {
            return templates.filter {
                ($0.name ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.templateType ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var builtInFiltered: [InspectionTemplate] {
        filteredTemplates.filter { $0.isBuiltIn }
    }

    private var customFiltered: [InspectionTemplate] {
        filteredTemplates.filter { !$0.isBuiltIn }
    }

    private var puTemplateCount: Int {
        templateManager.templates.filter { $0.templateType == "PU" }.count
    }

    private var ncTemplateCount: Int {
        templateManager.templates.filter { $0.templateType == "NC" }.count
    }
}

// MARK: - Supporting Views

struct FilterButton: View {
    let title: String
    let count: Int
    var isSelected: Bool = false
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text("(\(count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color.opacity(0.2) : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct TemplateRowView: View {
    let template: InspectionTemplate
    let isBuiltIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(template.name ?? "Untitled")
                            .font(.headline)

                        if isBuiltIn {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }

                        Spacer()

                        // Template type badge
                        Text(template.templateTypeDisplay)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(templateTypeColor.opacity(0.2))
                            )
                            .foregroundColor(templateTypeColor)
                    }

                    // Field count and visibility indicators
                    HStack(spacing: 12) {
                        Text(fieldCountText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let validationStatus = validationStatus {
                            Label(validationStatus.text, systemImage: validationStatus.icon)
                                .font(.caption)
                                .foregroundColor(validationStatus.color)
                        }
                    }

                    // Field configuration preview
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(fieldConfigurationPreview, id: \.name) { field in
                                Text(field.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(field.color.opacity(0.2))
                                    )
                                    .foregroundColor(field.color)
                            }
                        }
                    }

                    // Last modified
                    if let lastModified = template.lastModified {
                        Text("Modified \(lastModified.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Computed Properties

    private var templateTypeColor: Color {
        switch template.templateType {
        case "PU": return .green
        case "NC": return .blue
        default: return .primary
        }
    }

    private var fieldCountText: String {
        let configs = template.decodedFieldConfigurations
        return "\(configs.count) fields"
    }

    private var fieldConfigurationPreview: [FieldPreview] {
        let configs = template.decodedFieldConfigurations
        var preview: [FieldPreview] = []

        // Group by visibility and take first 3 examples
        let requiredFields = configs.filter { $0.visibility == .required }
        let visibleFields = configs.filter { $0.visibility == .visible }
        let hiddenFields = configs.filter { $0.visibility == .hidden }

        if let firstRequired = requiredFields.first {
            preview.append(FieldPreview(name: firstRequired.fieldName, color: .red))
        }

        if let firstVisible = visibleFields.first {
            preview.append(FieldPreview(name: firstVisible.fieldName, color: .orange))
        }

        if let firstHidden = hiddenFields.first {
            preview.append(FieldPreview(name: firstHidden.fieldName, color: .gray))
        }

        return preview
    }

    private var validationStatus: ValidationStatus? {
        guard !isBuiltIn else { return nil }

        let isValid = template.isValid
        return isValid ? nil : ValidationStatus(
            text: "Review",
            icon: "exclamationmark.triangle",
            color: .orange
        )
    }
}

struct FieldPreview: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
}

struct ValidationStatus {
    let text: String
    let icon: String
    let color: Color
}

enum TemplateTypeFilter {
    case all, pu, nc
}

#Preview {
    TemplateLibraryView()
}
