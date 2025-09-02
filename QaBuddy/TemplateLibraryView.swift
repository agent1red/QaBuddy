//
//  TemplateLibraryView.swift
//  QA Buddy PU/NC Template System - Template Library View
//  Phase 3.2 - Subtask 1.1: Create Template Library View

import SwiftUI
import CoreData

// Local template struct for display purposes
struct DisplayTemplate: Identifiable {
    var id: UUID
    var name: String?
    var templateType: String?
    var isBuiltIn: Bool
    var fieldCount: Int
    var lastModified: Date?

    init(id: UUID = UUID(), name: String?, templateType: String?, isBuiltIn: Bool = false, fieldCount: Int = 0, lastModified: Date? = nil) {
        self.id = id
        self.name = name
        self.templateType = templateType
        self.isBuiltIn = isBuiltIn
        self.fieldCount = fieldCount
        self.lastModified = lastModified
    }
}

// Simple template manager for demo
class SimpleTemplateManager: ObservableObject {
    @Published var templates: [DisplayTemplate] = []

    static let shared = SimpleTemplateManager()

    init() {
        // Mock data for testing
        templates = [
            DisplayTemplate(id: UUID(), name: "FOD Cleanup", templateType: "PU", isBuiltIn: true, fieldCount: 9, lastModified: Date().addingTimeInterval(-86400)),
            DisplayTemplate(id: UUID(), name: "Standard QA Write-up", templateType: "PU", isBuiltIn: true, fieldCount: 9, lastModified: Date().addingTimeInterval(-172800)),
            DisplayTemplate(id: UUID(), name: "Equipment Defect", templateType: "NC", isBuiltIn: true, fieldCount: 3, lastModified: Date().addingTimeInterval(-259200))
        ]
    }

    func loadTemplates() async {
        // Already loaded in init
    }

    func addTemplate(name: String, templateType: String, fieldCount: Int) {
        let newTemplate = DisplayTemplate(
            name: name,
            templateType: templateType,
            isBuiltIn: false,
            fieldCount: fieldCount,
            lastModified: Date()
        )
        templates.append(newTemplate)
        print("Template added to library: \(name) with \(fieldCount) fields")
    }
}

struct SimpleTemplateBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var templateName = ""
    @State private var templateType = "PU"
    @State private var fieldConfigs: [String] = []
    @State private var newFieldName = ""

    var onSaveTemplate: ((String, String, Int) -> Void)?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Template Information")) {
                    TextField("Template Name", text: $templateName)
                    Picker("Type", selection: $templateType) {
                        Text("Pickup (PU)").tag("PU")
                        Text("Non-Conformance (NC)").tag("NC")
                    }
                }

                Section(header: Text("Fields")) {
                    ForEach(fieldConfigs, id: \.self) { field in
                        Text("• " + field)
                    }

                    if fieldConfigs.isEmpty {
                        Text("No fields added yet")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        TextField("Field name", text: $newFieldName)
                        Button("Add") {
                            if !newFieldName.isEmpty {
                                fieldConfigs.append(newFieldName)
                                newFieldName = ""
                            }
                        }
                        .disabled(newFieldName.isEmpty)
                    }
                }

                Section {
                    Button("Save Template") {
                        if !templateName.isEmpty {
                            print("Template saved: \(templateName) with \(fieldConfigs.count) fields")
                            onSaveTemplate?(templateName, templateType, fieldConfigs.count)
                            dismiss()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(templateName.isEmpty)
                    .tint(.green)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Reset") {
                            templateName = ""
                            templateType = "PU"
                            fieldConfigs.removeAll()
                            newFieldName = ""
                        }
                        .foregroundColor(.red)
                        Spacer()
                    }
                }
            }
            .navigationTitle("New Template")
        }
    }
}

struct TemplateLibraryView: View {
    @StateObject private var templateManager = SimpleTemplateManager.shared
    @State private var showingTemplateBuilder = false
    @State private var searchText = ""
    @State private var showingTemplateDetails = false
    @State private var selectedTemplate: DisplayTemplate?
    @State private var navigationPath = NavigationPath()

