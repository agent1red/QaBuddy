// SmartLocationField.swift
// Intelligent Location Entry System - Phase 3.2 Subtask 2.3
// Standalone smart location field component with real-time validation

import SwiftUI
import Combine

// Forward declarations (declared at end of file)
class _LocationSuggestionPill: UIView {}  // Dummy class for cross-file references
class _ZonePrefixChip: UIView {}           // Dummy class for cross-file references

extension LocationSuggestionPill {
    typealias SuggestionType = LocationSuggestionEngine.LocationSuggestion
}

extension ZonePrefixChip {
    typealias Source = String
}

struct SmartLocationField: View {
    @Binding var location: String
    let zonePrefix: String
    let validationError: Bool = false
    let showSuggestions: Bool = true

    @StateObject private var engine = LocationSuggestionEngine.shared
    @State private var userInput: String = ""
    @State private var formData = LocationFormData()
    @State private var recentLocations: [String] = []
    @State private var validationErrors: [String: String] = [:]
    @State private var lastSelectedSuggestion: LocationSuggestionEngine.LocationSuggestion?

    @FocusState private var isFieldFocused: Bool

    // Debounced auto-save and validation
    @State private var validationTimer: Timer?
    @State private var lastValidationTime: Date?
    private let validationDebounceInterval: TimeInterval = 0.3
    private let recentLocationsLimit = 5

    // Configuration
    var placeholder: String = "Enter location"
    var showHelperText: Bool = true
    var showRecentlyUsed: Bool = true
    var maxSuggestions: Int = 30  // Support all aviation zone suggestions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label and validation
            fieldHeader

            // Input field with zone prefix
            inputFieldStack

            // Helper text
            if showHelperText {
                helperTextSection
            }

            // Recently used locations
            if showRecentlyUsed && !recentLocations.isEmpty && userInput.isEmpty {
                recentlyUsedSection
            }

