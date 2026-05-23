import SwiftUI
import UniformTypeIdentifiers

struct CertificatesView: View {
    @EnvironmentObject var store: AppStore
    @State private var showImport = false
    @State private var selectedCert: Certificate? = nil
    @State private var certToDelete: Certificate? = nil
    @State private var showDeleteAlert = false
    @State private var errorMessage: String? = nil
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Group {
                if store.certificates.isEmpty {
                    EmptyStateView(
                        systemImage: "lock.shield",
                        title: "No Certificates",
                        message: "Import a .p12 certificate to start signing apps.",
                        action: { showImport = true },
                        actionLabel: "Import Certificate"
                    )
                } else {
                    List {
                        ForEach(store.certificates) { cert in
                            CertificateRow(cert: cert)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedCert = cert }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        certToDelete = cert
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Certificates")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImport = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportCertificateSheet().environmentObject(store)
        }
        .sheet(item: $selectedCert) { cert in
            CertificateDetailView(cert: cert).environmentObject(store)
        }
        .alert("Delete Certificate?", isPresented: $showDeleteAlert, presenting: certToDelete) { cert in
            Button("Delete", role: .destructive) { store.removeCertificate(cert) }
            Button("Cancel", role: .cancel) {}
        } message: { cert in
            Text(""\(cert.name)" will be permanently removed.")
        }
    }
}

struct CertificateRow: View {
    let cert: Certificate

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cert.expiryStatus == .valid ? Color.blue : cert.expiryStatus == .expiringSoon ? Color.orange : Color.red)
                    .frame(width: 44, height: 44)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(cert.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(cert.teamName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("Expires \(cert.expiryDate.formatted(.dateTime.month().day().year()))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            CertExpiryBadge(cert: cert)
        }
        .padding(.vertical, 2)
    }
}

struct ImportCertificateSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var p12URL: URL? = nil
    @State private var profileURL: URL? = nil
    @State private var password: String = ""
    @State private var isImporting = false
    @State private var errorMessage: String? = nil
    @State private var showP12Picker = false
    @State private var showProfilePicker = false

    var canImport: Bool { p12URL != nil && !password.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let url = p12URL {
                        HStack {
                            Label(url.lastPathComponent, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).lineLimit(1)
                            Spacer()
                            Button("Change") { showP12Picker = true }.font(.caption)
                        }
                    } else {
                        Button { showP12Picker = true } label: {
                            Label("Select .p12 File", systemImage: "doc.badge.plus")
                        }
                    }
                } header: { Text("Certificate (.p12)") }
                  footer: { Text("Your signing certificate exported from Keychain.") }

                Section("Password") {
                    SecureField("Certificate Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    if let url = profileURL {
                        HStack {
                            Label(url.lastPathComponent, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).lineLimit(1)
                            Spacer()
                            Button("Change") { showProfilePicker = true }.font(.caption)
                        }
                    } else {
                        Button { showProfilePicker = true } label: {
                            Label("Select .mobileprovision (optional)", systemImage: "doc.badge.plus")
                        }
                    }
                } header: { Text("Provisioning Profile") }
                  footer: { Text("Required for installing on non-jailbroken devices.") }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Import Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView().tint(.blue)
                    } else {
                        Button("Import") { importCertificate() }
                            .fontWeight(.semibold)
                            .disabled(!canImport)
                    }
                }
            }
        }
        .fileImporter(isPresented: $showP12Picker,
                      allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data]) { result in
            if case .success(let url) = result { p12URL = url }
        }
        .fileImporter(isPresented: $showProfilePicker,
                      allowedContentTypes: [UTType(filenameExtension: "mobileprovision") ?? .data]) { result in
            if case .success(let url) = result { profileURL = url }
        }
    }

    private func importCertificate() {
        guard let p12URL else { return }
        isImporting = true
        errorMessage = nil
        Task {
            do {
                let cert = try await CertificateService.shared.importCertificate(
                    p12URL: p12URL, password: password, profileURL: profileURL, store: store
                )
                await MainActor.run {
                    store.addCertificate(cert)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

struct CertificateDetailView: View {
    let cert: Certificate
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(cert.expiryStatus == .valid ? Color.blue : .orange)
                                    .frame(width: 64, height: 64)
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            Text(cert.name).font(.title3.weight(.bold))
                            CertExpiryBadge(cert: cert)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }

                Section("Certificate Info") {
                    DetailRow(label: "Team Name", value: cert.teamName)
                    DetailRow(label: "Team ID", value: cert.teamID)
                    DetailRow(label: "Serial Number", value: cert.serialNumber)
                    DetailRow(label: "Expires", value: cert.expiryDate.formatted(date: .abbreviated, time: .omitted))
                    DetailRow(label: "Days Remaining", value: cert.isExpired ? "Expired" : "\(cert.daysUntilExpiry) days")
                }

                Section("Files") {
                    DetailRow(label: "P12 File", value: cert.p12FileName)
                    if let profile = cert.profileFileName {
                        DetailRow(label: "Profile", value: profile)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.removeCertificate(cert)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Certificate", systemImage: "trash").font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}
