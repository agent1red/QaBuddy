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
    @State private var selectedPresetName: String = "" // Separate binding for Picker

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

                ForEach([InspectionType.other], id: \.self) { type in
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

            Picker("Common Names", selection: $selectedPresetName) {
                Text("Select Saved Inspector").tag("")
                // TODO: Load from previous sessions
                Divider()
                Text("John Smith").tag("John Smith")
                Text("Sarah Johnson").tag("Sarah Johnson")
                Text("Mike Rodriguez").tag("Mike Rodriguez")
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPresetName) { oldValue, newValue in
                // Only update inspectorName when non-empty selection is made
                if !newValue.isEmpty {
                    inspectorName = newValue
                    selectedPresetName = "" // Reset picker after selection
                }
            }
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
        case .generalMaintenance: return "Maintenance Inspection"
        case .aDeck: return "A Deck Inspection"
        case .bDeck: return "B Deck Inspection"
        case .flightDeck: return "Flight Deck Check"
        case .leftMLG: return "Left MLG Inspection"
        case .rightMLG: return "Right MLG Inspection"
        case .fwEEBay: return "FW EE Bay Inspection"
        case .leftEngine: return "Left Engine Inspection"
        case .leftWing: return "Left Wing Inspection"
        case .rightWing: return "Right Wing Inspection"
        // Add cases for other zones as needed
        default: return "General Inspection"
        }
    }

    /// Detailed descriptions for each inspection type
    var description: String {
        switch self {
        case .preFlight:
            return "Pre-flight inspection typically conducted before each flight to ensure airworthiness and safety."
        case .postFlight:
            return "Post-flight inspection to check for flight damage, wear, and maintenance needs."
        case .generalMaintenance:
            return "Scheduled or unscheduled maintenance activities requiring documentation."
        case .aDeck:
            return "A Deck (passenger deck) inspection focusing on cabin area, emergency equipment, and safety features."
        case .bDeck:
            return "B Deck (cargo deck) inspection and maintenance activities."
        case .flightDeck:
            return "Flight Deck (cockpit) inspection including instruments, controls, and pilot equipment."
        case .leftMLG:
            return "Left Main Landing Gear and Wheel Well inspection, crucial for aircraft safety and operation."
        case .rightMLG:
            return "Right Main Landing Gear and Wheel Well inspection, ensuring balanced landing gear performance."
        case .leftWing:
            return "Left wing structure, fuel system, and flight control surfaces inspection."
        case .rightWing:
            return "Right wing structure, fuel system, and flight control surfaces inspection."
        case .empennage:
            return "Empennage (tail section) inspection including vertical and horizontal stabilizers."
        case .fwEEBay:
            return "Forward Electronic Equipment Bay inspection including avionics and communication systems."
        case .aftEEBay:
            return "Aft Electronic Equipment Bay inspection and maintenance."
        case .leftACBay:
            return "Left Air Conditioning Bay inspection and servicing."
        case .rightACBay:
            return "Right Air Conditioning Bay inspection and servicing."
        case .leftEngine:
            return "Left engine inspection including cowling, pylon, and associated systems."
        case .rightEngine:
            return "Right engine inspection including cowling, pylon, and associated systems."
        case .apu:
            return "Auxiliary Power Unit inspection and maintenance."
        case .nlg:
            return "Nose Landing Gear inspection and wheel well check."
        case .forwardCargo:
            return "Forward cargo compartment inspection."
        case .aftCargo:
            return "Aft cargo compartment inspection."
        case .fortyEightSection:
            return "48 Section (aft pressure bulkhead) inspection."
        case .other:
            return "Custom or specialty inspection not covered by standard categories."
        case .aog:
            return "Aircraft on Ground maintenance or emergency inspection."
        default:
            return "Inspection type description not yet available."
        }
    }
}

// MARK: - Preview

struct NewSessionView_Previews: PreviewProvider {
    static var previews: some View {
        NewSessionView()
    }
}
