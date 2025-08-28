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

    let persistenceController = PersistenceController.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // Camera View - Tab 0
            CameraView()
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
        }
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        .accentColor(.blue) // Aviation-appropriate accent color
    }
}

#Preview {
    ContentView()
}

