//  CameraViewWrapper.swift
//  QA Buddy
//
//  Created by Kevin Hudson on 8/29/25.
//

import SwiftUI
import UIKit

/// Wrapper to integrate UIKit CameraViewController with SwiftUI and enable tab navigation coordination
struct CameraViewWrapper: UIViewControllerRepresentable {
    @Binding var selectedTab: Int

    func makeUIViewController(context: Context) -> UINavigationController {
        let cameraController = CameraViewController()
        cameraController.tabSwitchHandler = { action in
            handleTabSwitch(action: action)
        }

        let navigationController = UINavigationController(rootViewController: cameraController)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Update if needed
    }

    /// Handle navigation actions from the CameraViewController
    private func handleTabSwitch(action: String) {
        switch action {
        case "gallery":
            // Switch to gallery tab
            selectedTab = 1
        case "sessions":
            // Switch to sessions tab
            selectedTab = 2
        default:
            break
        }
    }
}

/// Coordinator for communicating between UIKit and SwiftUI
class Coordinator: NSObject {
    var parent: CameraViewWrapper

    init(parent: CameraViewWrapper) {
        self.parent = parent
    }
}

// MARK: - CameraViewController Extensions

extension CameraViewController {
    // Note: `tabSwitchHandler` property should be declared in the main class definition of CameraViewController

    /// Request to switch to gallery tab
    func requestGalleryTab() {
        tabSwitchHandler?("gallery")
    }

    /// Request to switch to sessions tab
    func requestSessionsTab() {
        tabSwitchHandler?("sessions")
    }



    private func switchToGalleryTab() {
        tabSwitchHandler?("gallery")
    }
}
