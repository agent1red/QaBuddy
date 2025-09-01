//  SessionManager.swift
//  QA Buddy
//
//  Created by Kevin Hudson on 8/29/25.
//

import Foundation
import CoreData
import SwiftUI

/// Aviation inspection types for professional documentation
enum InspectionType: String, CaseIterable, Codable {
    // Aircraft Zones
    case aDeck = "A Deck"                    // Passenger deck (top)
    case bDeck = "B Deck"                    // Cargo deck (bottom)
    case leftWing = "Left Wing"
    case rightWing = "Right Wing"
    case empennage = "Empennage"             // Tail section
    case leftMLG = "Left MLG"                // Main Landing Gear
    case rightMLG = "Right MLG"
    case leftWheelWell = "Left Wheel Well"
    case rightWheelWell = "Right Wheel Well"
    case nlg = "NLG"                         // Nose Landing Gear
    case forwardCargo = "Forward Cargo"
    case aftCargo = "Aft Cargo"
    case fortyEightSection = "48 Section"    // Aft pressure bulkhead area
    case fwEEBay = "FW EE Bay"               // Forward Electronic Equipment
    case aftEEBay = "Aft EE Bay"             // Aft Electronic Equipment
    case leftACBay = "Left AC Bay"           // Air Conditioning
    case rightACBay = "Right AC Bay"
    case flightDeck = "Flight Deck"
    case leftEngine = "Left Engine"
    case rightEngine = "Right Engine"
    case apu = "APU"                         // Auxiliary Power Unit

    // Activity Types
    case preFlight = "Pre-Flight"
    case postFlight = "Post-Flight"
    case generalMaintenance = "General Maintenance"
    case aog = "AOG"                         // Aircraft On Ground
    case other = "Other"

    var displayName: String { self.rawValue }
}

/// Session status for tracking inspection progress
enum SessionStatus: String, Codable {
    case active = "Active"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var color: Color {
        switch self {
        case .active: return .green
        case .completed: return .blue
        case .cancelled: return .red
        }
    }
}

/// Aviation inspection session manager with Core Data integration
@MainActor
final class SessionManager: ObservableObject {
    /// Struct to safely extract Session data for session switching
    struct SessionData {
        let name: String?
        let aircraftTailNumber: String?
        let inspectionType: String?
        let inspectorName: String?
        let startTimestamp: Date?
        let totalPhotos: Int64

        init(from session: Session) {
            self.name = session.name
            self.aircraftTailNumber = session.aircraftTailNumber
            self.inspectionType = session.inspectionType
            self.inspectorName = session.inspectorName
            self.startTimestamp = session.startTimestamp ?? Date()
            self.totalPhotos = session.totalPhotos
        }
    }
    static let shared = SessionManager()

    private let context: NSManagedObjectContext
    private let persistenceController: PersistenceController

    // Published properties for SwiftUI
    @Published var activeSession: Session? {
        didSet {
            if let session = activeSession {
                UserDefaults.standard.set(session.id?.uuidString ?? "", forKey: "activeSessionId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeSessionId")
            }
        }
    }

    @Published var allSessions: [Session] = []

    private init() {
        self.persistenceController = PersistenceController.shared
        self.context = persistenceController.container.viewContext

        Task {
            await loadActiveSession()
        }
    }

    // MARK: - Core Data Operations

