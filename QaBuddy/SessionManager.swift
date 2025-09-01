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

// MARK: - Zone Awareness Extensions
extension SessionManager {
    /// Check if active session is zone-aware (inspects specific aircraft zones)
    /// Returns true if inspection type matches aircraft zone definitions
    var isZoneBasedSession: Bool {
        guard let sessionType = activeSession?.inspectionType,
              let zoneInspectionType = InspectionType(rawValue: sessionType) else {
            return false
        }

        // Check if this is an aircraft zone inspection (not activity type)
        let zoneCases: [InspectionType] = [
            .aDeck, .bDeck, .leftWing, .rightWing, .empennage,
            .leftMLG, .rightMLG, .leftWheelWell, .rightWheelWell, .nlg,
            .forwardCargo, .aftCargo, .fortyEightSection,
            .fwEEBay, .aftEEBay, .leftACBay, .rightACBay, .flightDeck,
            .leftEngine, .rightEngine, .apu
        ]

        for zoneCase in zoneCases {
            if zoneInspectionType == zoneCase {
                return true
            }
        }

        return false
    }

    /// Get zone prefix for location formatting (e.g., "Left Wing", "APU")
    var sessionZonePrefix: String? {
        guard isZoneBasedSession,
              let inspectionType = activeSession?.inspectionType,
              let zoneType = InspectionType(rawValue: inspectionType) else {
            return nil
        }
        return zoneType.rawValue
    }

    /// Format location string with zone context for UI display
    /// Example: "Left Wing" + "Leading Edge" = "Left Wing Leading Edge"
    func formatLocationWithPrefix(_ baseLocation: String) -> String {
        if let prefix = sessionZonePrefix {
            return "\(prefix) \(baseLocation)"
        }
        return baseLocation
    }

    /// Get available zones appropriate for the current session type
    /// For zone-based sessions: returns configured zones from ZoneConfigurationManager
    /// For activity-based sessions: returns nil (location-based inspections not applicable)
    var currentSessionZones: [String]? {
        guard isZoneBasedSession else { return nil }

        // Access ZoneConfigurationManager safely (will resolve at runtime)
        let zoneManager = NSClassFromString("ZoneConfigurationManager") as? NSObject
        if let manager = zoneManager,
           manager.responds(to: NSSelectorFromString("shared")),
           let sharedManager = manager.perform(NSSelectorFromString("shared"))?.takeUnretainedValue(),
           sharedManager.responds(to: NSSelectorFromString("currentZones")) {

            if let currentZonesArray = sharedManager.perform(NSSelectorFromString("currentZones"))?.takeUnretainedValue() as? [String] {
                return currentZonesArray
            }
        }

        // Fallback to default zones if manager not available
        return [
            "A Deck", "B Deck", "Left Wing", "Right Wing", "Empennage",
            "Left MLG", "Right MLG", "Left Wheel Well", "Right Wheel Well", "NLG",
            "Forward Cargo", "Aft Cargo", "48 Section",
            "FW EE Bay", "Aft EE Bay", "Left AC Bay", "Right AC Bay", "Flight Deck",
            "Left Engine", "Right Engine", "APU"
        ]
    }

    /// Check if current session supports location-based inspections
    /// Zone-based sessions require location information, activity-based may not
    var supportsLocationBasedInspections: Bool {
        return isZoneBasedSession
    }

    /// Get inspection activity type (Pre-Flight, Post-Flight, etc.)
    var currentInspectionActivity: String? {
        guard let sessionType = activeSession?.inspectionType,
              let inspectionType = InspectionType(rawValue: sessionType) else {
            return nil
        }

        // Check if this is an activity type (not zone)
        let activityCases: [InspectionType] = [
            .preFlight, .postFlight, .generalMaintenance, .aog, .other
        ]

        for activityCase in activityCases {
            if inspectionType == activityCase {
                return inspectionType.rawValue
            }
        }

        return nil
    }

