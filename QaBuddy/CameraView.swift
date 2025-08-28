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
    private let sequenceManager = SequenceManager()

    // Sequence display overlay
    private var sequenceOverlayLabel: PaddingLabel?

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
        label.font = .systemFont(ofSize: 36, weight: .bold)
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

        // Position prominently in camera viewfinder (top-left to avoid obstructing subject)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),    // Increased width
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)    // Increased height for 3 lines
        ])
    }

    private func updateSequenceOverlay() {
        guard let label = sequenceOverlayLabel else { return }

        // Update the display with current sequence
        let sequence = sequenceManager.currentSequence
        let sessionName = sequenceManager.activeSessionName

        // Display format: "Photo\n8\nSession: Pre-flight"
        let sequenceText = "Photo\n\(sequence)\n\(sessionName.count > 12 ? String(sessionName.prefix(12)) + "..." : sessionName)"
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

        // Save photo using PhotoManager
        Task {
            do {
                // Get current sequence metadata before incrementing
                let currentSequence = sequenceManager.currentSequence
                let sessionMetadata = sequenceManager.getPhotoMetadata(forSequence: currentSequence)

                let metadata = PhotoMetadata(
                    sequenceNumber: sessionMetadata.sequence,
                    sessionID: sessionMetadata.sessionId,
                    location: nil, // Can be added later with CLLocationManager
                    deviceOrientation: UIDevice.current.orientation.description
                )

                try await photoManager.savePhoto(image: image, metadata: metadata)
                print("Photo saved successfully! Sequence #\(sessionMetadata.sequence)")

                // Increment sequence number for next photo
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
