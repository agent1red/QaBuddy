//
//  ContentView.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/25/25.
//

import SwiftUI
import UIKit
import AVFoundation
import CoreData

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showingNewSession = false
    @State private var showingSessionHistory = false
    @State private var totalSessions: Int = 0
    @State private var activeSessionCount: Int = 0
    @StateObject private var sessionManager = SessionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController = PersistenceController.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // Camera View - Tab 0
            CameraViewWrapper(selectedTab: $selectedTab)
                .tabItem {
                    VStack {
                        Image(systemName: "camera.fill")
                        Text("Camera")
                    }
                }
                .tag(0)

            // Gallery View - Tab 1
            PhotoGalleryView()
                .tabItem {
                    VStack {
                        Image(systemName: "photo.stack.fill")
                        Text("Gallery")
                    }
                }
                .tag(1)

            // Sessions View - Tab 2
            VStack {
                Text("Inspection Sessions")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding()

                HStack(spacing: 20) {
                    // Quick Stats
                    VStack {
                        Text("\(totalSessions)")
                            .font(.title)
                            .foregroundColor(.blue)
                        Text("Total Sessions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text("\(activeSessionCount)")
                            .font(.title)
                            .foregroundColor(.green)
                        Text("Active Session")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

                Spacer()

                // Action Buttons
                VStack(spacing: 16) {
                    Button("Manage Sessions") {
                        print("🔗 Opening Session History")
                        showingSessionHistory = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: {
                        print("🔗 Opening New Session creation (with auto-completion of current session)")
                        showingNewSession = true
                    }) {
                        Text("Start New Session")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.green)
                }
                .padding(.horizontal)

                Spacer()
            }
            .tabItem {
                VStack {
                    Image(systemName: SessionManager.shared.activeSession != nil ? "airplane.circle.fill" : "airplane.circle")
                    Text("Sessions")
                }
            }
            .tag(2)

            // Templates View - Tab 3
            TemplateLibraryView()
                .tabItem {
                    VStack {
                        Image(systemName: "clipboard")
                        Text("Templates")
                    }
                }
                .tag(3)
        }
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        .accentColor(.blue) // Aviation-appropriate accent color
        .onReceive(sessionManager.objectWillChange) { _ in
            Task {
                await updateSessionCounters()
            }
        }
        .sheet(isPresented: $showingNewSession, onDismiss: {
            // Update counters when new session sheet is dismissed
            print("🔄 New session sheet dismissed - refreshing counters")
            Task {
                await updateSessionCounters()
            }
        }) {
            NewSessionView()
        }
        .sheet(isPresented: $showingSessionHistory, onDismiss: {
            // Update counters when session history sheet is dismissed
            print("🔄 Session history sheet dismissed - refreshing counters")
            Task {
                await updateSessionCounters()
            }
        }) {
            let callback = {
                print("🔄 Callback: Switching to Gallery tab from SessionHistoryView")
                selectedTab = 1 // Switch to Gallery tab
            }
            SessionHistoryView(onReturnToGallery: callback)
        }
        .onAppear {
            // Load sessions on app launch and run integrity checks
            Task {
                // Attempt recovery if needed
                if SessionManager.shared.activeSession == nil {
                    let recovered = await SessionManager.shared.loadFromRecoveryCheckpoint()
                    Logger.info("App launch recovery: \(recovered ? "Recovered active session" : "None")")
                }
                await sessionManager.syncAllSessionCounts()
                _ = await sessionManager.performIntegrityCheck()
                await updateSessionCounters()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await sessionManager.syncAllSessionCounts()
                    _ = await sessionManager.performIntegrityCheck()
                    await updateSessionCounters()
                }
            case .background:
                Task {
                    await sessionManager.autoSaveWithRecovery()
                    Logger.info("Background: autoSaveWithRecovery checkpoint created")
                }
            default:
                break
            }
        }
    }

    // MARK: - Helper Methods

    private func updateSessionCounters() async {
        // Preload sessions first
        await SessionManager.shared.preloadSessions()

        // Update counters with accurate data
        let allSessions = await SessionManager.shared.fetchAllSessions()
        let activeSessionCount = SessionManager.shared.activeSession != nil ? 1 : 0

        await MainActor.run {
            self.totalSessions = allSessions.count
            self.activeSessionCount = activeSessionCount
        }
    }
}

#Preview {
    ContentView()
}
