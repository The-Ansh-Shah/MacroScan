import AVFoundation
import SwiftUI

#if canImport(UIKit)
/// AVFoundation-based barcode scanner using the camera
class BarcodeScanner: NSObject, ObservableObject {
    @Published var scannedCode: String?
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    let captureSession = AVCaptureSession()
    private var isSetup = false

    override init() {
        super.init()
        checkAuthorization()
    }

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.isAuthorized = granted
                    if !granted {
                        self?.errorMessage = "Camera access is required to scan barcodes."
                    }
                }
            }
        case .denied, .restricted:
            isAuthorized = false
            errorMessage = "Camera access denied. Enable it in Settings."
        @unknown default:
            break
        }
    }

    func setupSession() {
        guard !isSetup, isAuthorized else { return }

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
        output.metadataObjectTypes = [.ean8, .ean13, .upce]

        captureSession.commitConfiguration()
        isSetup = true
    }

    func startScanning() {
        guard isSetup else { return }
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    func stopScanning() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}

extension BarcodeScanner: AVCaptureMetadataOutputObjectsDelegate {
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
        stopScanning()
    }
}
#endif
