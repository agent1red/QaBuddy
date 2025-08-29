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
        if let cameraController = uiViewController.viewControllers.first as? CameraViewController {
            cameraController.tabSwitchHandler = { action in
                handleTabSwitch(action: action)
            }
        }
    }

    /// Handle navigation actions from the CameraViewController
    private func handleTabSwitch(action: String) {
        print("🔄 CameraViewWrapper: Switching tab to: \(action)")
        switch action {
        case "gallery":
            // Switch to gallery tab
            selectedTab = 1
            print("✅ Switched to Gallery tab (1)")
        case "sessions":
            // Switch to sessions tab
            selectedTab = 2
            print("✅ Switched to Sessions tab (2)")
        case "camera":
            // Switch to camera tab
            selectedTab = 0
            print("✅ Switched to Camera tab (0)")
        default:
            print("⚠️ Unknown tab switch action: \(action)")
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
