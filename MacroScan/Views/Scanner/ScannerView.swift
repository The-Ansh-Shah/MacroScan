import SwiftUI
import SwiftData
import AVFoundation

#if canImport(UIKit)
struct ScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = BarcodeScanner()
    @State private var lookupResult: Food?
    @State private var isVerifiedResult: Bool = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showNotFoundAlert = false
    @State private var showingManualEntry = false
    @State private var conflictLocalFood: Food?
    @State private var conflictFatSecretFood: Food?
    @State private var showConflictAlert = false

    private let fatSecretAPI = FatSecretAPI()

    var body: some View {
        NavigationStack {
            ZStack {
                if scanner.isAuthorized {
                    CameraPreviewView(session: scanner.captureSession)
                        .ignoresSafeArea()

                    VStack {
                        Spacer()

                        RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                            .stroke(Color.mAccent, lineWidth: 3)
                            .frame(width: 280, height: 140)

                        Spacer()

                        if isLoading {
                            VStack(spacing: Spacing.sm) {
                                ProgressView()
                                Text("Looking up product...")
                                    .font(.mBody)
                                    .foregroundStyle(Color.mTextPrimary)
                            }
                            .padding(Spacing.md)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius))
                            .transition(.scale.combined(with: .opacity))
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
            .task {
                await scanner.start()
            }
            .onDisappear {
                scanner.stop()
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
                    scanner.resetForRescan()
                    Task { await scanner.start() }
                }
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Product Not Found", isPresented: $showNotFoundAlert) {
                Button("Log Manually") {
                    showingManualEntry = true
                }
                Button("Try Another", role: .cancel) {
                    scanner.resetForRescan()
                    Task { await scanner.start() }
                }
            } message: {
                Text("This barcode wasn't found in FatSecret. Log it manually or scan a different product.")
            }
            .alert("Nutrition Conflict", isPresented: $showConflictAlert) {
                Button("Use Local") {
                    if let local = conflictLocalFood {
                        isVerifiedResult = false
                        lookupResult = local
                    }
                    conflictLocalFood = nil
                    conflictFatSecretFood = nil
                }
                Button("Use FatSecret") {
                    if let fs = conflictFatSecretFood {
                        modelContext.insert(fs)
                        isVerifiedResult = false
                        lookupResult = fs
                    }
                    conflictLocalFood = nil
                    conflictFatSecretFood = nil
                }
                Button("Cancel", role: .cancel) {
                    conflictLocalFood = nil
                    conflictFatSecretFood = nil
                    scanner.resetForRescan()
                    Task { await scanner.start() }
                }
            } message: {
                let localCal = Int(conflictLocalFood?.calories ?? 0)
                let fsCal = Int(conflictFatSecretFood?.calories ?? 0)
                return Text("Local: \(localCal) cal • FatSecret: \(fsCal) cal — pick one.")
            }
            .sheet(item: $lookupResult, onDismiss: {
                isVerifiedResult = false
                scanner.resetForRescan()
                Task { await scanner.start() }
            }) { food in
                ScanResultSheet(food: food, isVerified: isVerifiedResult)
            }
            .sheet(isPresented: $showingManualEntry, onDismiss: {
                scanner.resetForRescan()
                Task { await scanner.start() }
            }) {
                ManualFoodForm()
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        let repo = FoodRepository(modelContext: modelContext)

        // Rate limit check
        if let profile = repo.userProfile() {
            if let resetAt = profile.fatSecretCallsResetAt,
               !Calendar.current.isDateInToday(resetAt) {
                profile.fatSecretCallsToday = 0
            }
            if profile.fatSecretCallsToday >= 4500 {
                errorMessage = "Daily lookup limit reached. Search for the item manually instead."
                return
            }
        }

        isLoading = true

        // Check local DB
        if let existing = repo.findByBarcode(code) {
            if existing.userVerified {
                // Verified food: use directly without fetching
                isLoading = false
                isVerifiedResult = true
                lookupResult = existing
                return
            }
            // Unverified local food: fetch FatSecret to compare calories
            Task {
                do {
                    let fetched = try await fatSecretAPI.barcodeLookup(barcode: code)
                    await MainActor.run {
                        incrementCallCounter(repo: repo)
                        isLoading = false
                        if abs(existing.calories - fetched.calories) > 5 {
                            conflictLocalFood = existing
                            conflictFatSecretFood = fetched
                            showConflictAlert = true
                        } else {
                            isVerifiedResult = false
                            lookupResult = existing
                        }
                    }
                } catch {
                    // Any error (not found, network, etc.) — fall back to local
                    await MainActor.run {
                        isLoading = false
                        isVerifiedResult = false
                        lookupResult = existing
                    }
                }
            }
            return
        }

        // No local food: fetch FatSecret
        Task {
            do {
                let food = try await fatSecretAPI.barcodeLookup(barcode: code)
                await MainActor.run {
                    incrementCallCounter(repo: repo)
                    modelContext.insert(food)
                    isLoading = false
                    isVerifiedResult = false
                    lookupResult = food
                }
            } catch FatSecretAPI.FatSecretError.notFound {
                await MainActor.run {
                    isLoading = false
                    showNotFoundAlert = true
                }
            } catch FatSecretAPI.FatSecretError.rateLimited {
                await MainActor.run {
                    markRateLimited(repo: repo)
                    isLoading = false
                    showNotFoundAlert = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func incrementCallCounter(repo: FoodRepository) {
        guard let profile = repo.userProfile() else { return }
        profile.fatSecretCallsToday += 1
        profile.fatSecretCallsResetAt = Date()
    }

    private func markRateLimited(repo: FoodRepository) {
        guard let profile = repo.userProfile() else { return }
        profile.fatSecretCallsToday = 5000
        profile.fatSecretCallsResetAt = Date()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// UIKit camera preview wrapped for SwiftUI.
/// Uses a subclassed UIView so the preview layer auto-resizes via layoutSubviews.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}
}

final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
#endif