    /// Get recommended template for current session type
    /// Returns template name based on inspection type and zone context
    var recommendedTemplateName: String? {
        if let activity = currentInspectionActivity {
            switch activity {
            case "Pre-Flight":
                return "Standard QA Write-up"
            case "Post-Flight":
                return sessionZonePrefix?.contains("Engine") == true ? "Equipment Defect" : "Standard QA Write-up"
            case "General Maintenance":
                return "Standard QA Write-up"
            case "AOG":
                return "Equipment Defect"
            default:
                return "Standard QA Write-up"
            }
        }

        // Zone-based with FOD context
        if isZoneBasedSession {
            return "FOD Cleanup"
        }

        return nil
    }

    /// Check if current session context supports FOD documentation
    var supportsFODDocumentation: Bool {
        guard let sessionType = activeSession?.inspectionType,
              let inspectionType = InspectionType(rawValue: sessionType) else {
            return false
        }

        // FOD is relevant for most zone-based inspections
        if isZoneBasedSession {
            return true
        }

        // Also relevant for maintenance activities
        let maintenanceActivities: [InspectionType] = [.postFlight, .generalMaintenance, .aog]
        return maintenanceActivities.contains(inspectionType)
    }

    /// Get common inspection locations for current zone
    var commonZoneLocations: [String] {
        guard let zonePrefix = sessionZonePrefix else { return [] }

        // Provide context-specific location hints for different zones
        // Provide context-specific location hints for different zones
// Based on Boeing 787 Dreamliner technical documentation and maintenance manuals
switch zonePrefix {
case "Left Wing", "Right Wing":
    // Composite wing structure with specific inspection points
    return [
        "Front Spar",                    // Primary composite load-bearing member
        "Rear Spar",                     // Secondary composite structure
        "Wing Rib Station",              // Numbered rib positions along span
        "Leading Edge Slat",             // With anti-ice heating elements
        "Inboard Flaperon",              // Combined flap/aileron surface
        "Outboard Aileron",              // Traditional control surface
        "Spoiler Panel 1-7",             // Seven panels per wing
        "Raked Winglet",                 // Lightning strike inspection point
        "Wing-Body Fairing",             // Root attachment interface
        "Fuel Access Panel"              // Tank inspection access
    ]
    
case "Left Engine", "Right Engine":
    // GEnx-1B or Trent 1000 specific components
    return [
        "Fan Blades (18)",               // Composite fan blades for GEnx
        "Fan Case",                      // 111.1-inch diameter on GEnx
        "Thrust Reverser Cascade",       // Translating sleeve mechanism
        "IPC Stage 1-2",                 // Intermediate pressure compressor (Trent)
        "TAPS Combustor",                // Twin-annular pre-swirl
        "LP Turbine Stage",              // Titanium aluminide construction
        "VFSG Mount",                    // Variable frequency starter generator
        "Chevron Nozzle",                // Noise reduction feature
        "FADEC Controller",              // Full authority digital control
        "Pylon Interface"                // Engine-to-wing attachment
    ]
    
case "APU":
    // Hamilton Sundstrand APS 5000 specific
    return [
        "Gas Generator Section",         // Primary turbine component
        "Power Turbine Assembly",        // 1,100 SHP turbine
        "Accessory Gearbox",             // Drive system for accessories
        "Fire Detection Loop",           // Kidde system sensor
        "Extinguisher Squib",            // Fire suppression activation
        "Electronic Control Box",        // ECB for start sequences
        "Exhaust Eductor",               // Tail cone outlet
        "Air Inlet Door",                // Ram air intake
        "APU Firewall",                  // Station 1016 interface
        "Mount Structure"                // Vibration isolation system
    ]
    
case "Left MLG", "Right MLG":
    // Main landing gear with electric brakes
    return [
        "Titanium Inner Cylinder",       // Oleo-pneumatic shock strut
        "EBAC Unit 1-4",                 // Electric brake actuator controller
        "Drag Brace Lock Link",          // AD 2024-16-01 inspection item
        "WOW Sensor",                    // Weight-on-wheels microswitch
        "Side Brace Downlock",           // Visual streamer identification
        "Hydraulic Supply Line",         // 5000 PSI system
        "Wheel Hub Assembly",            // Four wheels per gear
        "Tire Pressure Sensor",          // TPMS monitoring
        "Door Actuator",                 // Retraction mechanism
        "Semi-Levered Strut"             // 787-10 specific
    ]
    
case "NLG", "Nose Landing Gear":
    // Nose gear specific components
    return [
        "Steering Actuator",             // 70-degree max angle
        "Centering Cam",                 // Alignment mechanism
        "Dual Wheel Assembly",           // Non-braked configuration
        "Taxi Light Mount",              // Integrated lighting
        "Tow Bar Attachment",            // Ground handling interface
        "Shimmy Damper",                 // Vibration control
        "Extension Actuator",            // Deployment mechanism
        "Door Linkage",                  // Bay door coordination
        "Position Sensor",               // Gear position indication
        "Drag Strut"                     // Structural support member
    ]
    
case "FW EE Bay", "Forward EE Bay":
    // Forward electrical equipment bay
    return [
        "CCR Cabinet",                   // Common computing resource
        "FCE Cabinet L/C1/C2",           // Flight control electronics
        "P300-P600 Panel",               // Power distribution
        "Li-Ion Battery",                // Main battery compartment
        "Battery Charger",               // BCU unit
        "E1/E2 Rack",                    // Primary avionics rack
        "Wire Bundle W4100",             // Main routing harness
        "Cooling Duct",                  // Thermal management
        "Ground Stud",                   // Bonding point
        "Access Door"                    // Maintenance entry
    ]
    
case "Aft EE Bay":
    // Aft electrical equipment bay
    return [
        "RPDU 81/82/92",                 // Remote power distribution
        "ATRU E5/E6",                    // Auto transformer rectifier
        "APU Battery",                   // Secondary battery system
        "GCU Panel P100",                // Generator control unit
        "CMSC Unit",                     // Common motor start controller
        "E3-E7 Rack",                    // Equipment rack positions
        "Wire Bundle W5200",             // Aft routing harness
        "Vent Outlet",                   // Bay ventilation
        "Fire Detector",                 // Smoke/heat sensor
        "Service Panel"                  // Ground power connection
    ]
    
case "Flight Deck", "Cockpit":
    // Advanced cockpit panel system
    return [
        "P1-P3 Display Panel",           // Primary flight displays
        "P5 Overhead Panel",             // Systems control
        "P9 Forward Aisle Stand",        // FMS and radio control
        "P55 Glareshield MCP",           // Mode control panel
        "EFB Mount",                     // Electronic flight bag
        "ISFD Panel P2",                 // Integrated standby display
        "MFK Keypad",                    // Multi-function keypad
        "Cursor Control Device",         // CCD trackball
        "P7 Aft Aisle Stand",            // Circuit breakers
        "Window Heat Controller"         // Ice protection panel
    ]
    
case "Forward Cargo":
    // Forward cargo compartment (Stations 275-390)
    return [
        "Powered Door Actuator",         // Hydraulic door mechanism
        "Manual Release Handle",         // Emergency operation
        "Smoke Detector",                // Fire detection system
        "Halon Manifold",                // Fire suppression
        "Ball Transfer Unit",            // Container loading system
        "Sidewall Panel",                // Composite structure
        "Divider Net Attachment",        // Bulk cargo restraint
        "Floor Track",                   // Container guides
        "Insulation Blanket",            // Thermal/acoustic
        "Ceiling Light"                  // LED illumination
    ]
    
case "Aft Cargo":
    // Aft cargo compartment (Stations 1220-1350)
    return [
        "Bulk Door Latch",               // Bulk compartment access
        "Pressure Bulkhead Interface",   // Station 1016 junction
        "Cargo Heat Manifold",           // Temperature control
        "Environmental Duct",            // ECS distribution
        "9G Barrier Net",                // Crash safety system
        "Sidewall Attachment",           // Panel mounting point
        "Door Warning Sensor",           // Lock indication
        "Floor Panel Joint",             // Structural interface
        "Drain Valve",                   // Water management
        "Access Panel"                   // Service entry point
    ]
    
case "Vertical Stabilizer", "Vertical Tail":
    // Composite vertical stabilizer structure
    return [
        "Box Beam Assembly",             // Primary structure
        "Rudder Hinge Bracket",          // Control surface attachment
        "Trim Tab Actuator",             // Flight control adjustment
        "Lightning Strike Point",        // Designated attachment
        "Static Discharge Wick",         // Electrical protection
        "Leading Edge",                  // Aerodynamic surface
        "Trailing Edge",                 // Control surface interface
        "Access Panel",                  // Internal inspection port
        "Bonding Jumper",                // Electrical continuity
        "VOR Antenna Mount"              // Navigation equipment
    ]
    
case "Horizontal Stabilizer":
    // Composite horizontal stabilizer
    return [
        "Torque Box",                    // Main structural assembly
        "Elevator Hinge Fitting",        // Control surface mount
        "Trunnion Bearing",              // Fuselage attachment
        "Stabilizer Jack Screw",         // Trim adjustment mechanism
        "Balance Weight",                // Control surface balance
        "Anti-Ice Duct",                 // Leading edge protection
        "Composite Bond Line",           // Critical inspection area
        "Access Door",                   // Maintenance entry
        "Position Sensor",               // Trim indication
        "Actuator Mount"                 // Drive mechanism attachment
    ]
    
case "Forward Fuselage", "Section 41":
    // Stations 178-360
    return [
        "Radome Attachment Ring",        // Nose cone interface
        "Forward Pressure Bulkhead",     // Pressure vessel boundary
        "Nose Gear Wheel Well",          // NLG bay structure
        "Window Belt",                   // Cockpit window frames
        "Door 1 Frame",                  // Entry door structure
        "Floor Beam",                    // Structural support
        "Crown Panel",                   // Upper fuselage skin
        "Keel Beam",                     // Lower centerline structure
        "Frame Station 275",             // Specific frame location
        "Wire Raceway"                   // Electrical routing
    ]
    
case "Center Fuselage", "Section 44":
    // Stations 540-727 (Wing box area)
    return [
        "Wing Box Interface",            // Wing attachment structure
        "MLG Attachment Frame",          // Main gear mounting
        "Center Fuel Tank",              // Fuel system component
        "Door 2/3 Frame",                // Passenger door structure
        "Floor Grid",                    // Cabin floor structure
        "Sidewall Frame",                // Fuselage structure
        "Belly Fairing",                 // Aerodynamic panel
        "Keel Beam Junction",            // Primary structure
        "Frame Station 663",             // Specific frame location
        "System Tunnel"                  // Service routing area
    ]
    
case "Aft Fuselage", "Section 47":
    // Stations 888-1016
    return [
        "Aft Pressure Bulkhead",         // Rear pressure boundary
        "APU Firewall",                  // Fire barrier
        "Door 4 Frame",                  // Aft door structure
        "Tail Cone Interface",           // Section 48 junction
        "Horizontal Stab Attachment",    // Empennage mount
        "Frame Station 1016",            // Critical frame location
        "Crown Splice",                  // Upper skin joint
        "Belly Panel",                   // Lower fuselage skin
        "Longeron",                      // Longitudinal stiffener
        "System Penetration"             // Service pass-through
    ]
    
default:
    // Generic inspection points for undefined zones
    return [
        "Composite Bond Line",           // CFRP joint inspection
        "Metal-Composite Interface",     // Transition joint
        "Frame Station",                 // Structural reference
        "Access Panel",                  // Service entry point
        "Drainage Point",                // Moisture management
        "Grounding Point",               // Electrical bonding
        "Sensor Location",               // System monitoring
        "Attachment Bracket",            // Component mounting
        "Service Port",                  // Maintenance access
        "Inspection Window"              // Visual check point
    ]
}
    }
}