    /// Load active session from Core Data on app launch
    private func loadActiveSession() async {
        if let activeSessionIdString = UserDefaults.standard.string(forKey: "activeSessionId"),
           let sessionId = UUID(uuidString: activeSessionIdString) {

            let request = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)
            request.fetchLimit = 1

            do {
                let sessions = try context.fetch(request)
                if let session = sessions.first {
                    activeSession = session
                    print("✅ Loaded active session: \(session.name ?? "Unknown")")
                } else {
                    // Session no longer exists (was deleted) - clean up UserDefaults
                    print("⚠️ Saved active session no longer exists - clearing UserDefaults")
                    UserDefaults.standard.removeObject(forKey: "activeSessionId")
                    activeSession = nil
                }
            } catch {
                print("❌ Error loading active session: \(error)")
                // Clear potentially corrupted UserDefaults on error
                UserDefaults.standard.removeObject(forKey: "activeSessionId")
                activeSession = nil
            }
        }
    }

    /// Get all sessions from Core Data
    func fetchAllSessions() async -> [Session] {
        let request = Session.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startTimestamp", ascending: false)]

        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching sessions: \(error)")
            return []
        }
    }

    // MARK: - Session Management

    /// Create a new inspection session
    func createSession(
        name: String,
        aircraftTailNumber: String?,
        inspectionType: InspectionType,
        inspectorName: String
    ) async -> Session? {
        // Close active session if any
        if let activeSession = activeSession {
            updateSessionStatus(activeSession, to: .completed)
        }

        // Create new session
        let newSession = Session(context: context)
        newSession.id = UUID()
        newSession.name = name
        newSession.aircraftTailNumber = aircraftTailNumber
        newSession.inspectionType = inspectionType.rawValue
        newSession.inspectorName = inspectorName
        newSession.startTimestamp = Date()
        newSession.status = SessionStatus.active.rawValue
        newSession.totalPhotos = 0

        // Save to context
        do {
            try context.save()
            activeSession = newSession

            print("✅ Created new session: \(name) for aircraft: \(aircraftTailNumber ?? "N/A")")

            // Notify observers
            objectWillChange.send()
            return newSession

        } catch {
            print("❌ Error creating session: \(error)")
            context.rollback()
            return nil
        }
    }

    /// Update session status (Active→Completed→Cancelled)
    func updateSessionStatus(_ session: Session, to newStatus: SessionStatus) {
        if newStatus != .active {
            session.endTimestamp = Date()
        }
        session.status = newStatus.rawValue

        do {
            try context.save()
            print("✅ Session '\(session.name ?? "Unknown")' status updated to \(newStatus.rawValue)")
        } catch {
            print("❌ Error updating session status: \(error)")
            context.rollback()
        }
    }

    /// Switch to a different session
    func switchToSession(_ targetSession: Session) async -> Bool {
        print("🔄 Switching to session: \(targetSession.name ?? "Unknown") with \(targetSession.totalPhotos) photos")

        // Close current active session if any
        if let currentActiveSession = activeSession {
            updateSessionStatus(currentActiveSession, to: .completed)
            print("✅ Closed current session: \(currentActiveSession.name ?? "Unknown")")
        }

        // Reactivate the target session (don't create copy!)
        targetSession.status = SessionStatus.active.rawValue
        targetSession.endTimestamp = nil // Clear completion timestamp

        do {
            try context.save()

            // Set the EXISTING session as active (don't create new!)
            activeSession = targetSession
            objectWillChange.send()

            print("✅ Successfully switched to existing session: \(targetSession.name ?? "Unknown Session") (ID: \(targetSession.id?.uuidString ?? "N/A"))")

            // Verify photo count is preserved
            if let sessionId = targetSession.id?.uuidString {
                print("📊 Verifying \(targetSession.totalPhotos) photos still available for session \(sessionId)")
            }

            return true

        } catch {
            print("❌ Error switching session: \(error)")
            context.rollback()
            return false
        }
    }

    /// Resume the most recent active session
    func resumeMostRecentSession() async -> Bool {
        let request = Session.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", SessionStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "startTimestamp", ascending: false)]
        request.fetchLimit = 1

        do {
            let sessions = try context.fetch(request)
            if let session = sessions.first {
                activeSession = session
                objectWillChange.send()
                return true
            }
        } catch {
            print("❌ Error resuming session: \(error)")
        }
        return false
    }

    /// Increment photo count for active session
    func incrementPhotoCount() async {
        guard let session = activeSession else { return }
        session.totalPhotos += 1

        do {
            try context.save()
        } catch {
            print("❌ Error updating photo count: \(error)")
            context.rollback()
        }
    }

    /// Get photo count for a specific session
    func getPhotoCount(for session: Session) async -> Int64 {
        guard let sessionPhotos = session.photos else { return 0 }
        return Int64(sessionPhotos.count)
    }

    /// Calculate real-time photo count from Core Data relationships
    func calculateRealPhotoCount(for session: Session?) async -> Int64 {
        guard let sessionId = session?.id?.uuidString else {
            print("📊 calculateRealPhotoCount: No session or session ID")
            return 0
        }

        let request = Photo.fetchRequest()
        request.predicate = NSPredicate(format: "sessionID == %@", sessionId)
        request.resultType = .countResultType

        do {
            let count = try context.count(for: request)
            let finalCount = Int64(max(0, count))
            return finalCount
        } catch {
            print("❌ Error calculating photo count for session \(sessionId): \(error)")
            return 0
        }
    }

    /// Update session photo count in database (synchronization method)
    func syncSessionPhotoCount(_ session: Session) async -> Bool {
        let realCount = await calculateRealPhotoCount(for: session)

        if session.totalPhotos != realCount {
            session.totalPhotos = realCount

            do {
                try context.save()
                print("📊 Synced photo count for session \(session.name ?? "Unknown"): \(realCount)")
                return true
            } catch {
                print("❌ Error syncing photo count: \(error)")
                return false
            }
        }

        return true
    }

    /// Get comprehensive session statistics with real photo counts
    func getSessionStats() async -> (name: String?, aircraft: String?, type: InspectionType?, photos: Int64, age: TimeInterval) {
        guard let session = activeSession else { return (nil, nil, nil, 0, 0) }

        // Get real photo count and sync if needed
        _ = await syncSessionPhotoCount(session)
        let photos = session.totalPhotos

        let inspectionType: InspectionType? = {
            if let typeString = session.inspectionType {
                return InspectionType(rawValue: typeString)
            } else {
                return nil
            }
        }()

        let age = Date().timeIntervalSince(session.startTimestamp ?? Date())
        return (session.name, session.aircraftTailNumber, inspectionType, photos, age)
    }

    /// Get formatted session info for display with real data
    func getCurrentSessionInfo() async -> String {
        guard let session = activeSession else { return "No Active Session" }

        // Ensure photo count is synced
        _ = await syncSessionPhotoCount(session)

        let type = session.inspectionType.flatMap { InspectionType(rawValue: $0)?.rawValue } ?? "Unknown Type"
        let aircraft = session.aircraftTailNumber.map { " • \($0)" } ?? ""
        let photoCount = session.totalPhotos > 0 ? " (\(session.totalPhotos) photos)" : ""

        return "\(type)\(aircraft)\(photoCount)"
    }

    /// Sync all session photo counts (useful for UI refresh)
    func syncAllSessionCounts() async {
        let request = Session.fetchRequest()

        do {
            let sessions = try context.fetch(request)
            for session in sessions {
                _ = await syncSessionPhotoCount(session)
            }

            // Refresh published data
            allSessions = sessions.sorted { ($0.startTimestamp ?? Date()) > ($1.startTimestamp ?? Date()) }
            objectWillChange.send()

            print("📊 Synced photo counts for \(sessions.count) sessions")

        } catch {
            print("❌ Error syncing all session counts: \(error)")
        }
    }

    /// Legacy sessionStats property for backward compatibility (will be deprecated)
    @available(*, deprecated, renamed: "getSessionStats()", message: "Use getSessionStats() for accurate real-time data")
    var sessionStats: (name: String?, aircraft: String?, type: InspectionType?, photos: Int64, age: TimeInterval) {
        // This provides cached values for immediate UI display
        // Real values should use getSessionStats() async method
        guard let session = activeSession else { return (nil, nil, nil, 0, 0) }

        let inspectionType: InspectionType? = {
            if let typeString = session.inspectionType {
                return InspectionType(rawValue: typeString)
            } else {
                return nil
            }
        }()

        let age = Date().timeIntervalSince(session.startTimestamp ?? Date())
        return (session.name, session.aircraftTailNumber, inspectionType, session.totalPhotos, age)
    }

    /// Legacy currentSessionInfo property for backward compatibility
    @available(*, deprecated, renamed: "getCurrentSessionInfo()", message: "Use getCurrentSessionInfo() for accurate real-time data")
    var currentSessionInfo: String {
        guard let session = activeSession else { return "No Active Session" }

        let type = session.inspectionType.flatMap { InspectionType(rawValue: $0)?.rawValue } ?? "Unknown Type"
        let aircraft = session.aircraftTailNumber.map { " • \($0)" } ?? ""

        return "\(type)\(aircraft)"
    }

    // MARK: - Background Operations

    /// Auto-save for safety (call after photo capture)
    func autoSave() async {
        do {
            if context.hasChanges {
                try context.save()
                print("💾 Auto-saved session data")
            }
        } catch {
            print("❌ Auto-save error: \(error)")
        }
    }

    /// Enhanced auto-save with session recovery data
    func autoSaveWithRecovery() async {
        // Update session stats before saving
        if let activeSession = activeSession {
            // Force update of photo count
            let request = Photo.fetchRequest()
            request.predicate = NSPredicate(format: "sessionID == %@", activeSession.id?.uuidString ?? "")

            do {
                let photos = try context.fetch(request)
                activeSession.totalPhotos = Int64(photos.count)
            } catch {
                print("Error counting photos: \(error)")
            }
        }

        // Save with recovery checkpoint
        do {
            if context.hasChanges {
                try context.save()

                // Create recovery checkpoint
                if let sessionId = activeSession?.id?.uuidString {
                    let checkpointData = [
                        "sessionId": sessionId,
                        "photoCount": "\(activeSession?.totalPhotos ?? 0)",
                        "timestamp": Date().ISO8601Format()
                    ] as [String: Any]

                    let recoveryFile = getRecoveryCheckpointURL()
                    try JSONSerialization.data(withJSONObject: checkpointData).write(to: recoveryFile)
                }

                print("💾 Auto-saved session with recovery checkpoint")
            }
        } catch {
            print("❌ Auto-save with recovery failed: \(error)")
        }
    }

    /// Perform data integrity check and repair
    func performIntegrityCheck() async -> Bool {
        print("🔍 Performing data integrity check...")

        // Check for orphaned sessions
        let sessionRequest = Session.fetchRequest()
        do {
            let sessions = try context.fetch(sessionRequest)
            print("✅ Found \(sessions.count) sessions in database")

            for session in sessions {
                if let photos = session.photos, photos.count > 0 {
                    print("📸 Session '\(session.name ?? "Unknown")' has \(photos.count) photos")
                }
            }
            return true

        } catch {
            print("❌ Integrity check failed: \(error)")
            return false
        }
    }

    /// Clean up old completed sessions
    func cleanupOldSessions(keepDays: Int = 30) async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()

        let request = Session.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@ AND startTimestamp <%@",
                                     SessionStatus.completed.rawValue,
                                     cutoffDate as CVarArg)

        do {
            let oldSessions = try context.fetch(request)
            if !oldSessions.isEmpty {
                for session in oldSessions {
                    context.delete(session)
                }
                try context.save()
                print("🧹 Cleaned up \(oldSessions.count) old sessions")
            }
        } catch {
            print("❌ Error during cleanup: \(error)")
        }
    }

    // MARK: - Computed Properties

    /// All non-active sessions for history view
    var inactiveSessions: [Session] {
        allSessions.filter { $0 != activeSession }
    }

    /// Check if we have an active session available
    var hasActiveSession: Bool {
        activeSession != nil
    }

    /// Get the active session's UUID string for photo storage
    var activeSessionIdString: String? {
        activeSession?.id?.uuidString
    }

    // MARK: - Recovery Checkpoint Management

    private func getRecoveryCheckpointURL() -> URL {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentDirectory.appendingPathComponent("sessionRecoveryCheckpoint.json")
    }

    /// Load session from recovery checkpoint if available
    func loadFromRecoveryCheckpoint() async -> Bool {
        let recoveryURL = getRecoveryCheckpointURL()

        do {
            let data = try Data(contentsOf: recoveryURL)
            let checkpoint = try JSONSerialization.jsonObject(with: data) as! [String: String]

            if let sessionId = checkpoint["sessionId"],
               let sessionUUID = UUID(uuidString: sessionId) {

                let request = Session.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", sessionUUID as CVarArg)
                request.fetchLimit = 1

                let sessions = try context.fetch(request)
                if let session = sessions.first {
                    activeSession = session
                    objectWillChange.send()
                    print("✅ Recovered session from checkpoint")
                    return true
                }
            }
        } catch {
            print("❌ Recovery checkpoint failed: \(error)")
        }

        return false
    }

    /// Clear recovery checkpoint (call on successful app state)
    func clearRecoveryCheckpoint() {
        let recoveryURL = getRecoveryCheckpointURL()

        do {
            try FileManager.default.removeItem(at: recoveryURL)
            print("✅ Recovery checkpoint cleared")
        } catch {
            print("❌ Failed to clear recovery checkpoint: \(error)")
        }
    }
}

