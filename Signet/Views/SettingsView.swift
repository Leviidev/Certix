import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var serverPort: String = "8080"
    @State private var showClearAlert = false
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.blue).frame(width: 50, height: 50)
                            Image(systemName: "signature")
                                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Certix").font(.title3.weight(.bold))
                            Text("Version 1.0").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack {
                        Label("Server Port", systemImage: "network")
                        Spacer()
                        TextField("8080", text: $serverPort)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .foregroundStyle(.secondary)
                            .frame(width: 70)
                    }
                } header: { Text("Local Server") }
                  footer: { Text("Port used for OTA installation server. Default: 8080") }

                Section {
                    StatsRow(label: "Certificates", value: "\(store.certificates.count)", icon: "lock.shield.fill", color: .blue)
                    StatsRow(label: "Apps", value: "\(store.ipas.count)", icon: "square.stack.3d.up.fill", color: .purple)
                    StatsRow(label: "Signed Jobs", value: "\(store.signingJobs.count)", icon: "checkmark.seal.fill", color: .green)
                    StatsRow(label: "Successful", value: "\(store.completedJobs.count)", icon: "star.fill", color: .yellow)
                } header: { Text("Statistics") }

                Section {
                    Button { showGuide = true } label: {
                        Label("How to Use Certix", systemImage: "questionmark.circle")
                    }
                    Link(destination: URL(string: "https://github.com/your-repo/signet")!) {
                        Label("GitHub Repository", systemImage: "link")
                    }
                } header: { Text("About") }

                Section {
                    Button(role: .destructive) { showClearAlert = true } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                } footer: {
                    Text("Removes all certificates, apps, and signing history. This cannot be undone.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Clear All Data?", isPresented: $showClearAlert) {
            Button("Clear Everything", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all certificates, imported apps, and signing history.")
        }
        .sheet(isPresented: $showGuide) { HowToUseGuide() }
    }

    private func clearAll() {
        for cert in store.certificates { store.removeCertificate(cert) }
        for ipa in store.ipas { store.removeIPA(ipa) }
        for job in store.signingJobs { store.removeSigningJob(job) }
    }
}

struct StatsRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Label(label, systemImage: icon).foregroundStyle(color)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

struct HowToUseGuide: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Step 1: Import Certificates") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Export your developer certificate from Keychain Access on Mac as a .p12 file with a password.")
                            .font(.subheadline)
                        Text("Optionally include a .mobileprovision file for provisioning.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section("Step 2: Import IPAs") {
                    Text("Import IPA files you want to sign.")
                        .font(.subheadline).padding(.vertical, 4)
                }
                Section("Step 3: Sign Apps") {
                    Text("Go to an imported IPA, tap Sign, select your certificate, and tap Sign App.")
                        .font(.subheadline).padding(.vertical, 4)
                }
                Section("Step 4: Install") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("After signing, tap Install to start the local server.")
                            .font(.subheadline)
                        Text("Tap \"Install on This Device\" or scan the QR code from another device on the same Wi-Fi.")
                            .font(.subheadline)
                        Text("Trust the developer certificate in Settings → General → VPN & Device Management.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section("Requirements") {
                    Label("iOS 16.0 or later", systemImage: "iphone")
                    Label("Valid developer certificate", systemImage: "lock.shield")
                    Label("Same Wi-Fi for QR code installs", systemImage: "wifi")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("How to Use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
