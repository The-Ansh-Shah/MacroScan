import AVFoundation
import SwiftUI
import Observation

#if canImport(UIKit)
/// AVFoundation-based barcode scanner using the camera.
/// Call `start()` once from `.task` — it awaits authorization, configures the
/// session, and begins scanning in one go. Avoids the auth-race bug where
/// setup ran before `.notDetermined` → granted resolved.
@Observable
@MainActor
class BarcodeScanner: NSObject {
    var scannedCode: String?
    var isAuthorized = false
    var errorMessage: String?

    let captureSession = AVCaptureSession()
    private var isSetup = false

    /// Async entry point: request permission (if needed), configure session, start running.
    func start() async {
        await ensureAuthorized()
        guard isAuthorized else { return }
        if !isSetup { setupSession() }
        guard isSetup else { return }
        startRunning()
    }

    func stop() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
    }

    /// Reset after a successful scan so the next `.onAppear` scans again.
    func resetForRescan() {
        scannedCode = nil
    }

    private func startRunning() {
        guard !captureSession.isRunning else { return }
        captureSession.startRunning()
    }

    private func ensureAuthorized() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            if !granted {
                errorMessage = "Camera access is required to scan barcodes."
            }
        case .denied, .restricted:
            isAuthorized = false
            errorMessage = "Camera access denied. Enable it in Settings."
        @unknown default:
            break
        }
    }

    private func setupSession() {
        captureSession.beginConfiguration()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            errorMessage = "Unable to access camera."
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else {
            errorMessage = "Unable to set up barcode scanning."
            captureSession.commitConfiguration()
            return
        }

        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .code93, .qr, .pdf417, .itf14]

        captureSession.commitConfiguration()
        isSetup = true
    }
}

extension BarcodeScanner: @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = metadata.stringValue,
              scannedCode == nil else { return }

        Haptics.logFood()
        scannedCode = code
        stop()
    }
}
#endif
