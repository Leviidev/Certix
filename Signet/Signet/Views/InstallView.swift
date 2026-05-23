import SwiftUI

struct InstallView: View {
    let job: SigningJob
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @StateObject private var server = OTAServer.shared

    @State private var isServerStarted = false
    @State private var serverError: String? = nil
    @State private var installURL: String = ""
    @State private var isCopied = false

    var ipa: IPAFile? {
        store.ipas.first(where: { $0.id == job.ipaID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    appHeader

                    if isServerStarted {
                        installCard
                        instructionsCard
                    } else if let error = serverError {
                        errorCard(error)
                    } else {
                        startingCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Install")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        server.stop()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .task {
            await startServer()
        }
    }

    private var appHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 4) {
                Text(job.ipaName)
                    .font(.title3.weight(.bold))
                Text("Signed with \(job.certificateName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            StatusBadge.forJob(job.status)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var installCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "network")
                        .foregroundStyle(.blue)
                    Text("Local Server Running")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 4)
                }

                Divider()

                Button {
                    openInstall()
                } label: {
                    HStack {
                        Spacer()
                        Label("Install on This Device", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !installURL.isEmpty {
                    HStack {
                        Text(installURL.prefix(60) + (installURL.count > 60 ? "..." : ""))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .monospaced()

                        Spacer()

                        Button {
                            UIPasteboard.general.string = installURL
                            isCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                isCopied = false
                            }
                        } label: {
                            Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(isCopied ? .green : .blue)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private var instructionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Installation Guide", systemImage: "list.number")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 10) {
                    InstructionStep(number: 1, text: "Tap \"Install on This Device\" above")
                    InstructionStep(number: 2, text: "Safari will open with an install prompt")
                    InstructionStep(number: 3, text: "Tap \"Install\" in the popup dialog")
                    InstructionStep(number: 4, text: "Go to Settings → General → VPN & Device Management")
                    InstructionStep(number: 5, text: "Trust the developer certificate")
                    InstructionStep(number: 6, text: "Return to Home Screen to find the app")
                }

                Divider()

                Label("Keep this screen open while installing", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorCard(_ error: String) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Server Error")
                    .font(.subheadline.weight(.semibold))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await startServer() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var startingCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.blue)
                Text("Starting local server...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func startServer() async {
        do {
            try server.start(for: job, store: store)
            try await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                isServerStarted = true
                installURL = server.installURL(for: job, store: store)
            }
        } catch {
            await MainActor.run {
                serverError = error.localizedDescription
            }
        }
    }

    private func openInstall() {
        let itmsURL = server.installURL(for: job, store: store)
        if let url = URL(string: itmsURL) {
            UIApplication.shared.open(url)
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.12))
                    .frame(width: 22, height: 22)
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.blue)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
