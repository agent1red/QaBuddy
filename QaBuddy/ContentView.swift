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
    let persistenceController = PersistenceController.shared

    var body: some View {
        CameraView()
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
    }
}

#Preview {
    ContentView()
}
