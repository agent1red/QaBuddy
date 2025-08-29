//  NewSessionView.swift
//  QA Buddy
//
//  Created by Kevin Hudson on 8/29/25.
//

import SwiftUI

struct NewSessionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var sessionManager = SessionManager.shared

    @State private var sessionName: String = ""
    @State private var aircraftTailNumber: String = ""
    @State private var selectedInspectionType: InspectionType = .preFlight
    @State private var inspectorName: String = ""
    @State private var isCreating = false
    @State private var showInspectorPicker = false

    // FAA Standard Aircraft Registration formats
    private let tailNumberPatterns = [
        "N" + String(repeating: "#", count: 5),
        "N" + String(repeating: "#", count: 4) + Character("A").description.uppercased(),
        "N" + String(repeating: "#", count: 3) + String(repeating: "A", count: 2)
    ]

    var body: some View {
        NavigationStack {
            Form {
                sessionDetailsSection
                aircraftSection
                inspectionDetailsSection
                inspectorSection
            }
            .navigationTitle("New Inspection Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createNewSession()
                    }
                    .disabled(!isFormValid)
                    .bold()
                }
            }
            .overlay {
                if isCreating {
                    ProgressView("Creating session...")
                        .padding()
                        .background(Color(.systemBackground).opacity(0.9))
                        .cornerRadius(10)
                        .shadow(radius: 5)
                }
            }
        }
    }

    // MARK: - Form Sections

    private var sessionDetailsSection: some View {
        Section(header: Text("Session Details")) {
            TextField("Session Name", text: $sessionName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onSubmit {
                    // Auto-suggest based on inspection type
                    if sessionName.isEmpty {
                        sessionName = selectedInspectionType.suggestedSessionName()
                    }
                }

            Text("This will name your session and photos (e.g., 'Morning Preflight')")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var aircraftSection: some View {
        Section(header: Text("Aircraft Details")) {
            TextField("Tail Number (e.g., N12345)", text: $aircraftTailNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .onChange(of: aircraftTailNumber) { oldValue, newValue in
                    aircraftTailNumber = formatTailNumber(newValue.uppercased())
                }

            if !aircraftTailNumber.isEmpty {
                Text("Aircraft: \(aircraftTailNumber)")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private var inspectionDetailsSection: some View {
        Section(header: Text("Inspection Type")) {
            Picker("Type", selection: $selectedInspectionType) {
                ForEach(InspectionType.allCases.filter { $0 != .other }, id: \.self) { type in
                    Text(type.displayName)
                        .tag(type)
                }

                Divider()

                ForEach([InspectionType.other, InspectionType.otherInspection], id: \.self) { type in
                    Text(type.displayName)
                        .tag(type)
                }
            }
            .pickerStyle(.navigationLink)

            Text(selectedInspectionType.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var inspectorSection: some View {
        Section(header: Text("Inspector")) {
            TextField("Inspector Name", text: $inspectorName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Picker("Common Names", selection: $inspectorName) {
                Text("Select Saved Inspector").tag("")
                // TODO: Load from previous sessions
                Divider()
                Text("John Smith").tag("John Smith")
                Text("Sarah Johnson").tag("Sarah Johnson")
                Text("Mike Rodriguez").tag("Mike Rodriguez")
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !sessionName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !inspectorName.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!aircraftTailNumber.isEmpty || selectedInspectionType != .preFlight)
    }

    // MARK: - Actions

    private func createNewSession() {
        guard isFormValid && !isCreating else { return }

        isCreating = true

        let finalSessionName = sessionName.trimmingCharacters(in: .whitespaces)
        let finalAircraftTail = aircraftTailNumber.trimmingCharacters(in: .whitespaces).isEmpty ?
                               nil : aircraftTailNumber.trimmingCharacters(in: .whitespaces)

        Task {
            let newSession = await sessionManager.createSession(
                name: finalSessionName,
                aircraftTailNumber: finalAircraftTail,
                inspectionType: selectedInspectionType,
                inspectorName: inspectorName.trimmingCharacters(in: .whitespaces)
            )

            await MainActor.run {
                isCreating = false
                if newSession != nil {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Utilities

    private func formatTailNumber(_ input: String) -> String {
        // Basic FAA tail number formatting (N followed by numbers/letters)
        let cleaned = input.replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
        guard cleaned.hasPrefix("N") && cleaned.count <= 6 else { return String(cleaned.prefix(6)) }

        return cleaned
    }
}

// MARK: - InspectionType Extensions

extension InspectionType {
    /// Get suggested session names based on inspection type
    func suggestedSessionName() -> String {
        switch self {
        case .preFlight: return "Morning Preflight"
        case .postFlight: return "Evening Postflight"
        case .maintenance: return "Maintenance Inspection"
        case .cabin: return "A Deck Inspection"
        case .lowerDeck: return "B Deck Inspection"
        case .flightDeck: return "Flight Deck Check"
        case .leftLandingGear: return "Left MLG Inspection"
        case .rightLandingGear: return "Right MLG Inspection"
        case .avionics: return "Avionics Inspection"
        case .propulsion: return "Engine Inspection"
        case .leftWing: return "Left Wing Inspection"
        case .rightWing: return "Right Wing Inspection"
        case .other, .otherInspection: return "General Inspection"
        }
    }

    /// Detailed descriptions for each inspection type
    var description: String {
        switch self {
        case .preFlight:
            return "Pre-flight inspection typically conducted before each flight to ensure airworthiness and safety."
        case .postFlight:
            return "Post-flight inspection to check for flight damage, wear, and maintenance needs."
        case .maintenance:
            return "Scheduled or unscheduled maintenance activities requiring documentation."
        case .cabin:
            return "A Deck (cabin) inspection focusing on passenger area, emergency equipment, and safety features."
        case .lowerDeck:
            return "B Deck (lower deck/cargo area) inspection and maintenance activities."
        case .flightDeck:
            return "Flight Deck (cockpit) inspection including instruments, controls, and pilot equipment."
        case .leftLandingGear:
            return "Left Main Landing Gear and Wheels inspection, crucial for aircraft safety and operation."
        case .rightLandingGear:
            return "Right Main Landing Gear and Wheels inspection, ensuring balanced landing gear performance."
        case .avionics:
            return "Avionics systems inspection including radios, navigation, and electrical components."
        case .propulsion:
            return "Engine inspection and maintenance, critical for aircraft propulsion systems."
        case .leftWing:
            return "Left wing inspection including structure, fuel system, and flight control surfaces."
        case .rightWing:
            return "Right wing inspection ensuring structural integrity and flight control functionality."
        case .other, .otherInspection:
            return "Custom or specialty inspection not covered by standard categories."
        }
    }
}

// MARK: - Preview

struct NewSessionView_Previews: PreviewProvider {
    static var previews: some View {
        NewSessionView()
    }
}
