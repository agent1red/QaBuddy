//
//  TemplateBuilderView.swift
//  QA Buddy PU/NC Template System - Template Builder Interface
//  Phase 3.2 - Subtask 1.3: Placeholder Implementation

import SwiftUI
import CoreData

struct TemplateBuilderView: View {
    let template: InspectionTemplate?

    @StateObject private var templateManager = TemplateManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var templateName = ""
    @State private var templateType = "PU"

    init(template: InspectionTemplate? = nil) {
        self.template = template
        _templateName = State(initialValue: template?.name ?? "")
        _templateType = State(initialValue: template?.templateType ?? "PU")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Template Configuration")) {
                    TextField("Template Name", text: $templateName)

                    Picker("Template Type", selection: $templateType) {
                        Text("Pickup (PU)").tag("PU")
                        Text("Non-Conformance (NC)").tag("NC")
                    }
                }

                Section {
                    Text("Template Builder Interface")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if let template = template {
                        Text("Editing: \(template.name ?? "Unknown")")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Creating new custom template")
                            .foregroundColor(.secondary)
                    }

                    Text("Field configuration interface will be implemented in Subtask 1.3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // TODO: Implement save functionality
                        dismiss()
                    }
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    TemplateBuilderView()
}
