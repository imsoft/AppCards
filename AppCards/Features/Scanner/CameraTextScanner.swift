import Foundation
import AVFoundation
import Vision
import SwiftUI

/// Cámara trasera + reconocimiento de texto con Vision. Entrega líneas reconocidas cada ~0.5 s.
final class CameraTextScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.imsoft.appcards.camera")
    private var lastAnalysis = Date.distantPast
    private var isAnalyzing = false
    var onLines: (([RecognizedLine]) -> Void)?
    var isPaused = false

    private var output: AVCaptureVideoDataOutput?
    private var device: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []

    @Published private(set) var isAvailable = true
    @Published private(set) var permissionDenied = false

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async { self.permissionDenied = !granted }
            guard granted else { return }
            self.queue.async { self.configureAndRun() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        guard session.inputs.isEmpty else {
            if !session.isRunning { session.startRunning() }
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            DispatchQueue.main.async { self.isAvailable = false }
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        self.output = output
        self.device = device
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { self.setUpRotation() }
    }

    /// La vista previa la crea SwiftUI; cuando existe, se conecta para girar con el iPad.
    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        setUpRotation()
    }

    /// Gira la vista previa y los cuadros que lee Vision según la orientación real del dispositivo (iPad en horizontal).
    private func setUpRotation() {
        guard rotationCoordinator == nil, let device, let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyRotation(coordinator)
        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coordinator, _ in
                DispatchQueue.main.async { self?.applyRotation(coordinator) }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coordinator, _ in
                DispatchQueue.main.async { self?.applyRotation(coordinator) }
            },
        ]
    }

    private func applyRotation(_ coordinator: AVCaptureDevice.RotationCoordinator) {
        let previewAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(previewAngle) {
            connection.videoRotationAngle = previewAngle
        }
        let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        queue.async { [output] in
            if let connection = output?.connection(with: .video), connection.isVideoRotationAngleSupported(captureAngle) {
                connection.videoRotationAngle = captureAngle
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isPaused, !isAnalyzing, Date().timeIntervalSince(lastAnalysis) > 0.5,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isAnalyzing = true
        lastAnalysis = .now

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            defer { self?.isAnalyzing = false }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let lines = observations.compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedLine(text: candidate.string, confidence: candidate.confidence, box: observation.boundingBox)
            }
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async { self?.onLines?(lines) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            isAnalyzing = false
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onLayer: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        onLayer?(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
