import UIKit

class CameraViewController: UIViewController {
    private var launchStart: Date? // For profiling camera readiness. Can be removed after optimization.

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let launchStart = Date()
        self.launchStart = launchStart

        // Additional setup...
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let launchStart = launchStart {
            let launchEnd = Date()
            let launchDuration = launchEnd.timeIntervalSince(launchStart)
            print("🚦 Camera ready in \(launchDuration) seconds")
        }
    }
}
