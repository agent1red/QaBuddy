//
//  SequenceManager.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/28/25.
//

import Foundation

enum SequencingStrategy {
    case dailyReset       // Reset to 1 each day
    case sessionBased     // Reset per inspection session
    case global           // Never reset, continuous numbering
}

/// Manages photo sequence numbering for aviation inspection documentation.
/// Provides session-based sequencing with persistence across app launches.
class SequenceManager: @unchecked Sendable {

    // MARK: - Constants
    private let currentSequenceKey = "SequenceManager.currentSequence"
    private let activeSessionKey = "SequenceManager.activeSessionId"
    private let sessionsKey = "SequenceManager.sessions"
    private let sequenceStrategyKey = "SequenceManager.strategy"

    private let userDefaults = UserDefaults.standard

    // MARK: - Session Structure
    struct InspectionSession: Codable, Hashable {
        let id: String
        var name: String
        var createdDate: Date
        var lastUsedDate: Date
        var sequence: Int64
        var isActive: Bool

        init(name: String = "Default Session", id: String = UUID().uuidString) {
            self.id = id
            self.name = name
            self.createdDate = Date()
            self.lastUsedDate = Date()
            self.sequence = 1
            self.isActive = true
        }

        mutating func incrementSequence() {
            sequence += 1
            lastUsedDate = Date()
        }

        mutating func resetSequence() {
            sequence = 1
            lastUsedDate = Date()
        }

        mutating func setSequence(_ newSequence: Int64) {
            precondition(newSequence >= 1, "Sequence must be positive")
            sequence = newSequence
            lastUsedDate = Date()
        }
    }

    // MARK: - Properties
    private var activeSession: InspectionSession
    private var allSessions: [String: InspectionSession] = [:]

    // MARK: - Initialization
    init() {
        // Load active session or create default
        if let activeSessionId = userDefaults.string(forKey: activeSessionKey),
           let sessionsData = userDefaults.data(forKey: sessionsKey),
           let decodedSessions = try? JSONDecoder().decode([String: InspectionSession].self, from: sessionsData),
           let session = decodedSessions[activeSessionId] {

            activeSession = session
            activeSession.isActive = true
            allSessions = decodedSessions
        } else {
            // Create new default session
            activeSession = InspectionSession()
            allSessions = [activeSession.id: activeSession]
            saveSessions()
        }
    }

    // MARK: - Public Interface

    /// Get the current sequence number for the active session
    var currentSequence: Int64 {
        activeSession.sequence
    }

    /// Get the active session ID
    var activeSessionId: String {
        activeSession.id
    }

    /// Get the active session name
    var activeSessionName: String {
        get { activeSession.name }
        set {
            activeSession.name = newValue
            allSessions[activeSession.id] = activeSession
            saveSessions()
        }
    }

    /// Increment the sequence number and return the new value
    @discardableResult
    func incrementSequence() -> Int64 {
        activeSession.incrementSequence()
        allSessions[activeSession.id] = activeSession
        saveSessions()

        print("📷 Sequence incremented to #\(activeSession.sequence) in session '\(activeSession.name)'")
        return activeSession.sequence
    }

    /// Get the next sequence number without incrementing (for preview)
    var nextSequence: Int64 {
        activeSession.sequence
    }

    /// Manually set the sequence number
    func setSequence(_ sequence: Int64) {
        activeSession.setSequence(sequence)
        allSessions[activeSession.id] = activeSession
        saveSessions()

        print("🔢 Sequence manually set to #\(sequence) in session '\(activeSession.name)'")
    }

    /// Reset sequence to 1 for the active session
    func resetSequence() {
        activeSession.resetSequence()
        allSessions[activeSession.id] = activeSession
        saveSessions()

        print("🔄 Sequence reset to #1 in session '\(activeSession.name)'")
    }

    /// Create a new inspection session and switch to it
    func createNewSession(name: String = "New Inspection") -> String {
        // Mark current session as inactive
        activeSession.isActive = false
        allSessions[activeSession.id] = activeSession

        // Create new active session
        let newSession = InspectionSession(name: name)
        activeSession = newSession
        allSessions[newSession.id] = newSession

        saveSessions()

        print("🆕 Created new session: \(newSession.name) (ID: \(newSession.id))")
        return newSession.id
    }

    /// Switch to an existing session
    func switchToSession(_ sessionId: String) -> Bool {
        guard let session = allSessions[sessionId] else {
            print("❌ Session not found: \(sessionId)")
            return false
        }

        // Mark current session as inactive
        activeSession.isActive = false
        allSessions[activeSession.id] = activeSession

        // Switch to target session
        var targetSession = session
        targetSession.isActive = true
        targetSession.lastUsedDate = Date()

        activeSession = targetSession
        allSessions[sessionId] = targetSession

        saveSessions()

        print("🔄 Switched to session: \(session.name)")
        return true
    }

    /// Get all sessions (for UI display)
    var sessions: [InspectionSession] {
        Array(allSessions.values).sorted { $0.lastUsedDate > $1.lastUsedDate }
    }

    /// Get statistics for the active session
    var sessionStats: (totalPhotos: Int64, sessionAge: TimeInterval) {
        (activeSession.sequence - 1, Date().timeIntervalSince(activeSession.createdDate))
    }

    // MARK: - Private Methods

    private func saveSessions() {
        do {
            let sessionData = try JSONEncoder().encode(allSessions)
            userDefaults.set(sessionData, forKey: sessionsKey)
            userDefaults.set(activeSession.id, forKey: activeSessionKey)
        } catch {
            print("❌ Error saving sessions: \(error)")
        }
    }

    /// Clean up old inactive sessions (keep last 10)
    func cleanupOldSessions(maxSessions: Int = 10) {
        let sortedSessions = allSessions.values.sorted { $0.lastUsedDate > $1.lastUsedDate }
        guard sortedSessions.count > maxSessions else { return }

        let sessionsToRemove = sortedSessions[maxSessions...]
        for session in sessionsToRemove {
            allSessions.removeValue(forKey: session.id)
        }

        saveSessions()
        print("🧹 Cleaned up \(sessionsToRemove.count) old sessions")
    }

    /// Collateral photo data for the current sequence (for integration with PhotoManager)
    func getPhotoMetadata(forSequence sequence: Int64? = nil) -> (sequence: Int64, sessionId: String, sessionName: String) {
        let seq = sequence ?? currentSequence
        return (seq, activeSession.id, activeSession.name)
    }
}

extension SequenceManager.InspectionSession: @unchecked Sendable {}
