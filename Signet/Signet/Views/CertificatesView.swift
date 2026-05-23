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
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportCertificateSheet()
                .environmentObject(store)
        }
        .sheet(item: $selectedCert) { cert in
            CertificateDetailView(cert: cert)
                .environmentObject(store)
        }
        .alert("Delete Certificate?", isPresented: $showDeleteAlert, presenting: certToDelete) { cert in
            Button("Delete", role: .destructive) {
                store.removeCertificate(cert)
            }
            Button("Cancel", role: .cancel) {}
        } message: { cert in
            Text(""\(cert.name)" will be permanently removed.")
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
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
                Text(cert.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(cert.teamName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Expires \(cert.expiryDate.formatted(.dateTime.month().day().year()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                                .foregroundStyle(.green)
                                .lineLimit(1)
                            Spacer()
                            Button("Change") { showP12Picker = true }
                                .font(.caption)
                        }
                    } else {
                        Button {
                            showP12Picker = true
                        } label: {
                            Label("Select .p12 File", systemImage: "doc.badge.plus")
                        }
                    }
                } header: {
                    Text("Certificate (.p12)")
                } footer: {
                    Text("Your signing certificate exported from Keychain.")
                }

                Section {
                    SecureField("Certificate Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Password")
                }

                Section {
                    if let url = profileURL {
                        HStack {
                            Label(url.lastPathComponent, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .lineLimit(1)
                            Spacer()
                            Button("Change") { showProfilePicker = true }
                                .font(.caption)
                            Button("Remove") { profileURL = nil }
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            showProfilePicker = true
                        } label: {
                            Label("Select .mobileprovision (Optional)", systemImage: "doc.badge.plus")
                        }
                    }
                } header: {
                    Text("Provisioning Profile")
                } footer: {
                    Text("Required for non-developer builds.")
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Import Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button("Import") {
                            performImport()
                        }
                        .disabled(!canImport)
                        .fontWeight(.semibold)
                    }
                }
            }
            .fileImporter(
                isPresented: $showP12Picker,
                allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data]
            ) { result in
                if case .success(let url) = result { p12URL = url }
            }
            .fileImporter(
                isPresented: $showProfilePicker,
                allowedContentTypes: [UTType(filenameExtension: "mobileprovision") ?? .data]
            ) { result in
                if case .success(let url) = result { profileURL = url }
            }
        }
    }

    private func performImport() {
        guard let p12 = p12URL else { return }
        isImporting = true
        errorMessage = nil

        Task {
            do {
                let cert = try await CertificateService.shared.importCertificate(
                    p12URL: p12,
                    password: password,
                    profileURL: profileURL,
                    store: store
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
                Section("Identity") {
                    DetailRow(label: "Name", value: cert.name)
                    DetailRow(label: "Team", value: cert.teamName)
                    DetailRow(label: "Team ID", value: cert.teamID)
                    DetailRow(label: "Serial", value: cert.serialNumber)
                }
                Section("Validity") {
                    HStack {
                        Text("Status")
                            .foregroundStyle(.secondary)
                        Spacer()
                        CertExpiryBadge(cert: cert)
                    }
                    DetailRow(label: "Created", value: cert.creationDate.formatted(date: .abbreviated, time: .omitted))
                    DetailRow(label: "Expires", value: cert.expiryDate.formatted(date: .abbreviated, time: .omitted))
                    if !cert.isExpired {
                        DetailRow(label: "Days Left", value: "\(cert.daysUntilExpiry) days")
                    }
                }
                Section("Files") {
                    DetailRow(label: "Certificate", value: cert.p12FileName)
                    if let profile = cert.profileFileName {
                        DetailRow(label: "Profile", value: profile)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
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
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.subheadline)
    }
}
