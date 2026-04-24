import SwiftUI
import AVFoundation

#if canImport(UIKit)
struct ScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = BarcodeScanner()
    @State private var lookupResult: Food?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let offAPI = OpenFoodFactsAPI()

    var body: some View {
        NavigationStack {
            ZStack {
                if scanner.isAuthorized {
                    CameraPreviewView(session: scanner.captureSession)
                        .ignoresSafeArea()

                    // Scan overlay
                    VStack {
                        Spacer()

                        RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                            .stroke(Color.mAccent, lineWidth: 3)
                            .frame(width: 280, height: 140)

                        Spacer()

                        if isLoading {
                            ProgressView("Looking up product...")
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius))
                        }

                        Spacer()
                            .frame(height: Spacing.xxl)
                    }
                } else {
                    EmptyStateView(
                        symbol: "camera.fill",
                        message: scanner.errorMessage ?? "Camera access needed to scan barcodes.",
                        buttonTitle: "Open Settings",
                        action: openSettings
                    )
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                scanner.setupSession()
                scanner.startScanning()
            }
            .onDisappear {
                scanner.stopScanning()
            }
            .onChange(of: scanner.scannedCode) { _, code in
                guard let code else { return }
                handleScannedCode(code)
            }
            .alert("Scan Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Try Again") {
                    scanner.scannedCode = nil
                    scanner.startScanning()
                }
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $lookupResult) { food in
                ScanResultSheet(food: food)
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        isLoading = true
        let repo = FoodRepository(modelContext: modelContext)

        // Check local DB first
        if let existing = repo.findByBarcode(code) {
            isLoading = false
            lookupResult = existing
            return
        }

        Task {
            do {
                let food = try await offAPI.lookup(barcode: code)
                await MainActor.run {
                    modelContext.insert(food)
                    isLoading = false
                    lookupResult = food
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// UIKit camera preview wrapped for SwiftUI
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
#endif
