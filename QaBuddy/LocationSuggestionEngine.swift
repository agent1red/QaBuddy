// LocationSuggestionEngine.swift
// Intelligent Location Entry System - Phase 3.2 Subtask 2.3
// Centralized engine for managing aviation location suggestions with learning capabilities

import Foundation

@MainActor
class LocationSuggestionEngine: ObservableObject {
    static let shared = LocationSuggestionEngine()

    // MARK: - Suggestion Types
    enum SuggestionType: String, Codable {
        case requiresNumber     // Needs numeric input (e.g., 1, 2, 3)
        case requiresDesignator // Needs letter/number combo (e.g., 1L, 2R, A1)
        case requiresSelection  // Needs choice from options (e.g., INBOARD/OUTBOARD)
        case complete          // Complete as-is (no additional input needed)
    }

    // MARK: - Suggestion Model
    struct LocationSuggestion: Identifiable, Codable, Sendable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        let helperText: String?
        let validationPattern: String?  // Regex for validation
        let commonValues: [String]?     // Quick-pick options
        let category: String?           // Aviation category (passenger, cargo, systems, etc.)

        // Computed properties for easy access
        var needsAdditionalInput: Bool {
            return type != .complete
        }

        var isSelectionType: Bool {
            return type == .requiresSelection
        }

