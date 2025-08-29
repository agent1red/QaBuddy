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
                        Text("\(SessionManager.shared.allSessions.count)")
                            .font(.title)
                            .foregroundColor(.blue)
                        Text("Total Sessions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text("\(SessionManager.shared.activeSession != nil ? "1" : "0")")
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
                        showingSessionHistory = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: {
                        if let activeSession = SessionManager.shared.activeSession {
                            let alertController = UIAlertController(
                                title: "End Current Session?",
                                message: "Current session '\(activeSession.name ?? "")' will be completed and a new one can be started.",
                                preferredStyle: .alert
                            )

                            alertController.addAction(UIAlertAction(title: "End Session", style: .destructive) { _ in
                                Task {
                                    SessionManager.shared.updateSessionStatus(activeSession, to: .completed)
                                }
                            })

                            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))

                            // Present alert (this requires access to a UIViewController)
                            // For now, just complete the session
                            Task {
                                SessionManager.shared.updateSessionStatus(activeSession, to: .completed)
                            }
                        } else {
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
            SessionHistoryView()
        }
        .onAppear {
            // Load sessions on app launch
            Task {
                await SessionManager.shared.preloadSessions()
            }
        }
    }
}

#Preview {
    ContentView()
}
