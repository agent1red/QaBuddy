//
//  ContentView.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/25/25.
//

import SwiftUI
import AVFoundation
import UIKit
import CoreData

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showingNewSession = false
    @State private var showingSessionHistory = false
    @State private var totalSessions: Int = 0
    @State private var activeSessionCount: Int = 0

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
                        if let activeSession = SessionManager.shared.activeSession {
                            print("🔄 Completing current session: \(activeSession.name ?? "Unknown")")
                            let alertController = UIAlertController(
                                title: "End Current Session?",
                                message: "Current session '\(activeSession.name ?? "")' will be completed and a new one can be started.",
                                preferredStyle: .alert
                            )

                            alertController.addAction(UIAlertAction(title: "End Session", style: .destructive) { _ in
                                Task {
                                    await SessionManager.shared.updateSessionStatus(activeSession, to: .completed)
                                    await updateSessionCounters() // Refresh counters after session change
                                    print("✅ Active session completed")
                                }
                            })

                            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))

                            // Present alert (this requires access to a UIViewController)
                            // For now, just complete the session
                            Task {
                                await SessionManager.shared.updateSessionStatus(activeSession, to: .completed)
                                await updateSessionCounters() // Refresh counters after session change
                                print("✅ Active session completed")
                            }
                        } else {
                            print("🔗 Opening New Session creation")
                            showingNewSession = true
                        }
                    }) {
                        Text(SessionManager.shared.activeSession != nil ? "Complete Current Session" : "Start New Session")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(SessionManager.shared.activeSession != nil ? .orange : .green)
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
        }
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        .accentColor(.blue) // Aviation-appropriate accent color
        .sheet(isPresented: $showingNewSession) {
            NewSessionView()
        }
        .sheet(isPresented: $showingSessionHistory) {
            SessionHistoryView(onReturnToGallery: {
                print("🔄 Callback: Switching to Gallery tab from SessionHistoryView")
                selectedTab = 1 // Switch to Gallery tab
            })
        }
        .onAppear {
            // Load sessions on app launch
            Task {
                await updateSessionCounters()
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
            print("📊 Updated session counters - Total: \(totalSessions), Active: \(activeSessionCount)")
        }
    }
}

#Preview {
    ContentView()
}