            // Suggestions
            if showSuggestions && isFieldFocused {
                suggestionsSection
            }
        }
        .animation(.easeInOut(duration: 0.2), value: validationError)
        .animation(.easeInOut(duration: 0.2), value: isFieldFocused)
        .onAppear {
            initializeField()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: userInput) { oldValue, newValue in
            handleInputChange(from: oldValue, to: newValue)
        }
        .onChange(of: location) { oldValue, newValue in
            // Sync binding changes to userInput for proper initialization
            syncLocationBindingToUserInput(newValue)
        }
    }

    // MARK: - Field Components

    private var fieldHeader: some View {
        HStack(spacing: 4) {
            Text("Location")
                .font(.caption)
                .foregroundColor(.secondary)

            if hasValidationError {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if isFieldValid && !userInput.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()

            if !recentLocations.isEmpty {
                Text("\(recentLocations.count) recent")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var inputFieldStack: some View {
        HStack(alignment: .center, spacing: 8) {
            // Zone prefix chip
            ZonePrefixChip(zone: zonePrefix)

            // Text field
            locationTextField

            // Quick actions
            if canShowQuickActions {
                quickActionButtons
            }
        }
        .padding(.vertical, 4)
    }

    private var locationTextField: some View {
        TextField(placeholder, text: $userInput)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .focused($isFieldFocused)
            .autocorrectionDisabled()
            .textCase(.uppercase)
            .onSubmit {
                finalizeLocation()
                isFieldFocused = false
            }
            .border(validationError || hasValidationError ? Color.red : Color.clear, width: validationError || hasValidationError ? 1 : 0)
    }

    @ViewBuilder
    private var quickActionButtons: some View {
        HStack(spacing: 4) {
            // Clear button
            if !userInput.isEmpty {
                Button(action: clearField) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            // Paste button
            if userInput.isEmpty {
                Button(action: pasteFromClipboard) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helper Sections

    private var helperTextSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let currentHelperText = getCurrentHelperText() {
                Text(currentHelperText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
                    .transition(.opacity)
            }

            if hasValidationError {
                ForEach(Array(validationErrors.values), id: \.self) { error in
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
            }
        }
    }

    private var recentlyUsedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent locations:")
                .font(.caption2)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recentLocations.prefix(recentLocationsLimit), id: \.self) { recentLocation in
                        RecentlyUsedChip(
                            location: recentLocation,
                            onSelected: { selectRecentLocation(recentLocation) }
                        )
                    }
                }
            }
            .frame(height: 30)
        }
    }

    private var suggestionsSection: some View {
        let suggestions = getFilteredSuggestions()

        return VStack(alignment: .leading, spacing: 8) {
            if !suggestions.isEmpty {
                Text("Suggestions:")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.id) { suggestion in
                            LocationSuggestionPill(
                                suggestion: suggestion,
                                userLocationInput: $userInput,
                                zonePrefix: zonePrefix,
                                isTextFieldFocused: _isFieldFocused,
                                onSuggestionSelected: { selectedSuggestion in
                                    handleSuggestionSelected(selectedSuggestion)
                                    recordSelection(selectedSuggestion)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Management

    private func initializeField() {
        // Handle zone prefix logic correctly
        if !location.isEmpty {
            // Check if location already has zone prefix
            if location.hasPrefix("\(zonePrefix) ") {
                // Location has prefix, extract user part
                let inputPart = String(location.dropFirst(zonePrefix.count + 1))
                userInput = inputPart.trimmingCharacters(in: .whitespaces)
            } else {
                // Location doesn't have prefix, use as-is
                userInput = location.trimmingCharacters(in: .whitespaces)
            }
        } else {
            // Empty location, start with empty user input (zone prefix will be visual only)
            userInput = ""
        }

        // Load recent locations for this zone
        loadRecentLocations()

        // Initial validation
        validateInput()
    }

    private func cleanup() {
        validationTimer?.invalidate()
        validationTimer = nil

        // Save final location
        updateLocation()
    }

    private func loadRecentLocations() {
        recentLocations = engine.getFrequentlyUsed(for: zonePrefix, limit: recentLocationsLimit)
    }

    private func updateLocation() {
        let fullLocation = userInput.isEmpty ? "" : "\(zonePrefix) \(userInput)"
        location = fullLocation
        formData.location = fullLocation
    }

    private func finalizeLocation() {
        updateLocation()
        if isFieldValid {
            saveToRecent()
            isFieldFocused = false
        }
    }

    private func saveToRecent() {
        guard !userInput.isEmpty else { return }

        var updatedRecent = recentLocations
        updatedRecent.removeAll { $0 == userInput }
        updatedRecent.insert(userInput, at: 0)

        if updatedRecent.count > recentLocationsLimit {
            updatedRecent = Array(updatedRecent.prefix(recentLocationsLimit))
        }

        recentLocations = updatedRecent

        // Update engine
        engine.recordUsage(zone: zonePrefix, suggestion: userInput)
    }

    // MARK: - Input Handling

    private func handleInputChange(from oldValue: String, to newValue: String) {
        // Update location immediately for form
        updateLocation()

        // Debounced validation
        validationTimer?.invalidate()
        validationTimer = Timer.scheduledTimer(withTimeInterval: validationDebounceInterval, repeats: false) { _ in
            Task { @MainActor in
                validateInput()

                // Update suggestions based on input
                // This will trigger view update in suggestionsSection
            }
        }
    }

    private func getFilteredSuggestions() -> [LocationSuggestionEngine.LocationSuggestion] {
        let allSuggestions = engine.getSuggestions(for: zonePrefix)

        if userInput.isEmpty {
            return Array(allSuggestions.prefix(maxSuggestions))
        } else {
            let filtered = allSuggestions.filter { suggestion in
                suggestion.text.localizedCaseInsensitiveContains(userInput) ||
                userInput.localizedCaseInsensitiveContains(suggestion.text)
            }
            return Array(filtered.prefix(maxSuggestions))
        }
    }

    private func getCurrentHelperText() -> String? {
        // Priority 1: Use the last selected suggestion's helper text (most reliable)
        if let storedSuggestion = lastSelectedSuggestion {
            return storedSuggestion.helperText
        }

        // Priority 2: Fall back to dynamic string parsing (for backward compatibility with typing)
        let trimmedInput = userInput.trimmingCharacters(in: .whitespaces)
        if trimmedInput.isEmpty {
            return nil
        }

        let lastWord = trimmedInput.split(separator: " ").last?.uppercased() ?? ""
        return engine.getHelperText(for: lastWord, in: zonePrefix)
    }

    private func handleSuggestionSelected(_ suggestion: LocationSuggestionEngine.LocationSuggestion) {
        // Store the last selected suggestion for helper text
        lastSelectedSuggestion = suggestion

        // Set the suggestion text - replace entire input, don't append
        let baseText = suggestion.text
        if suggestion.needsAdditionalInput {
            // For suggestions that need additional input, just set the base text and add space
            userInput = baseText + " "
            isFieldFocused = true // Keep focus for additional input
        } else {
            // For complete suggestions, set the final text and finalize
            userInput = baseText
            finalizeLocation()
        }

        // Clear validation errors on selection
        validationErrors.removeValue(forKey: "input")
    }

    private func recordSelection(_ suggestion: LocationSuggestionEngine.LocationSuggestion) {
        engine.recordUsage(zone: zonePrefix, suggestion: suggestion.text)
        loadRecentLocations() // Refresh recent list
    }

    /// Sync location binding changes to userInput for proper initialization
    private func syncLocationBindingToUserInput(_ newLocation: String) {
        let trimmedLocation = newLocation.trimmingCharacters(in: .whitespaces)

        // Only update userInput if location binding has actual content
        if !trimmedLocation.isEmpty {
            // Handle zone prefix logic correctly for binding updates
            if trimmedLocation.hasPrefix("\(zonePrefix) ") {
                // Location has prefix, extract user part
                let inputPart = String(trimmedLocation.dropFirst(zonePrefix.count + 1))
                userInput = inputPart.trimmingCharacters(in: .whitespaces)
            } else if trimmedLocation != userInput {
                // Location doesn't have prefix or is different, use as-is
                userInput = trimmedLocation
            }
            // Note: Only update userInput if different to avoid triggering onChange loops
        } else if !userInput.isEmpty {
            // Location binding is now empty but userInput has content - clear it
            userInput = ""
        }

        // Update formData for consistency
        formData.location = trimmedLocation
    }

    // MARK: - Validation

    private func validateInput() {
        let inputToValidate = userInput.trimmingCharacters(in: .whitespaces)

        // Clear previous errors
        validationErrors.removeValue(forKey: "input")

        // Check length
        if inputToValidate.isEmpty {
            // Empty is OK unless we're in finalization
            return
        }

        if inputToValidate.count < 2 {
            validationErrors["input"] = "Location too short"
            return
        }

        if inputToValidate.count > 100 {
            validationErrors["input"] = "Location too long"
            return
        }

        // Basic pattern validation
        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet.punctuationCharacters)
            .union(CharacterSet.whitespaces)

        let invalidChars = inputToValidate.unicodeScalars.filter { !allowedCharacters.contains($0) }

        if !invalidChars.isEmpty {
            validationErrors["input"] = "Contains invalid characters"
            return
        }

        // Custom zone-specific validation
        if let zoneError = validateZoneSpecificInput(inputToValidate) {
            validationErrors["input"] = zoneError
            return
        }

        lastValidationTime = Date()
    }

    private func validateZoneSpecificInput(_ input: String) -> String? {
        // Add zone-specific validation rules as needed
        switch zonePrefix {
        case "A DECK":
            // Check for seat format consistency
            let seatPattern = #"(\d+[A-Z]{1,2})"#
            let hasSeats = try? NSRegularExpression(pattern: seatPattern, options: [])
                .matches(in: input.uppercased(), options: [], range: NSRange(location: 0, length: input.count))
                .isEmpty == false

            if input.uppercased().contains("SEAT") && !(hasSeats ?? false) {
                return "Seat locations should include seat number (e.g., 12A)"
            }

        case "FLIGHT DECK":
            // Check for instrument naming consistency
            let validInstrumentParts = ["DISPLAY", "PANEL", "WINDOW", "CDU", "BUTTON", "SWITCH", "LIGHT"]
            let inputUpper = input.uppercased()
            let hasValidPart = validInstrumentParts.contains { inputUpper.contains($0) }

            if !hasValidPart && inputUpper.count > 3 {
                return "Use standard flight deck terminology (DISPLAY, PANEL, WINDOW, etc.)"
            }

        default:
            break
        }

        return nil
    }

    // MARK: - Quick Actions

    private func clearField() {
        userInput = ""
        validationErrors.removeAll()
        updateLocation()
        isFieldFocused = true // Keep focus for new input
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        if let pasteboardString = UIPasteboard.general.string {
            userInput = pasteboardString
            updateLocation()
        }
        #endif
        // macOS version would need appropriate pasteboard API

        isFieldFocused = true
    }

    private func selectRecentLocation(_ location: String) {
        userInput = location
        finalizeLocation()

        // Move to top of recent list
        var updatedRecent = recentLocations
        updatedRecent.removeAll { $0 == location }
        updatedRecent.insert(location, at: 0)
        recentLocations = updatedRecent
    }

    // MARK: - Computed Properties

    private var hasValidationError: Bool {
        return !validationErrors.isEmpty
    }

    private var isFieldValid: Bool {
        return !hasValidationError && !userInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canShowQuickActions: Bool {
        return isFieldFocused
    }
}

// MARK: - Supporting Structures

struct LocationFormData {
    var location: String = ""
}

struct RecentlyUsedChip: View {
    let location: String
    let onSelected: () -> Void

    @State private var isSelected = false

    var body: some View {
        Button(action: {
            onSelected()
            withAnimation(.easeInOut(duration: 0.2)) {
                isSelected = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelected = false
                }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                Text(location)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(.secondary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// NOTE: View components removed to avoid Swift 6 redeclaration error
// They are now defined in LocationSuggestionPill.swift as canonical versions

// MARK: - Preview

struct SmartLocationField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SmartLocationField(
                location: .constant("A DECK SEAT 12A"),
                zonePrefix: "A DECK"
            )

            SmartLocationField(
                location: .constant(""),
                zonePrefix: "FLIGHT DECK"
            )

            SmartLocationField(
                location: .constant("MLG TIRE 1"),
                zonePrefix: "MLG"
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