extension SessionManager {
    func preloadSessions() async {
        allSessions = await fetchAllSessions()
    }
}

// MARK: - Converting Legacy Sessions

extension SessionManager {
    /// Import existing SequenceManager sessions to Core Data
    func importLegacySessions(from sequenceManager: SequenceManager) async {
        for legacySession in sequenceManager.sessions where legacySession.id != activeSession?.id?.uuidString {
            // Check if session already exists
            let request = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", legacySession.id as CVarArg)

            do {
                let existing = try context.fetch(request)
                if existing.isEmpty {
                    // Create new session from legacy data
                    let newSession = Session(context: context)
                    newSession.id = UUID(uuidString: legacySession.id) ?? UUID()
                    newSession.name = legacySession.name
                    newSession.aircraftTailNumber = nil
                    newSession.startTimestamp = legacySession.createdDate
                    newSession.endTimestamp = nil as Date?
                    newSession.status = SessionStatus.completed.rawValue
                    newSession.totalPhotos = Int64(max(0, legacySession.sequence - 1))
                    newSession.inspectionType = InspectionType.other.rawValue
                    newSession.inspectorName = "Legacy Import"
                }
            } catch {
                print("Error importing legacy session: \(error)")
            }
        }

        // Save any new sessions
        do {
            if context.hasChanges {
                try context.save()
                print("✅ Imported legacy sessions")
            }
        } catch {
            print("❌ Error saving imported sessions: \(error)")
            context.rollback()
        }
    }
}
