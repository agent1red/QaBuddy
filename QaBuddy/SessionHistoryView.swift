//  SessionHistoryView.swift
//  QA Buddy
//
//  Created by Kevin Hudson on 8/29/25.
//

import SwiftUI

struct SessionHistoryView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var sessionManager = SessionManager.shared
    var onReturnToGallery: (() -> Void)?

    @State private var showingNewSession = false
    @State private var isLoading = true
    @State private var showingDeleteConfirmation = false
    @State private var sessionToDelete: Session?
    @State private var sessionPhotoCounts: [String: Int64] = [:]

    init(onReturnToGallery: (() -> Void)? = nil) {
        self.onReturnToGallery = onReturnToGallery
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView("Loading sessions...")
                } else {
                    sessionListView
                }
            }
            .navigationTitle("Inspection Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewSession = true }) {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                }
            }
            .sheet(isPresented: $showingNewSession) {
                NewSessionView()
            }
            .alert("Delete Session?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteSession(sessionToDelete!)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let session = sessionToDelete {
                    Text("Delete '\(session.name ?? "Unknown Session")' and all its photos? This cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this session?")
                }
            }
        }
        .onAppear {
            Task {
                await loadSessions()
            }
        }
        .refreshable {
            await loadSessions()
        }
    }

    private var sessionListView: some View {
        Group {
            if sessionManager.allSessions.isEmpty {
                emptyStateView
            } else {
                List {
                    // Active Session Section
                    if let activeSession = sessionManager.activeSession {
                        Section(header: Text("Active Session").foregroundColor(.green)) {
                            sessionRow(for: activeSession, isActive: true)
                        }
                    }

                    // Recent Sessions Section
                    if sessionManager.inactiveSessions.count > 0 {
                        Section(header: Text("Recent Sessions")) {
                            ForEach(sessionManager.inactiveSessions) { session in
                                sessionRow(for: session, isActive: false)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "plus.rectangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.3))

            Text("No Inspection Sessions")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Start by creating your first session to begin documenting aircraft inspections and maintenance.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Create First Session") {
                showingNewSession = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 10)
        }
        .padding()
    }

    private func sessionRow(for session: Session, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Session Title & Status
                    HStack {
                        Text(session.name ?? "Unnamed Session")
                            .font(.headline)
                            .foregroundColor(isActive ? .primary : .secondary)

                        Spacer()

                        statusBadge(for: session)
                    }

                    // Inspection Type & Aircraft
                    HStack(spacing: 12) {
                        if let inspectionType = session.inspectionType.flatMap({ InspectionType(rawValue: $0) }) {
                            Label(inspectionType.displayName, systemImage: "airplane.circle.fill")
                        }

                        if let tailNumber = session.aircraftTailNumber {
                            Label(tailNumber, systemImage: "tag.fill")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    // Inspector & Photos (with real-time count)
                    HStack(spacing: 12) {
                        if let inspector = session.inspectorName {
                            Label(inspector, systemImage: "person.fill")
                        }

                        // Get actual photo count from our calculated values
                        let photoCount = session.id.flatMap { sessionPhotoCounts[$0.uuidString] } ?? 0
                        Label("\(photoCount) photos", systemImage: "photo.stack.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }

            // Session Timing
            HStack {
                if let startDate = session.startTimestamp {
                    if isActive {
                        Label(startTimeAgo(from: startDate), systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else {
                        if let endDate = session.endTimestamp {
                            Label(sessionDuration(from: startDate, to: endDate), systemImage: "timer")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        } else {
                            Label(startTimeAgo(from: startDate), systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                if isActive {
                    Button("View Gallery") {
                        print("🔄 SessionHistoryView: View Gallery clicked for active session")
                        dismiss() // Close the sheet
                        // Call callback to switch to gallery tab
                        onReturnToGallery?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Resume") {
                        Task {
                            let success = await sessionManager.switchToSession(session)
                            if success {
                                // Refresh the view to show updated state
                                await loadSessions()
                                print("✅ Successfully resumed session: \(session.name ?? "Unknown")")
                            } else {
                                print("❌ Failed to resume session")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }

                Button(role: .destructive) {
                    sessionToDelete = session
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }

    private func statusBadge(for session: Session) -> some View {
        let status = SessionStatus(rawValue: session.status ?? "Unknown")
        return Text(getStatusText(for: status))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status?.color.opacity(0.2) ?? Color.gray.opacity(0.2))
            .foregroundColor(status?.color ?? .gray)
            .clipShape(Capsule())
    }

    // MARK: - Private Methods

    private func loadSessions() async {
        isLoading = true
        await sessionManager.preloadSessions()

        // Calculate real photo counts for all sessions
        var counts: [String: Int64] = [:]
        for session in sessionManager.allSessions {
            if let sessionId = session.id?.uuidString {
                let photoCount = await sessionManager.calculateRealPhotoCount(for: session)
                counts[sessionId] = photoCount

                // Sync the photo count in the database
                _ = await sessionManager.syncSessionPhotoCount(session)
            }
        }

        await MainActor.run {
            sessionPhotoCounts = counts
            isLoading = false
        }
    }

    private func deleteSession(_ session: Session) async {
        let context = PersistenceController.shared.container.viewContext
        let wasActiveSession = session == sessionManager.activeSession

        // Delete associated photos first
        if let photos = session.photos as? Set<Photo> {
            for photo in photos {
                // Delete image files
                if let imageFilename = photo.imageFilename {
                    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let fullImagePath = documentsDirectory.appendingPathComponent(imageFilename)

                    do {
                        try FileManager.default.removeItem(at: fullImagePath)
                        print("🗑️ Deleted full image file: \(imageFilename)")
                    } catch {
                        print("⚠️ Failed to delete full image file \(imageFilename): \(error)")
                    }
                }

                // Delete thumbnail files
                if let thumbnailFilename = photo.thumbnailFilename {
                    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let thumbnailPath = documentsDirectory.appendingPathComponent(thumbnailFilename)

                    do {
                        try FileManager.default.removeItem(at: thumbnailPath)
                        print("🗑️ Deleted thumbnail file: \(thumbnailFilename)")
                    } catch {
                        print("⚠️ Failed to delete thumbnail file \(thumbnailFilename): \(error)")
                    }
                }

                // Delete photo entities
                context.delete(photo)
            }
        }

        // Delete the session
        context.delete(session)

        do {
            try context.save()
            print("✅ Session '\(session.name ?? "Unknown")' and all photos permanently deleted")

            // If this was the active session, clear it and promote next session
            if wasActiveSession {
                // Clear current active session first
                sessionManager.activeSession = nil
                print("🔥 Active session cleared - checking for promotion candidates")

                // Check for remaining completed sessions and promote the most recent one
                // Note: This refreshes the sessionManager.allSessions after deletion
                await sessionManager.preloadSessions()

                let remainingSessions = sessionManager.allSessions
                    .filter { $0.status == SessionStatus.completed.rawValue && $0.id != session.id }
                    .sorted { ($0.startTimestamp ?? Date()) > ($1.startTimestamp ?? Date()) }

                print("📊 Found \(remainingSessions.count) remaining completed sessions")

                if let nextSession = remainingSessions.first {
                    let success = await sessionManager.switchToSession(nextSession)
                    if success {
                        print("🔄 Auto-promoted next session: \(nextSession.name ?? "Unknown")")
                    } else {
                        print("❌ Failed to auto-promote session: \(nextSession.name ?? "Unknown")")
                    }
                } else {
                    print("ℹ️ No remaining sessions to promote")
                    // No auto-promotion needed - remain in 'No Active Session' state
                }

                sessionManager.objectWillChange.send()
            }

            // Refresh the sessions list
            await loadSessions()
            print("🔄 Session deletion completed - UI refreshed")

        } catch {
            print("❌ Error deleting session: \(error)")
            context.rollback()
        }
    }

    private func getStatusText(for status: SessionStatus?) -> String {
        switch status {
        case .active: return "Active"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case nil: return "Unknown"
        }
    }

    private func startTimeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sessionDuration(from startDate: Date, to endDate: Date) -> String {
        let duration = endDate.timeIntervalSince(startDate)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        return formatter.string(from: duration) ?? "Unknown duration"
    }
}

// MARK: - Preview

struct SessionHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        SessionHistoryView()
    }
}
