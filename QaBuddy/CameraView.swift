//
//  CameraView.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/27/25.
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Update if needed
    }
}

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    /// Handler for tab switching requests
    var tabSwitchHandler: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var captureDevice: AVCaptureDevice?
    private let audioSession = AVAudioSession.sharedInstance()

    // Volume button detection
    private var notificationObserver: NSObjectProtocol?
    private var volumeDetectionEnabled = false
    private var volumeCheckTimer: Timer?
    private let initialVolume: Float

    // Haptic feedback
    private let captureFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let errorFeedback = UINotificationFeedbackGenerator()

    // Photo management
    private let photoManager = PhotoManager()
    private let sessionManager = SessionManager.shared

    private var sessionObserver: NSObjectProtocol?
    private let sequenceManager = SequenceManager() // Keep for migration and sequence number generation

    // Sequence display overlay
    private var sequenceOverlayLabel: PaddingLabel?

    // Session header overlay
    private var sessionHeaderView: UIView?
    private var sessionHeaderLabel: UILabel?

    init() {
        self.initialVolume = createVolumeBaseline()
        super.init(nibName: nil, bundle: nil)
        requestPermissions()
    }

    required init?(coder: NSCoder) {
        self.initialVolume = createVolumeBaseline()
        super.init(coder: coder)
        requestPermissions()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCamera()
        setupVolumeDetection()
        setupAudioSession()
        setupSequenceOverlay()
        setupSessionHeader()

        // Generator is reusable
        captureFeedback.prepare()
        errorFeedback.prepare()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCamera()
        resumeVolumeDetection()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pauseVolumeDetection()
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if !granted {
                DispatchQueue.main.async {
                    self?.showPermissionError()
                }
            }
        }
    }

    private func showPermissionError() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to capture photos for your inspection documentation.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Settings", style: .default, handler: { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        }))

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    private func setupCamera() {
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("No camera available")
            return
        }

        captureDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            photoOutput = AVCapturePhotoOutput()
            if let photoOutput = photoOutput, captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }

            setupPreviewLayer()

            // Configure flash mode
            if device.hasTorch {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            }

        } catch {
            print("Error setting up camera: \(error)")
            errorFeedback.notificationOccurred(.error)
        }
    }

    private func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        view.layer.addSublayer(previewLayer!)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateSessionHeader()
    }

    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .default, policy: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Error setting up audio session: \(error)")
        }
    }

    private func setupVolumeDetection() {
        // Volume button detection using MPVolumeView as an invisible view
        // This is the recommended approach for detecting volume button presses without audio interference
        let volumeView = VolumeDetectionView()
        volumeView.frame = .zero
        volumeView.alpha = 0.01  // Make it essentially invisible but still functional
        view.addSubview(volumeView)

        // Set up KVO on the volume slider to detect changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(volumeButtonPressed),
            name: NSNotification.Name(rawValue: "VolumeButtonPressed"),
            object: nil
        )
    }

    private func setupSequenceOverlay() {
        sequenceOverlayLabel = PaddingLabel()
        guard let label = sequenceOverlayLabel else { return }

        // Aviation-inspired professional styling
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textColor = .white
        // Make lettering twice as small (36 -> 18)
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 3  // Enable multiline support
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.layer.borderWidth = 2
        label.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor

        // Set padding for the label
        label.edgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        view.addSubview(label)
        updateSequenceOverlay()

        // Position in camera viewfinder: move it further down from the top
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Move down a bit more (from 20 to 80)
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            // Reduce minimum size since font is smaller
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    private func updateSequenceOverlay() {
        guard let label = sequenceOverlayLabel else { return }

        // Update the display with current sequence and session info
        Task {
            let sequence = sequenceManager.currentSequence

            // Get real session info asynchronously
            let sessionInfo = await sessionManager.getCurrentSessionInfo()
            let sessionName = sessionManager.activeSession?.name ?? "Default Session"

            await MainActor.run {
                // Use real session info instead of old sequence manager
                let displayName = sessionName.count > 12 ? String(sessionName.prefix(12)) + "..." : sessionName

                // Display format: "Photo\n8\nSession Name\n(Inspection Type • Tail)"
                let sequenceText = "Photo\n\(sequence)\n\(displayName)"
                label.text = sequenceText

                // Animate the change briefly to draw attention
                UIView.animate(withDuration: 0.2, animations: {
                    label.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                }) { _ in
                    UIView.animate(withDuration: 0.1) {
                        label.transform = CGAffineTransform.identity
                    }
                }
            }
        }
    }

    private func resumeVolumeDetection() {
        volumeDetectionEnabled = true
        // Reset volume detection baseline
    }

    private func pauseVolumeDetection() {
        volumeDetectionEnabled = false
    }

    private func handleVolumeButtonPress() {
        if volumeDetectionEnabled {
            capturePhoto(volumeTriggered: true)
        }
    }

    @objc private func volumeButtonPressed() {
        if volumeDetectionEnabled {
            capturePhoto(volumeTriggered: true)
        }
    }

    private func startCamera() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }

    private func stopCamera() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func capturePhoto(volumeTriggered: Bool = false) {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        photoOutput?.capturePhoto(with: settings, delegate: self)

        // Provide haptic feedback
        if volumeTriggered {
            captureFeedback.impactOccurred(intensity: 0.8)
        } else {
            captureFeedback.impactOccurred(intensity: 0.6)
        }

        // Visual feedback
        showCaptureFlash()
    }

    private func showCaptureFlash() {
        let flashView = UIView(frame: view.bounds)
        flashView.backgroundColor = .white
        flashView.alpha = 0.4

        view.addSubview(flashView)

        UIView.animate(withDuration: 0.1, animations: {
            flashView.alpha = 0
        }) { _ in
            flashView.removeFromSuperview()
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            errorFeedback.notificationOccurred(.error)
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            print("No image data")
            return
        }

        // Convert to UIImage for storage
        guard let image = UIImage(data: imageData) else {
            print("Failed to create image from data")
            errorFeedback.notificationOccurred(.error)
            return
        }

        // Save photo using PhotoManager with new SessionManager
        Task {
            do {
                // Get active session info for photo metadata
                let activeSessionId = sessionManager.activeSessionIdString ?? "default-session"

                // Use old sequence manager for current sequence number within this session
                let currentSessionSequence = sequenceManager.currentSequence

                let metadata = PhotoMetadata(
                    sequenceNumber: currentSessionSequence,
                    sessionID: activeSessionId,
                    location: nil, // Can be added later with CLLocationManager
                    deviceOrientation: UIDevice.current.orientation.description
                )

                try await photoManager.savePhoto(image: image, metadata: metadata)

                // Increment photo count in the new SessionManager (not sequence count)
                await sessionManager.incrementPhotoCount()

                // Auto-save session data with recovery checkpoint
                await sessionManager.autoSave()

                // Update camera view header with new photo count
                await MainActor.run {
                    self.updateSessionHeader()
                }

                print("Photo saved successfully! Session sequence #\(currentSessionSequence)")

                // Increment sequence number for next photo in this session
                sequenceManager.incrementSequence()

                // Update the visual sequence display
                DispatchQueue.main.async {
                    self.updateSequenceOverlay()
                }

                // Additional haptic feedback for successful save
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                print("Error saving photo to storage: \(error)")
                errorFeedback.notificationOccurred(.error)
            }
        }
    }

    // MARK: - Session Header Management

    private func setupSessionHeader() {
        // Create session header view
        sessionHeaderView = UIView()
        guard let headerView = sessionHeaderView else { return }

        headerView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        headerView.layer.cornerRadius = 8
        headerView.layer.borderWidth = 1
        headerView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor

        // Create header label
        sessionHeaderLabel = UILabel()
        guard let headerLabel = sessionHeaderLabel else { return }

        headerLabel.textColor = .white
        headerLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        headerLabel.numberOfLines = 1
        headerLabel.adjustsFontSizeToFitWidth = true
        headerLabel.minimumScaleFactor = 0.8
        headerLabel.textAlignment = .left

        headerView.addSubview(headerLabel)
        view.addSubview(headerView)

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.translatesAutoresizingMaskIntoConstraints = false

        // Layout constraints
        NSLayoutConstraint.activate([
            // Header view position (top center, below safe area)
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            headerView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            // Header label position inside view
            headerLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            headerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])

        updateSessionHeader()

        // Add tap gesture for session management
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(sessionHeaderTapped))
        headerView.addGestureRecognizer(tapGesture)
        headerView.isUserInteractionEnabled = true
    }

    private func updateSessionHeader() {
        guard let headerLabel = sessionHeaderLabel else { return }

        // Use async method to get real-time session info with accurate photo counts
        Task {
            let sessionInfo = await sessionManager.getCurrentSessionInfo()

            await MainActor.run {
                // Update header text with aviation-appropriate formatting
                if sessionInfo == "No Active Session" {
                    headerLabel.text = "Tap to Start Inspection"
                    headerLabel.textColor = .orange
                } else {
                    headerLabel.text = "📸 \(sessionInfo)"
                    headerLabel.textColor = .white
                }

                // Update header visibility
                sessionHeaderView?.isHidden = false
            }
        }
    }

    @objc private func sessionHeaderTapped() {
        // Navigate to session management (Gallery tab)
        print("🔄 Session header tapped - requesting Gallery tab")
        if sessionManager.activeSession != nil {
            // If we have an active session, switch to gallery
            tabSwitchHandler?("gallery")
            print("✅ Switching to Gallery tab (active session)")
        } else {
            // If no active session, switch to sessions tab to create one
            tabSwitchHandler?("sessions")
            print("✅ Switching to Sessions tab (no active session)")
        }
    }

    // MARK: - Touch Controls

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        if let touch = touches.first, touch.view == view {
            let touchPoint = touch.location(in: view)
            if touchPoint.y > view.bounds.height * 0.8 { // Bottom 20% of screen
                capturePhoto(volumeTriggered: false)
            }
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopCamera()
    }
}

// MARK: - Volume Detection View

class VolumeDetectionView: UIView {
    @objc func volumeChanged(notification: NSNotification) {
        // Check if the notification object is a volume slider and post button press notification
        if (notification.object as? UISlider) != nil {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "VolumeButtonPressed"), object: nil)
        }
    }
}

// MARK: - Padding Label

/// Custom UILabel that supports padding/insets for better text layout
class PaddingLabel: UILabel {
    var edgeInsets: UIEdgeInsets = .zero

    override func drawText(in rect: CGRect) {
        let insetRect = rect.inset(by: edgeInsets)
        super.drawText(in: insetRect)
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += edgeInsets.left + edgeInsets.right
        size.height += edgeInsets.top + edgeInsets.bottom
        return size
    }
}

// Helper function to create a baseline volume reference for volume button detection
func createVolumeBaseline() -> Float {
    // Return a float value between 0.0 and 1.0 as baseline reference
    // In a real implementation, you might use system volume level
    return 0.5
}