    // Template field preview helper
    private func printTemplatePreview(name: String, type: String, fieldCount: Int) {
        print("\n📋 TEMPLATE PREVIEW: \(name)")
        print("🏷️ Type: \(type)")
        print("📊 Fields: \(fieldCount)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔗 In full app, this would show:")
        print("✅ Field validation rules")
        print("✅ Default values")
        print("✅ Prefix/suffix formatters")
        print("✅ Required vs optional fields")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    }

    var filteredTemplates: [DisplayTemplate] {
        if searchText.isEmpty {
            return templateManager.templates
        } else {
            return templateManager.templates.filter { template in
                (template.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ((template.templateType ?? "").localizedCaseInsensitiveContains(searchText))
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with Template Builder Navigation
                HStack {
                    Text("Template Library")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(action: {
                        showingTemplateBuilder = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                    }
                }
                .padding()

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    ZStack(alignment: .leading) {
                        if searchText.isEmpty {
                            Text("Search templates...")
                                .foregroundColor(.secondary)
                        }
                        TextField("", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Template List
                if templateManager.templates.isEmpty {
                    // Empty State (fallback, though templates should load)
                    VStack(spacing: 32) {
                        Image(systemName: "clipboard")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)

                        Text("Loading Templates...")
                            .font(.title)
                            .foregroundColor(.secondary)

                        Button(action: {
                            showingTemplateBuilder = true
                        }) {
                            Label("Create New Template", systemImage: "plus")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Template List
                    List(filteredTemplates, id: \.id) { template in
                        TemplateRow(template: template)
                            .contentShape(Rectangle())  // Make entire row tappable
                            .onTapGesture {
                                selectedTemplate = template
                                showingTemplateDetails = true
                            }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingTemplateBuilder) {
            SimpleTemplateBuilderView { name, templateType, fieldCount in
                templateManager.addTemplate(name: name, templateType: templateType, fieldCount: fieldCount)
            }
        }
        .task {
            await templateManager.loadTemplates()
        }
        .alert("Template Details", isPresented: $showingTemplateDetails, actions: {
            Button("Use Template", action: {
                showingTemplateDetails = false
                let templateName = selectedTemplate?.name ?? "Unknown"
                print("Starting inspection with template: \(templateName)")

                // Simulate session creation and navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // This would navigate to write-up form in the real app
                    print("✅ Template '\(templateName)' is ready for inspection")
                    print("🚀 In a full app, this would navigate to the write-up form with \(selectedTemplate?.fieldCount ?? 0) fields")
                }
            })
            Button("View Template", action: {
                showingTemplateDetails = false
                let templateName = selectedTemplate?.name ?? "Unknown"
                let fieldCount = selectedTemplate?.fieldCount ?? 0
                let type = selectedTemplate?.templateType == "PU" ? "Pickup" : "Non-Conformance"

                // Show template preview
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    printTemplatePreview(name: templateName, type: type, fieldCount: fieldCount)
                }
            })
            Button("Cancel", role: .cancel, action: {})
        }, message: {
            if let template = selectedTemplate {
                Text("""
                Name: \(template.name ?? "Untitled")
                Type: \(template.templateType == "PU" ? "Pickup" : "Non-Conformance")
                Fields: \(template.fieldCount)
                Status: \(template.isBuiltIn ? "Built-in" : "Custom")
                """)
            } else {
                Text("No template selected")
            }
        })
    }
}

struct TemplateRow: View {
    let template: DisplayTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(template.name ?? "Untitled")
                            .font(.headline)

                        if template.isBuiltIn {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }

                        Spacer()

                        HStack {
                            Text(template.templateType == "PU" ? "Pickup" : "Non-Conformance")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    template.templateType == "PU" ?
                                    Color.green.opacity(0.2) :
                                    Color.blue.opacity(0.2)
                                )
                                .foregroundColor(template.templateType == "PU" ? .green : .blue)
                                .cornerRadius(8)

                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }

                    Text("\(template.fieldCount) fields")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let lastModified = template.lastModified {
                        Text("Modified \(lastModified.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}


#Preview {
    TemplateLibraryView()
}
