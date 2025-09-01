//
//  CoordinateSystemManager.swift
//  QaBuddy
//
//  Manages coordinate system switching between Velocity (X:Y:Z) and CMES (STA:WL:BL)
//  Phase 3.1 - Subtask 2.2: Implement Coordinate System Manager
//

import Foundation
import SwiftUI

// MARK: - Coordinate System Protocols and Types

/// Coordinate system protocol supporting both Velocity and CMES systems
protocol CoordinateSystem: Sendable {
    var systemName: String { get }
    var xLabel: String { get } // "X" or "STA"
    var yLabel: String { get } // "Y" or "WL"
    var zLabel: String { get } // "Z" or "BL"
}

/// Velocity coordinate system (X:Y:Z)
struct VelocitySystem: CoordinateSystem {
    let systemName = "Velocity"
    let xLabel = "X"
    let yLabel = "Y"
    let zLabel = "Z"
}

/// CMES coordinate system (STA:WL:BL)
struct CMESSystem: CoordinateSystem {
    let systemName = "CMES"
    let xLabel = "STA"
    let yLabel = "WL"
    let zLabel = "BL"
}

// MARK: - Coordinate System Manager

/// Manager for coordinate system switching and persistence
@MainActor
final class CoordinateSystemManager: ObservableObject {
    static let shared = CoordinateSystemManager()

    @Published var currentSystem: any CoordinateSystem = VelocitySystem()

    private let userDefaultsKey = "selectedCoordinateSystem"

    private init() {
        loadSavedSystem()
    }

    /// Switch to Velocity coordinate system (X:Y:Z)
    func switchToVelocity() {
        currentSystem = VelocitySystem()
        persistSelection("Velocity")
    }

    /// Switch to CMES coordinate system (STA:WL:BL)
    func switchToCMES() {
        currentSystem = CMESSystem()
        persistSelection("CMES")
    }

    /// Get current coordinate labels for UI display
    var currentLabels: (x: String, y: String, z: String) {
        (currentSystem.xLabel, currentSystem.yLabel, currentSystem.zLabel)
    }

    /// Format a location using current coordinate system
    func formatLocation(x: String?, y: String?, z: String?) -> String {
        "(\(currentSystem.xLabel): \(x ?? "UNK") \(currentSystem.yLabel): \(y ?? "UNK") \(currentSystem.zLabel): \(z ?? "UNK"))"
    }

    /// Check if current system is Velocity
    var isVelocitySystem: Bool {
        currentSystem.systemName == "Velocity"
    }

    /// Check if current system is CMES
    var isCMESSystem: Bool {
        currentSystem.systemName == "CMES"
    }

    private func loadSavedSystem() {
        let saved = UserDefaults.standard.string(forKey: userDefaultsKey) ?? "Velocity"
        currentSystem = saved == "CMES" ? CMESSystem() : VelocitySystem()
    }

    private func persistSelection(_ systemName: String) {
        UserDefaults.standard.set(systemName, forKey: userDefaultsKey)
    }
}