        func validateInput(_ input: String, for remainder: String) -> Bool {
            guard let pattern = validationPattern else { return true }

            let remainderTrimmed = remainder.trimmingCharacters(in: .whitespaces)
            let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
            return predicate.evaluate(with: remainderTrimmed)
        }
    }

    // MARK: - Zone Suggestions Database (Complete for all 19 zones)
    private let zoneSuggestions: [String: [LocationSuggestion]] = [

        // PASSENGER CABIN ZONES
        "A DECK": [
            LocationSuggestion(
                text: "SEAT",
                type: .requiresDesignator,
                helperText: "Add seat number (e.g., 1A, 12B, 34F)",
                validationPattern: "^[0-9]{1,3}[A-Z]$",
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "ROW",
                type: .requiresNumber,
                helperText: "Add row number (e.g., 1, 15, 32)",
                validationPattern: "^[0-9]{1,3}$",
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "GALLEY FWD",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "GALLEY MID",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "GALLEY AFT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "LAV",
                type: .requiresNumber,
                helperText: "Add lavatory number (e.g., 1, 2, 3)",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2", "3", "4"],
                category: "passenger"
            ),
            LocationSuggestion(
                text: "OVERHEAD BIN L",
                type: .requiresNumber,
                helperText: "Add bin number (e.g., 1, 2, 15)",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "OVERHEAD BIN R",
                type: .requiresNumber,
                helperText: "Add bin number (e.g., 1, 2, 15)",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "EMERGENCY EXIT L",
                type: .requiresNumber,
                helperText: "Add exit number (e.g., 1, 2)",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "passenger"
            ),
            LocationSuggestion(
                text: "EMERGENCY EXIT R",
                type: .requiresNumber,
                helperText: "Add exit number (e.g., 1, 2)",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "passenger"
            ),
            LocationSuggestion(
                text: "ATTENDANT SEAT",
                type: .requiresNumber,
                helperText: "Add seat number (e.g., 1, 2, 3)",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2", "3", "4"],
                category: "passenger"
            ),
            LocationSuggestion(
                text: "DOOR",
                type: .requiresDesignator,
                helperText: "Add door designation (e.g., 1L, 2R)",
                validationPattern: "^[0-9][LR]$",
                commonValues: ["1L", "1R", "2L", "2R"],
                category: "passenger"
            ),
            LocationSuggestion(
                text: "CLOSET FWD",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "CLOSET AFT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "COAT CLOSET",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "STORAGE BIN",
                type: .requiresNumber,
                helperText: "Add bin number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "passenger"
            ),
            LocationSuggestion(
                text: "SERVICE PANEL",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "passenger"
            )
        ],

        "B DECK": [
            LocationSuggestion(
                text: "CARGO DOOR",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "POSITION",
                type: .requiresDesignator,
                helperText: "Add position (e.g., 1, 2, A1, B2)",
                validationPattern: "^[A-Z]?[0-9]{1,2}$",
                commonValues: ["1", "2", "3", "A1", "A2", "B1", "B2"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "CONTAINER LOCK",
                type: .requiresNumber,
                helperText: "Add lock number (e.g., 1, 2, 3)",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: ["1", "2", "3", "4"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "PALLET POSITION",
                type: .requiresDesignator,
                helperText: "Add position (e.g., A, B, 1A, 2B)",
                validationPattern: "^[A-Z][0-9]?$|^[0-9][A-Z]$",
                commonValues: ["A", "B", "C", "1A", "2B"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "FLOOR TRACK",
                type: .requiresNumber,
                helperText: "Add track number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "WALL NET",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "CEILING NET",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "DIVIDER NET",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "SMOKE DETECTOR",
                type: .requiresNumber,
                helperText: "Add detector number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: ["1", "2", "3"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "FIRE SUPPRESSION NOZZLE",
                type: .requiresNumber,
                helperText: "Add nozzle number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "TEMP SENSOR",
                type: .requiresNumber,
                helperText: "Add sensor number",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "LIGHTING FIXTURE",
                type: .requiresNumber,
                helperText: "Add fixture number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "TIE DOWN POINT",
                type: .requiresDesignator,
                helperText: "Add point designation",
                validationPattern: "^[A-Z]?[0-9]{1,2}$",
                commonValues: ["1", "2", "A", "B"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "ROLLER TRACK",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "ACCESS PANEL",
                type: .requiresDesignator,
                helperText: "Add panel designation",
                validationPattern: "^[A-Z0-9]{1,3}$",
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "SIDEWALL LINER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "CEILING LINER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "BILGE AREA",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "DRAIN VALVE",
                type: .requiresNumber,
                helperText: "Add valve number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "cargo"
            )
        ],

        "FORWARD CARGO": [
            LocationSuggestion(
                text: "CARGO DOOR",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "POSITION",
                type: .requiresDesignator,
                helperText: "Add position (e.g., 1, 2, A1, B2)",
                validationPattern: "^[A-Z]?[0-9]{1,2}$",
                commonValues: ["1", "2", "3", "A1", "A2", "B1", "B2"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "CONTAINER LOCK",
                type: .requiresNumber,
                helperText: "Add lock number (e.g., 1, 2, 3)",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: ["1", "2", "3", "4"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "PALLET POSITION",
                type: .requiresDesignator,
                helperText: "Add position (e.g., A, B, 1A, 2B)",
                validationPattern: "^[A-Z][0-9]?$|^[0-9][A-Z]$",
                commonValues: ["A", "B", "C", "1A", "2B"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "FLOOR TRACK",
                type: .requiresNumber,
                helperText: "Add track number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "WALL NET",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "TIE DOWN POINT",
                type: .requiresDesignator,
                helperText: "Add point designation",
                validationPattern: "^[A-Z]?[0-9]{1,2}$",
                commonValues: ["1", "2", "A", "B"],
                category: "cargo"
            )
        ],

        "AFT CARGO": [
            LocationSuggestion(
                text: "CARGO DOOR",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cargo"
            ),
            LocationSuggestion(
                text: "POSITION",
                type: .requiresDesignator,
                helperText: "Add position (e.g., 1, 2, A1, B2)",
                validationPattern: "^[A-Z]?[0-9]{1,2}$",
                commonValues: ["1", "2", "3", "A1", "A2", "B1", "B2"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "CONTAINER LOCK",
                type: .requiresNumber,
                helperText: "Add lock number (e.g., 1, 2, 3)",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: ["1", "2", "3", "4"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "PALLET POSITION",
                type: .requiresDesignator,
                helperText: "Add position (e.g., A, B, 1A, 2B)",
                validationPattern: "^[A-Z][0-9]?$|^[0-9][A-Z]$",
                commonValues: ["A", "B", "C", "1A", "2B"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "TIE DOWN POINT",
                type: .requiresDesignator,
                helperText: "Add point designation",
                validationPattern: "^[A-Z]?[0-9]{1,2}$",
                commonValues: ["1", "2", "A", "B"],
                category: "cargo"
            )
        ],

        "BULK CARGO": [
            LocationSuggestion(
                text: "POSITION",
                type: .requiresDesignator,
                helperText: "Add position (e.g., 1, 2, A1, B2)",
                validationPattern: "^[A-Z]?[0-9]{1,2}$",
                commonValues: ["1", "2", "3", "A1", "A2", "B1", "B2"],
                category: "cargo"
            ),
            LocationSuggestion(
                text: "CONTAINER LOCK",
                type: .requiresNumber,
                helperText: "Add lock number (e.g., 1, 2, 3)",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: ["1", "2", "3", "4"],
                category: "cargo"
            )
        ],

        // WING SYSTEMS
        "LEFT WING": [
            LocationSuggestion(
                text: "LEADING EDGE",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "wing"
            ),
            LocationSuggestion(
                text: "TRAILING EDGE",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "wing"
            ),
            LocationSuggestion(
                text: "FLAP",
                type: .requiresSelection,
                helperText: "Add flap position (e.g., INBOARD, OUTBOARD)",
                validationPattern: "^(INBOARD|OUTBOARD)$",
                commonValues: ["INBOARD", "OUTBOARD"],
                category: "wing"
            ),
            LocationSuggestion(
                text: "SLAT",
                type: .requiresNumber,
                helperText: "Add slat number (e.g., 1, 2, 3, 4, 5)",
                validationPattern: "^[1-5]$",
                commonValues: ["1", "2", "3", "4", "5"],
                category: "wing"
            ),
            LocationSuggestion(
                text: "SPOILER",
                type: .requiresNumber,
                helperText: "Add spoiler number (e.g., 1, 2, 3, 4, 5)",
                validationPattern: "^[1-7]$",
                commonValues: ["1", "2", "3", "4", "5", "6", "7"],
                category: "wing"
            ),
            LocationSuggestion(
                text: "FUEL ACCESS PANEL",
                type: .requiresDesignator,
                helperText: "Add panel designation",
                validationPattern: "^[A-Z0-9]{1,3}$",
                commonValues: nil,
                category: "wing"
            ),
            LocationSuggestion(
                text: "STATIC WICK",
                type: .requiresNumber,
                helperText: "Add wick number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "wing"
            ),
            LocationSuggestion(
                text: "VORTEX GENERATOR",
                type: .requiresDesignator,
                helperText: "Add row/position",
                validationPattern: "^[A-Z0-9]{1,3}$",
                commonValues: nil,
                category: "wing"
            )
        ],

        "RIGHT WING": [
            LocationSuggestion(
                text: "LEADING EDGE",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "wing"
            ),
            LocationSuggestion(
                text: "TRAILING EDGE",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "wing"
            ),
            LocationSuggestion(
                text: "FLAP",
                type: .requiresSelection,
                helperText: "Add flap position (e.g., INBOARD, OUTBOARD)",
                validationPattern: "^(INBOARD|OUTBOARD)$",
                commonValues: ["INBOARD", "OUTBOARD"],
                category: "wing"
            ),
            LocationSuggestion(
                text: "SLAT",
                type: .requiresNumber,
                helperText: "Add slat number (e.g., 1, 2, 3, 4, 5)",
                validationPattern: "^[1-5]$",
                commonValues: ["1", "2", "3", "4", "5"],
                category: "wing"
            ),
            LocationSuggestion(
                text: "SPOILER",
                type: .requiresNumber,
                helperText: "Add spoiler number (e.g., 1, 2, 3, 4, 5)",
                validationPattern: "^[1-7]$",
                commonValues: ["1", "2", "3", "4", "5", "6", "7"],
                category: "wing"
            ),
            LocationSuggestion(
                text: "FUEL ACCESS PANEL",
                type: .requiresDesignator,
                helperText: "Add panel designation",
                validationPattern: "^[A-Z0-9]{1,3}$",
                commonValues: nil,
                category: "wing"
            ),
            LocationSuggestion(
                text: "STATIC WICK",
                type: .requiresNumber,
                helperText: "Add wick number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "wing"
            ),
            LocationSuggestion(
                text: "VORTEX GENERATOR",
                type: .requiresDesignator,
                helperText: "Add row/position",
                validationPattern: "^[A-Z0-9]{1,3}$",
                commonValues: nil,
                category: "wing"
            )
        ],

        // FLIGHT DECK SYSTEMS
        "FLIGHT DECK": [
            LocationSuggestion(
                text: "FMS CDU",
                type: .requiresDesignator,
                helperText: "Add side (e.g., L, R, C)",
                validationPattern: "^[LRC]$",
                commonValues: ["L", "R", "C"],
                category: "cockpit"
            ),
            LocationSuggestion(
                text: "THRUST LEVER",
                type: .requiresNumber,
                helperText: "Add lever number (e.g., 1, 2, 3, 4)",
                validationPattern: "^[1-4]$",
                commonValues: ["1", "2", "3", "4"],
                category: "cockpit"
            ),
            LocationSuggestion(
                text: "CIRCUIT BREAKER",
                type: .requiresDesignator,
                helperText: "Add panel designation",
                validationPattern: "^[A-Z][0-9]{1,2}$",
                commonValues: nil,
                category: "cockpit"
            ),
            LocationSuggestion(
                text: "WINDOW",
                type: .requiresDesignator,
                helperText: "Add window number (e.g., 1, 2, L1, R2)",
                validationPattern: "^[LR]?[0-9]$",
                commonValues: ["1", "2", "3", "4", "L1", "L2", "R1", "R2"],
                category: "cockpit"
            ),
            LocationSuggestion(
                text: "INSTRUMENT PANEL",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cockpit"
            ),
            LocationSuggestion(
                text: "YOKE",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cockpit"
            ),
            LocationSuggestion(
                text: "RUDDER PEDALS",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "cockpit"
            )
        ],

        // LANDING GEAR SYSTEMS
        "MLG": [
            LocationSuggestion(
                text: "TIRE",
                type: .requiresNumber,
                helperText: "Add tire position (e.g., 1, 2, 3, 4)",
                validationPattern: "^[1-4]$",
                commonValues: ["1", "2", "3", "4"],
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "BRAKE ASSEMBLY",
                type: .requiresNumber,
                helperText: "Add brake number (e.g., 1, 2)",
                validationPattern: "^[1-4]$",
                commonValues: ["1", "2", "3", "4"],
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "HUB",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "ANTI-SKID SENSOR",
                type: .requiresNumber,
                helperText: "Add sensor number",
                validationPattern: "^[1-4]$",
                commonValues: ["1", "2", "3", "4"],
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "WHEEL SPEED SENSOR",
                type: .requiresNumber,
                helperText: "Add sensor number",
                validationPattern: "^[1-4]$",
                commonValues: ["1", "2", "3", "4"],
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "AXLE",
                type: .requiresNumber,
                helperText: "Add axle number if multiple",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "DOOR",
                type: .requiresSelection,
                helperText: "Add door position (e.g., INNER, OUTER)",
                validationPattern: "^(INNER|OUTER)$",
                commonValues: ["INNER", "OUTER"],
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "UPLINK",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "landing-gear"
            )
        ],

        "NLG": [
            LocationSuggestion(
                text: "STEERING ACTUATOR",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "SHIMMY DAMPER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "TOWING ATTACHMENT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "LANDING LIGHT",
                type: .requiresSelection,
                helperText: "Add position (e.g., L, R)",
                validationPattern: "^[LR]$",
                commonValues: ["L", "R"],
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "POSITION LIGHT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "landing-gear"
            ),
            LocationSuggestion(
                text: "AXLE",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "landing-gear"
            )
        ],

        // ENGINE SYSTEMS
        "LEFT ENGINE": [
            LocationSuggestion(
                text: "FAN BLADE",
                type: .requiresNumber,
                helperText: "Add blade number",
                validationPattern: "^[0-9]{1,3}$",
                commonValues: nil,
                category: "engine"
            ),
            LocationSuggestion(
                text: "THRUST REVERSER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "engine"
            ),
            LocationSuggestion(
                text: "IPC STAGE",
                type: .requiresNumber,
                helperText: "Add stage number (e.g., 1, 2)",
                validationPattern: "^[1-2]$",
                commonValues: ["1", "2"],
                category: "engine"
            ),
            LocationSuggestion(
                text: "COMPRESSOR STAGE",
                type: .requiresNumber,
                helperText: "Add stage number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "engine"
            ),
            LocationSuggestion(
                text: "FADEC UNIT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "engine"
            ),
            LocationSuggestion(
                text: "PYLON",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "engine"
            )
        ],

        "RIGHT ENGINE": [
            LocationSuggestion(
                text: "FAN BLADE",
                type: .requiresNumber,
                helperText: "Add blade number",
                validationPattern: "^[0-9]{1,3}$",
                commonValues: nil,
                category: "engine"
            ),
            LocationSuggestion(
                text: "THRUST REVERSER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "engine"
            ),
            LocationSuggestion(
                text: "IPC STAGE",
                type: .requiresNumber,
                helperText: "Add stage number (e.g., 1, 2)",
                validationPattern: "^[1-2]$",
                commonValues: ["1", "2"],
                category: "engine"
            ),
            LocationSuggestion(
                text: "COMPRESSOR STAGE",
                type: .requiresNumber,
                helperText: "Add stage number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "engine"
            ),
            LocationSuggestion(
                text: "FADEC UNIT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "engine"
            ),
            LocationSuggestion(
                text: "PYLON",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "engine"
            )
        ],

        // APU SYSTEM
        "APU": [
            LocationSuggestion(
                text: "EXHAUST OUTLET",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "apu"
            ),
            LocationSuggestion(
                text: "AIR INLET",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "apu"
            ),
            LocationSuggestion(
                text: "INLET DOOR",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "apu"
            ),
            LocationSuggestion(
                text: "OIL FILLER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "apu"
            ),
            LocationSuggestion(
                text: "FIRE BOTTLE",
                type: .requiresNumber,
                helperText: "Add bottle number if multiple",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "apu"
            ),
            LocationSuggestion(
                text: "CONTROL BOX",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "apu"
            ),
            LocationSuggestion(
                text: "GENERATOR",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "apu"
            )
        ],

        // ELECTRICAL SYSTEMS
        "FWD EE BAY": [
            LocationSuggestion(
                text: "RACK E",
                type: .requiresNumber,
                helperText: "Add rack number (e.g., 1, 2, 3, 4)",
                validationPattern: "^[1-6]$",
                commonValues: ["1", "2", "3", "4", "5", "6"],
                category: "electrical"
            ),
            LocationSuggestion(
                text: "BATTERY",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "electrical"
            ),
            LocationSuggestion(
                text: "POWER PANEL",
                type: .requiresDesignator,
                helperText: "Add panel designation (e.g., P100, P200)",
                validationPattern: "^P[0-9]{3}$",
                commonValues: ["P100", "P200"],
                category: "electrical"
            ),
            LocationSuggestion(
                text: "TRANSFORMER",
                type: .requiresDesignator,
                helperText: "Add transformer designation (e.g., T1, T2)",
                validationPattern: "^T[0-9]$",
                commonValues: ["T1", "T2", "T3"],
                category: "electrical"
            ),
            LocationSuggestion(
                text: "INVERTER",
                type: .requiresNumber,
                helperText: "Add inverter number",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "electrical"
            ),
            LocationSuggestion(
                text: "CIRCUIT BREAKER",
                type: .requiresDesignator,
                helperText: "Add panel designation",
                validationPattern: "^[A-Z][0-9]{1,2}$",
                commonValues: nil,
                category: "electrical"
            )
        ],

        "AFT EE BAY": [
            LocationSuggestion(
                text: "RACK E",
                type: .requiresNumber,
                helperText: "Add rack number (e.g., 1, 2, 3, 4)",
                validationPattern: "^[1-6]$",
                commonValues: ["1", "2", "3", "4", "5", "6"],
                category: "electrical"
            ),
            LocationSuggestion(
                text: "BATTERY",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "electrical"
            ),
            LocationSuggestion(
                text: "POWER PANEL",
                type: .requiresDesignator,
                helperText: "Add panel designation (e.g., P100, P200)",
                validationPattern: "^P[0-9]{3}$",
                commonValues: ["P100", "P200"],
                category: "electrical"
            )
        ],

        "E/E BAY": [
            LocationSuggestion(
                text: "RACK E",
                type: .requiresNumber,
                helperText: "Add rack number (e.g., 1, 2, 3, 4)",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2", "3", "4", "5", "6", "7"],
                category: "electrical"
            ),
            LocationSuggestion(
                text: "CIRCUIT BREAKER",
                type: .requiresDesignator,
                helperText: "Add panel designation",
                validationPattern: "^[A-Z][0-9]{1,2}$",
                commonValues: nil,
                category: "electrical"
            )
        ],

        // AIR CONDITIONING SYSTEMS
        "LEFT AC BAY": [
            LocationSuggestion(
                text: "PACK",
                type: .requiresNumber,
                helperText: "Add pack number (e.g., 1, 2, 3)",
                validationPattern: "^[1-3]$",
                commonValues: ["1", "2", "3"],
                category: "air-conditioning"
            ),
            LocationSuggestion(
                text: "HEAT EXCHANGER",
                type: .requiresSelection,
                helperText: "Add type (e.g., PRIMARY, SECONDARY)",
                validationPattern: "^(PRIMARY|SECONDARY)$",
                commonValues: ["PRIMARY", "SECONDARY"],
                category: "air-conditioning"
            ),
            LocationSuggestion(
                text: "COMPRESSOR",
                type: .requiresNumber,
                helperText: "Add compressor number",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "air-conditioning"
            ),
            LocationSuggestion(
                text: "TEMPERATURE SENSOR",
                type: .requiresNumber,
                helperText: "Add sensor number",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2", "3"],
                category: "air-conditioning"
            )
        ],

        "RIGHT AC BAY": [
            LocationSuggestion(
                text: "PACK",
                type: .requiresNumber,
                helperText: "Add pack number (e.g., 1, 2, 3)",
                validationPattern: "^[1-3]$",
                commonValues: ["1", "2", "3"],
                category: "air-conditioning"
            ),
            LocationSuggestion(
                text: "HEAT EXCHANGER",
                type: .requiresSelection,
                helperText: "Add type (e.g., PRIMARY, SECONDARY)",
                validationPattern: "^(PRIMARY|SECONDARY)$",
                commonValues: ["PRIMARY", "SECONDARY"],
                category: "air-conditioning"
            ),
            LocationSuggestion(
                text: "COMPRESSOR",
                type: .requiresNumber,
                helperText: "Add compressor number",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "air-conditioning"
            )
        ],

        // EXTERIOR SYSTEMS
        "CROWN": [
            LocationSuggestion(
                text: "ANTENNA",
                type: .requiresSelection,
                helperText: "Add antenna type (e.g., GPS, VHF1, VHF2, HF, SATCOM)",
                validationPattern: "^ VHF[12]|GPS|HF|SATCOM|DME|VOR|ILS$",
                commonValues: ["GPS", "VHF1", "VHF2", "HF", "SATCOM"],
                category: "exterior"
            ),
            LocationSuggestion(
                text: "BEACON LIGHT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "exterior"
            ),
            LocationSuggestion(
                text: "STROBE LIGHT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "exterior"
            ),
            LocationSuggestion(
                text: "PRESSURE RELIEF",
                type: .requiresNumber,
                helperText: "Add valve number",
                validationPattern: "^[0-9]$",
                commonValues: ["1", "2"],
                category: "exterior"
            ),
            LocationSuggestion(
                text: "VENT",
                type: .requiresDesignator,
                helperText: "Add vent designation",
                validationPattern: "^[A-Z0-9]{1,3}$",
                commonValues: nil,
                category: "exterior"
            )
        ],

        "BELLY": [
            LocationSuggestion(
                text: "ANTENNA",
                type: .requiresSelection,
                helperText: "Add antenna type (e.g., VOR, ILS, TCAS, DME)",
                validationPattern: "^ VOR|ILS|TCAS|DME|TCAS|GPS|ADF$",
                commonValues: ["VOR", "ILS", "TCAS", "DME", "GPS", "ADF"],
                category: "exterior"
            ),
            LocationSuggestion(
                text: "PITOT TUBE",
                type: .requiresSelection,
                helperText: "Add position (e.g., CAPT, FO, STBY)",
                validationPattern: "^(CAPT|FO|STBY)$",
                commonValues: ["CAPT", "FO", "STBY"],
                category: "exterior"
            ),
            LocationSuggestion(
                text: "AOA VANE",
                type: .requiresDesignator,
                helperText: "Add vane designation (e.g., 1, 2, L, R)",
                validationPattern: "^[LR12]$",
                commonValues: ["1", "2", "L", "R"],
                category: "exterior"
            ),
            LocationSuggestion(
                text: "STATIC PORT",
                type: .requiresDesignator,
                helperText: "Add port designation (e.g., L, R, 1, 2)",
                validationPattern: "^[LR12]$",
                commonValues: ["L", "R", "1", "2"],
                category: "exterior"
            ),
            LocationSuggestion(
                text: "GROUND POWER RECEPTACLE",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "exterior"
            ),
            LocationSuggestion(
                text: "FUEL DRAIN",
                type: .requiresDesignator,
                helperText: "Add tank designation",
                validationPattern: "^[A-Z0-9]{1,3}$",
                commonValues: nil,
                category: "exterior"
            )
        ],

        // TAIL SYSTEMS
        "TAIL": [
            LocationSuggestion(
                text: "VERTICAL STABILIZER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "tail"
            ),
            LocationSuggestion(
                text: "RUDDER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "tail"
            ),
            LocationSuggestion(
                text: "HORIZONTAL STABILIZER",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "tail"
            ),
            LocationSuggestion(
                text: "ELEVATOR",
                type: .requiresSelection,
                helperText: "Add side (e.g., LEFT, RIGHT)",
                validationPattern: "^(LEFT|RIGHT)$",
                commonValues: ["LEFT", "RIGHT"],
                category: "tail"
            ),
            LocationSuggestion(
                text: "TRIM ACTUATOR",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "tail"
            ),
            LocationSuggestion(
                text: "FEEL UNIT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "tail"
            ),
            LocationSuggestion(
                text: "BEACON LIGHT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "tail"
            ),
            LocationSuggestion(
                text: "NAV LIGHT",
                type: .complete,
                helperText: nil,
                validationPattern: nil,
                commonValues: nil,
                category: "tail"
            ),
            LocationSuggestion(
                text: "STATIC WICK",
                type: .requiresNumber,
                helperText: "Add wick number",
                validationPattern: "^[0-9]{1,2}$",
                commonValues: nil,
                category: "tail"
            )
        ]

    ]

    // MARK: - Learning System
    @Published private(set) var frequentlyUsed: [String: [String]] = [:]
    @Published private(set) var usageStats: [String: Int] = [:]

    // MARK: - Public Methods

    /// Get all suggestions for a specific zone
    func getSuggestions(for zone: String) -> [LocationSuggestion] {
        return zoneSuggestions[zone.uppercased()] ?? []
    }

    /// Get helper text for the current input word
    func getHelperText(for input: String, in zone: String) -> String? {
        let lastWord = input.split(separator: " ").last?.uppercased() ?? ""

        if let suggestions = zoneSuggestions[zone.uppercased()] {
            if let match = suggestions.first(where: { $0.text == lastWord }) {
                return match.helperText
            }
        }

        return nil
    }

    /// Validate input against suggestion pattern for a specific word in input
    func validateInput(for suggestion: LocationSuggestion, in input: String) -> Bool {
        let lastWord = input.split(separator: " ").last?.trimmingCharacters(in: .whitespaces) ?? ""

        // Find remainder after the suggestion word
        let inputUpper = input.uppercased()
        let suggestionUpper = suggestion.text.uppercased()

        if inputUpper.hasSuffix(suggestionUpper) {
            return true // Just the suggestion word
        }

        if inputUpper.contains(suggestionUpper + " ") {
            // There's text after the suggestion, validate the remainder
            let components = input.uppercased().split(separator: " ")
            if let suggestionIndex = components.firstIndex(where: { $0 == suggestionUpper }),
               suggestionIndex < components.count - 1 {
                let remainder = components[suggestionIndex + 1..<components.count].joined(separator: " ")
                return suggestion.validateInput(input, for: remainder)
            }
        }

        return suggestion.type == .complete
    }

    /// Record usage of suggestion for learning
    func recordUsage(zone: String, suggestion: String) {
        var zoneHistory = frequentlyUsed[zone, default: []]

        // Remove if already exists to move to front
        zoneHistory.removeAll { $0 == suggestion }
        zoneHistory.insert(suggestion, at: 0)

        // Keep only most recent 10
        if zoneHistory.count > 10 {
            zoneHistory = Array(zoneHistory.prefix(10))
        }

        frequentlyUsed[zone] = zoneHistory

        // Update usage stats
        usageStats[suggestion] = (usageStats[suggestion] ?? 0) + 1
    }

    /// Get frequently used suggestions for a zone
    func getFrequentlyUsed(for zone: String, limit: Int = 5) -> [String] {
        return frequentlyUsed[zone, default: []].prefix(limit).map { $0 }
    }

    /// Get all available zone names for suggestions
    func getAvailableZones() -> [String] {
        return Array(zoneSuggestions.keys).sorted()
    }

    /// Check if zone has suggestions
    func hasSuggestions(for zone: String) -> Bool {
        return !(zoneSuggestions[zone.uppercased()]?.isEmpty ?? true)
    }

    /// Get suggestion category statistics
    func getCategoryStats(for zone: String) -> [String: Int] {
        guard let suggestions = zoneSuggestions[zone.uppercased()] else { return [:] }

        var stats: [String: Int] = [:]
        for suggestion in suggestions {
            if let category = suggestion.category {
                stats[category, default: 0] += 1
            }
        }

        return stats
    }
}
