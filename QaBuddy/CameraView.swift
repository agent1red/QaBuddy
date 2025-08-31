//
//  CameraView.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/27/25.
//

import SwiftUI
import AVFoundation
import UIKit
import Combine

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

    // Orientation handling
    private var orientationObserver: NSObjectProtocol?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    // Combine
    private var cancellables = Set<AnyCancellable>()

    // Zoom handling
    private var initialZoomFactor: CGFloat = 1.0
    private var currentZoomFactor: CGFloat = 1.0
    private var zoomIndicatorLabel: UILabel?
    private var zoomHideWorkItem: DispatchWorkItem?

    // Reliability: capture throttling and state
    private var inFlightCapture = false
    private var lastCaptureTime: Date?
    private let captureThrottleInterval: TimeInterval = 0.5

    // Foreground observer
    private var foregroundObserver: NSObjectProtocol?

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
        setupOrientationUpdates()
        setupSessionObservers()
        setupPinchToZoom()
        setupDoubleTapToZoom()
        setupZoomIndicator()
        setupForegroundObserver()

        // Prepare haptics
        captureFeedback.prepare()
        errorFeedback.prepare()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCamera()
        resumeVolumeDetection()
        updateVideoOrientation()

        // Attempt recovery if needed
        Task {
            if sessionManager.activeSession == nil {
                let recovered = await sessionManager.loadFromRecoveryCheckpoint()
                Logger.info("Recovery attempt on appear: \(recovered ? "Recovered active session" : "No recovery needed")")
                if recovered {
                    await MainActor.run {
                        self.updateSessionHeader()
                        self.updateSequenceOverlay()
                    }
                }
            }

            // Integrity checks and sync on appear
            _ = await sessionManager.performIntegrityCheck()
            await sessionManager.syncAllSessionCounts()
        }

        // Ensure overlays reflect the latest session immediately when returning to camera
        updateSessionHeader()
        updateSequenceOverlay()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pauseVolumeDetection()
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted == false {
                Logger.warn("Camera permission not granted")
                DispatchQueue.main.async {
                    self?.presentErrorAlert(
                        title: "Camera Access Required",
                        message: "Enable camera access in Settings to capture photos.",
                        actions: [
                            ("Open Settings", { _ in
                                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsUrl)
                                }
                            }),
                            ("Cancel", { _ in })
                        ]
                    )
                }
            }
        }
    }

    private func showPermissionError() {
        presentErrorAlert(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to capture photos for your inspection documentation.",
            actions: [
                ("Settings", { _ in
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }),
                ("Cancel", { _ in })
            ]
        )
    }

    private func setupCamera() {
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            Logger.error("No camera available")
            presentErrorAlert(title: "Camera Unavailable", message: "Your device’s camera is not available.")
            return
        }

        captureDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                Logger.error("Cannot add camera input to session")
            }

            photoOutput = AVCapturePhotoOutput()
            if let photoOutput = photoOutput, captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            } else {
                Logger.error("Cannot add photo output to session")
            }

            setupPreviewLayer()

            // Configure flash mode
            if device.hasTorch {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            }

            // Initialize current zoom factor from device
            currentZoomFactor = device.videoZoomFactor
            initialZoomFactor = currentZoomFactor

            // Initialize rotation coordinator for iOS 17+ compatibility
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        } catch {
            Logger.error("Error setting up camera: \(error.localizedDescription)")
            errorFeedback.notificationOccurred(.error)
            presentErrorAlert(
                title: "Camera Setup Failed",
                message: "Please restart the app. If the issue persists, check camera permissions in Settings."
            )
        }
    }

    private func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds

        // Initialize rotation coordinator after preview layer is created
        if let device = captureDevice {
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)

            // Observe rotations using KVO
            setupRotationObserver()
        }

        view.layer.addSublayer(previewLayer!)
        updateVideoOrientation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateVideoOrientation()
        updateSessionHeader()
    }

    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .default, policy: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            Logger.warn("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    private func setupVolumeDetection() {
        // Volume button detection using MPVolumeView as an invisible view
        let volumeView = VolumeDetectionView()
        volumeView.frame = .zero
        volumeView.alpha = 0.01
        view.addSubview(volumeView)

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

        // Styling
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .bold) // smaller per your request
        label.textAlignment = .center
        label.numberOfLines = 3
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.layer.borderWidth = 2
        label.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor

        label.edgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        view.addSubview(label)
        updateSequenceOverlay()

        // Position lower
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    private func updateSequenceOverlay() {
        guard let label = sequenceOverlayLabel else { return }

        Task {
            let sequence = sequenceManager.currentSequence
            let sessionName = sessionManager.activeSession?.name ?? "Unknown Session"

            await MainActor.run {
                let displayName = sessionName.count > 12 ? String(sessionName.prefix(12)) + "..." : sessionName
                let sequenceText = "Photo\n\(sequence)\n\(displayName)"
                label.text = sequenceText

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
                DispatchQueue.main.async {
                    self?.updateVideoOrientation()
                }
            }
        }
    }

    private func stopCamera() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func capturePhoto(volumeTriggered: Bool = false) {
        // Throttle rapid successive captures
        let now = Date()
        if inFlightCapture {
            Logger.debug("Capture ignored: in-flight capture still processing")
            return
        }
        if let last = lastCaptureTime, now.timeIntervalSince(last) < captureThrottleInterval {
            Logger.debug("Capture throttled: too soon since last (\(now.timeIntervalSince(last))s)")
            return
        }

        guard photoOutput != nil else {
            presentErrorAlert(title: "Camera Not Ready", message: "Please wait a moment and try again.")
            return
        }

        inFlightCapture = true
        lastCaptureTime = now

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        // Apply rotation angle from iOS 17+ rotation coordinator
        if let coordinator = rotationCoordinator {
            let rotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            if let connection = photoOutput?.connections.first, connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
        }

        photoOutput?.capturePhoto(with: settings, delegate: self)

        // Haptics
        captureFeedback.impactOccurred(intensity: volumeTriggered ? 0.8 : 0.6)

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

    // MARK: - Zoom UI & Gestures

    private func setupZoomIndicator() {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.alpha = 0.0
        label.text = formattedZoomText(currentZoomFactor)

        zoomIndicatorLabel = label
        view.addSubview(label)

        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            label.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func formattedZoomText(_ factor: CGFloat) -> String {
        // Round to nearest 0.1x
        let rounded = (factor * 10).rounded() / 10.0
        return "\(rounded)x"
    }

    private func showZoomIndicator() {
        guard let label = zoomIndicatorLabel else { return }

        // Update text and show
        label.text = formattedZoomText(currentZoomFactor)
        UIView.animate(withDuration: 0.15) {
            label.alpha = 1.0
        }

        // Cancel any pending hides and schedule a new one
        zoomHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.25) {
                self?.zoomIndicatorLabel?.alpha = 0.0
            }
        }
        zoomHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func setupPinchToZoom() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        view.addGestureRecognizer(pinch)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = captureDevice else { return }

        // Determine supported zoom range
        let maxSupported = min(device.activeFormat.videoMaxZoomFactor, 6.0) // cap at ~6x for quality
        let minSupported: CGFloat = 1.0

        switch gesture.state {
        case .began:
            initialZoomFactor = currentZoomFactor
            showZoomIndicator()
        case .changed:
            var newZoom = initialZoomFactor * gesture.scale
            newZoom = max(min(newZoom, maxSupported), minSupported)
            setZoom(to: newZoom, animated: false)
            showZoomIndicator()
        case .ended, .cancelled, .failed:
            initialZoomFactor = currentZoomFactor
            showZoomIndicator() // will auto-hide
        default:
            break
        }
    }

    private func setupDoubleTapToZoom() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        view.addGestureRecognizer(doubleTap)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let device = captureDevice else { return }
        let maxSupported = min(device.activeFormat.videoMaxZoomFactor, 6.0)

        // Toggle between 1x and 2x (or clamp to max if device < 2x)
        let target: CGFloat
        if currentZoomFactor < 1.5 {
            target = min(2.0, maxSupported)
        } else {
            target = 1.0
        }

        setZoom(to: target, animated: true)
        showZoomIndicator()
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }

    private func setZoom(to factor: CGFloat, animated: Bool) {
        guard let device = captureDevice else { return }
        let clamped = max(1.0, min(factor, min(device.activeFormat.videoMaxZoomFactor, 6.0)))

        do {
            try device.lockForConfiguration()
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.2)
                device.videoZoomFactor = clamped
                CATransaction.commit()
            } else {
                device.videoZoomFactor = clamped
            }
            device.unlockForConfiguration()
            currentZoomFactor = clamped
        } catch {
            Logger.warn("Zoom configuration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Orientation Handling

    private func setupOrientationUpdates() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateVideoOrientation()
        }
    }

    private func setupRotationObserver() {
        // Observe rotation changes using iOS 17+ KVO approach
        guard let coordinator = rotationCoordinator else { return }

        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.old, .new]
        ) { [weak self] coordinator, change in
            DispatchQueue.main.async {
                if let connection = self?.previewLayer?.connection {
                    // Check if rotation angle is supported before applying
                    if connection.isVideoRotationAngleSupported(coordinator.videoRotationAngleForHorizonLevelPreview) {
                        connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
                    }
                }

                if let connection = self?.photoOutput?.connections.first {
                    if connection.isVideoRotationAngleSupported(coordinator.videoRotationAngleForHorizonLevelPreview) {
                        connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
                    }
                }
            }
        }
    }

    private func updateVideoOrientation() {
        // Apply rotation angle using iOS 17+ RotationCoordinator APIs
        guard let coordinator = rotationCoordinator else {
            Logger.warn("Rotation coordinator not available")
            return
        }

        let rotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture

        // Apply to preview layer connection
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }

        // Apply to photo output connection so captures are upright
        if let connection = photoOutput?.connections.first, connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.previewLayer?.frame = CGRect(origin: .zero, size: size)
            self.updateVideoOrientation()
        })
    }

    // MARK: - Session Observers & Foreground

    private func setupSessionObservers() {
        // Update overlays immediately when the active session changes
        sessionManager.$activeSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSessionHeader()
                self?.updateSequenceOverlay()
            }
            .store(in: &cancellables)
    }

    private func setupForegroundObserver() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Logger.info("App entering foreground: verifying integrity and refreshing overlays")
            Task {
                _ = await self.sessionManager.performIntegrityCheck()
                await self.sessionManager.syncAllSessionCounts()
                await MainActor.run {
                    self.updateSessionHeader()
                    self.updateSequenceOverlay()
                }
            }
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer {
            // Allow next capture
            inFlightCapture = false
            lastCaptureTime = Date()
        }

        if let error = error {
            Logger.error("Error capturing photo: \(error.localizedDescription)")
            errorFeedback.notificationOccurred(.error)

            let nsError = error as NSError
            if isStorageOutOfSpace(nsError) {
                presentErrorAlert(
                    title: "Storage Full",
                    message: "Your device is out of storage. Free up space and try again.",
                    actions: [("OK", { _ in })]
                )
            } else {
                presentErrorAlert(
                    title: "Capture Failed",
                    message: "Unable to capture photo. Please try again.",
                    actions: [("OK", { _ in })]
                )
            }
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            Logger.error("No image data from capture")
            presentErrorAlert(title: "Capture Failed", message: "No image data was returned.")
            return
        }

        // Convert to UIImage for storage
        guard let image = UIImage(data: imageData) else {
            Logger.error("Failed to create image from data")
            errorFeedback.notificationOccurred(.error)
            presentErrorAlert(title: "Capture Failed", message: "Captured data could not be decoded.")
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

                // Enhanced auto-save with recovery checkpoint
                await sessionManager.autoSaveWithRecovery()

                // Update camera view header with new photo count
                await MainActor.run {
                    self.updateSessionHeader()
                }

                Logger.info("Photo saved successfully (session seq #\(currentSessionSequence))")

                // Increment sequence number for next photo in this session
                sequenceManager.incrementSequence()

                // Update the visual sequence display
                DispatchQueue.main.async {
                    self.updateSequenceOverlay()
                }

                // Additional haptic feedback for successful save
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                let nsError = error as NSError
                Logger.error("Error saving photo: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
                errorFeedback.notificationOccurred(.error)

                if isStorageOutOfSpace(nsError) {
                    presentErrorAlert(
                        title: "Storage Full",
                        message: "Your device is out of storage. Free up space and try again.",
                        actions: [("OK", { _ in })]
                    )
                } else {
                    presentErrorAlert(
                        title: "Save Failed",
                        message: "We couldn’t save the photo. Please try again. If the issue persists, restart the app.",
                        actions: [("OK", { _ in })]
                    )
                }
            }
        }
    }

    private func isStorageOutOfSpace(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError { return true }
        // POSIX ENOSPC (28) sometimes comes through as NSPOSIXErrorDomain
        if error.domain == NSPOSIXErrorDomain && error.code == 28 { return true }
        return false
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
                // Update header text
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
        if sessionManager.activeSession != nil {
            tabSwitchHandler?("gallery")
        } else {
            tabSwitchHandler?("sessions")
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

    // MARK: - Alerts

    private func presentErrorAlert(title: String, message: String, actions: [(String, (UIAlertAction) -> Void)] = [("OK", { _ in })]) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for (title, handler) in actions {
            let style: UIAlertAction.Style = title.lowercased().contains("cancel") ? .cancel : .default
            alert.addAction(UIAlertAction(title: title, style: style, handler: handler))
        }
        present(alert, animated: true)
    }

    // MARK: - Deinit

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let orientationObserver = orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
        if let foregroundObserver = foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        rotationObservation?.invalidate()  // Invalidate rotation observer
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        zoomHideWorkItem?.cancel()
        cancellables.removeAll()
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
