// LocationSuggestionPill.swift
// Intelligent Location Entry System - Phase 3.2 Subtask 2.3
// Enhanced pill component with haptics, animations, and accessibility

import SwiftUI
import UIKit

struct LocationSuggestionPill: View {
    let suggestion: LocationSuggestionEngine.LocationSuggestion
    @Binding var userLocationInput: String
    let zonePrefix: String?
    @FocusState var isTextFieldFocused: Bool
    let onSuggestionSelected: ((LocationSuggestionEngine.LocationSuggestion) -> Void)?

    // Animation states
    @State private var isPressed = false
    @State private var isHighlighted = false
    @State private var showQuickValues = false

    // Configuration
    var pillColor: Color = .blue.opacity(0.8)
    var textColor: Color = .white
    var validationError: Bool = false
    var showHapticFeedback: Bool = true
    var animationEnabled: Bool = true

    var body: some View {
        VStack(spacing: 4) {
            // Main pill
            mainPill

            // Quick values for applicable suggestions
            if showQuickValues && suggestion.isSelectionType {
                QuickValuePicker(
                    suggestion: suggestion,
                    userLocationInput: $userLocationInput,
                    zonePrefix: zonePrefix,
                    isTextFieldFocused: _isTextFieldFocused,
                    onSuggestionSelected: onSuggestionSelected
                )
                .transition(.opacity.combined(with: .slide))
            }
        }
        .animation(animationEnabled ? .easeInOut(duration: 0.2) : nil, value: isHighlighted)
        .animation(animationEnabled ? .easeInOut(duration: 0.3) : nil, value: showQuickValues)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAction(named: Text("Select")) {
            handleSuggestionTap()
        }
    }

    private var mainPill: some View {
        Button(action: handleSuggestionTap) {
            HStack(spacing: 6) {
                // Type indicator icon
                typeIndicatorIcon
                    .font(.caption2)

                Text(suggestion.text)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)

                // Additional input indicator
                if suggestion.needsAdditionalInput {
                    additionalInputIndicator
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                pillBackground
            )
            .foregroundColor(textColor)
            .clipShape(Capsule())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .brightness(validationError ? 0.2 : 0)
        }
        .buttonStyle(PillButtonStyle(
            isPressed: $isPressed,
            isHighlighted: $isHighlighted,
            showHapticFeedback: showHapticFeedback
        ))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0)
                .onEnded { _ in
                    withAnimation {
                        showQuickValues.toggle()
                    }
                }
        )
    }

    // MARK: - Visual Components

    @ViewBuilder
    private var typeIndicatorIcon: some View {
        switch suggestion.type {
        case .requiresNumber:
            Image(systemName: "number.circle.fill")
        case .requiresDesignator:
            Image(systemName: "123.rectangle.fill")
        case .requiresSelection:
            Image(systemName: "arrow.up.arrow.down.circle.fill")
        case .complete:
            Image(systemName: "checkmark.circle.fill")
        }
    }

    @ViewBuilder
    private var additionalInputIndicator: some View {
        switch suggestion.type {
        case .requiresNumber:
            Image(systemName: "plus.circle.fill")
                .font(.caption2)
        case .requiresDesignator:
            Text("A-Z")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
        case .requiresSelection:
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.caption2)
        case .complete:
            EmptyView()
        }
    }

    private var pillBackground: some View {
        Capsule()
            .fill(pillColor)
            .overlay(
                Capsule()
                    .strokeBorder(
                        Color.white.opacity(isHighlighted ? 0.8 : 0.3),
                        lineWidth: validationError ? 2 : 1
                    )
            )
            .shadow(
                color: pillColor.opacity(0.3),
                radius: isPressed ? 2 : 4,
                x: 0,
                y: isPressed ? 1 : 2
            )
    }

    // MARK: - Behavior

    private func handleSuggestionTap() {
        if showHapticFeedback {
            provideHapticFeedback(for: suggestion)
        }

        switch suggestion.type {
        case .requiresNumber, .requiresDesignator:
            appendSuggestionWithSpace()

        case .requiresSelection:
            showQuickValues.toggle()

        case .complete:
            setCompleteSuggestion()
        }

        // Highlight briefly
        withAnimation(.easeInOut(duration: 0.2)) {
            isHighlighted = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isHighlighted = false
            }
        }

        onSuggestionSelected?(suggestion)
    }

    private func appendSuggestionWithSpace() {
        let prefix = zonePrefix.map { "\($0) " } ?? ""
        let currentText = userLocationInput.isEmpty ? prefix : userLocationInput
        userLocationInput = currentText + (suggestion.text + " ")
        isTextFieldFocused = true
    }

    private func setCompleteSuggestion() {
        let prefix = zonePrefix.map { "\($0) " } ?? ""
        userLocationInput = prefix + suggestion.text
        isTextFieldFocused = false
    }

    // MARK: - Haptic Feedback

    private func provideHapticFeedback(for suggestion: LocationSuggestionEngine.LocationSuggestion) {
        switch suggestion.type {
        case .complete:
            successHaptic()
        case .requiresNumber, .requiresDesignator:
            lightHaptic()
        case .requiresSelection:
            mediumHaptic()
        }
    }

    private func lightHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func mediumHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func successHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var label = suggestion.text

        switch suggestion.type {
        case .requiresNumber:
            label += ", requires number"
        case .requiresDesignator:
            label += ", requires designator"
        case .requiresSelection:
            label += ", requires selection"
        case .complete:
            label += ", complete location"
        }

        if let helperText = suggestion.helperText {
            label += ", " + helperText
        }

        return label
    }

    private var accessibilityHint: String {
        switch suggestion.type {
        case .complete:
            return "Double tap to select complete location"
        case .requiresSelection:
            return "Double tap to show options, long press to toggle quick values"
        case .requiresNumber, .requiresDesignator:
            return "Double tap to append with space for additional input"
        }
    }
}

// MARK: - Pill Button Style

struct PillButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    @Binding var isHighlighted: Bool
    var showHapticFeedback: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
                if newValue && showHapticFeedback {
                    let generator = UIImpactFeedbackGenerator(style: .soft)
                    generator.impactOccurred()
                }
            }
    }
}

// MARK: - Quick Value Picker

struct QuickValuePicker: View {
    let suggestion: LocationSuggestionEngine.LocationSuggestion
    @Binding var userLocationInput: String
    let zonePrefix: String?
    @FocusState var isTextFieldFocused: Bool
    let onSuggestionSelected: ((LocationSuggestionEngine.LocationSuggestion) -> Void)?

    @State private var isExpanded = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(suggestion.commonValues ?? [], id: \.self) { value in
                    QuickValueChip(
                        value: value,
                        suggestion: suggestion,
                        userLocationInput: $userLocationInput,
                        zonePrefix: zonePrefix,
                        isTextFieldFocused: _isTextFieldFocused,
                        onSuggestionSelected: onSuggestionSelected
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.gray.opacity(0.1))
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - Quick Value Chip

struct QuickValueChip: View {
    let value: String
    let suggestion: LocationSuggestionEngine.LocationSuggestion
    @Binding var userLocationInput: String
    let zonePrefix: String?
    @FocusState var isTextFieldFocused: Bool
    let onSuggestionSelected: ((LocationSuggestionEngine.LocationSuggestion) -> Void)?

    @State private var isSelected = false

    var body: some View {
        Button(action: selectQuickValue) {
            Text(value)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.orange.opacity(0.8) : Color.orange.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.orange.opacity(isSelected ? 0.8 : 0.5), lineWidth: 1)
                        )
                )
                .foregroundColor(isSelected ? .white : .orange)
                .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }

    private func selectQuickValue() {
        let prefix = zonePrefix.map { "\($0) " } ?? ""
        userLocationInput = prefix + suggestion.text + " " + value
        isTextFieldFocused = false // Complete entry

        withAnimation(.easeInOut(duration: 0.2)) {
            isSelected = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSelected = false
            }
        }

        onSuggestionSelected?(suggestion)

        // Haptic feedback for selection
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - Supporting Views

struct ZonePrefixChip: View {
    let zone: String
    var color: Color = .blue
    var textColor: Color = .white

    @State private var animate = false

    var body: some View {
        Text(zone)
            .font(.system(.caption, design: .rounded))
            .fontWeight(.bold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(
                        color: color.opacity(0.3),
                        radius: animate ? 3 : 6,
                        x: 0,
                        y: animate ? 1 : 3
                    )
            )
            .foregroundColor(textColor)
            .scaleEffect(animate ? 1.02 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
    }
}

// MARK: - Preview

struct LocationSuggestionPill_Previews: PreviewProvider {
    static var previews: some View {
        let mockSuggestion = LocationSuggestionEngine.LocationSuggestion(
            text: "SEAT",
            type: .requiresDesignator,
            helperText: "Add seat number (e.g., 1A, 12B)",
            validationPattern: "^[0-9]{1,3}[A-Z]$",
            commonValues: ["1A", "2B", "34F"],
            category: "passenger"
        )

        return VStack(spacing: 20) {
            LocationSuggestionPill(
                suggestion: mockSuggestion,
                userLocationInput: .constant(""),
                zonePrefix: "A DECK",
                onSuggestionSelected: nil
            )

            ZonePrefixChip(zone: "A DECK")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
