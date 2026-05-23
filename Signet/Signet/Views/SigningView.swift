import SwiftUI

struct SigningView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    var preselectedIPA: IPAFile? = nil

    @State private var selectedCertID: UUID? = nil
    @State private var selectedIPAID: UUID? = nil
    @State private var isSigning = false
    @State private var signingProgress: Double = 0
    @State private var errorMessage: String? = nil
    @State private var signedJob: SigningJob? = nil

    var selectedCert: Certificate? {
        store.certificates.first(where: { $0.id == selectedCertID })
    }

    var selectedIPA: IPAFile? {
        store.ipas.first(where: { $0.id == selectedIPAID })
    }

    var canSign: Bool {
        selectedCertID != nil && selectedIPAID != nil && !isSigning
    }

    var body: some View {
        NavigationStack {
            Form {
                certSection
                ipaSection

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if isSigning {
                    signingProgressSection
                }

                if !isSigning && canSign {
                    signSection
                }
            }
            .navigationTitle("Sign App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSigning)
                }
            }
            .onAppear {
                if let pre = preselectedIPA {
                    selectedIPAID = pre.id
                }
                if selectedCertID == nil, let first = store.certificates.first(where: { !$0.isExpired }) {
                    selectedCertID = first.id
                }
            }
        }
        .sheet(item: $signedJob) { job in
            InstallView(job: job)
                .environmentObject(store)
        }
        .interactiveDismissDisabled(isSigning)
    }

    private var certSection: some View {
        Section {
            if store.certificates.isEmpty {
                Label("No certificates imported", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            } else {
                ForEach(store.certificates) { cert in
                    CertPickerRow(cert: cert, isSelected: cert.id == selectedCertID) {
                        selectedCertID = cert.id
                    }
                }
            }
        } header: {
            Label("Certificate", systemImage: "lock.shield.fill")
        } footer: {
            if let cert = selectedCert {
                Text("Expires \(cert.expiryDate.formatted(date: .abbreviated, time: .omitted)) · \(cert.teamID)")
                    .foregroundStyle(cert.isExpired ? .red : .secondary)
            }
        }
    }

    private var ipaSection: some View {
        Section {
            if store.ipas.isEmpty {
                Label("No apps imported", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            } else {
                ForEach(store.ipas) { ipa in
                    IPAPickerRow(ipa: ipa, isSelected: ipa.id == selectedIPAID) {
                        selectedIPAID = ipa.id
                    }
                }
            }
        } header: {
            Label("App", systemImage: "square.stack.3d.up.fill")
        } footer: {
            if let ipa = selectedIPA {
                Text("\(ipa.bundleID) · \(ipa.fileSizeFormatted)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var signingProgressSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    Text(signingProgressLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(signingProgress * 100))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                }

                ProgressView(value: signingProgress)
                    .tint(.blue)
                    .animation(.easeInOut(duration: 0.3), value: signingProgress)
            }
            .padding(.vertical, 4)
        } header: {
            Label("Signing in Progress", systemImage: "signature")
        }
    }

    private var signingProgressLabel: String {
        switch signingProgress {
        case 0 ..< 0.1:  return "Loading certificate..."
        case 0.1 ..< 0.25: return "Extracting IPA..."
        case 0.25 ..< 0.45: return "Analyzing app bundle..."
        case 0.45 ..< 0.9: return "Signing binary..."
        case 0.9 ..< 1.0: return "Repackaging..."
        default:           return "Complete"
        }
    }

    private var signSection: some View {
        Section {
            Button {
                startSigning()
            } label: {
                HStack {
                    Spacer()
                    Label("Sign App", systemImage: "signature")
                        .font(.headline)
                    Spacer()
                }
            }
            .disabled(!canSign)
            .listRowBackground(canSign ? Color.blue : Color.blue.opacity(0.4))
            .foregroundStyle(.white)
        }
    }

    private func startSigning() {
        guard let certID = selectedCertID,
              let ipaID = selectedIPAID,
              let cert = selectedCert,
              let ipa = selectedIPA else { return }

        isSigning = true
        errorMessage = nil
        signingProgress = 0

        var job = SigningJob(
            ipaID: ipaID,
            certificateID: certID,
            ipaName: ipa.name,
            certificateName: cert.name,
            status: .queued,
            progress: 0,
            dateCreated: Date()
        )
        store.addSigningJob(job)

        Task {
            await SigningService.shared.sign(job: job, store: store)

            await MainActor.run {
                isSigning = false
                if let updated = store.signingJobs.first(where: { $0.id == job.id }) {
                    job = updated
                    if updated.status == .completed {
                        signedJob = updated
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            signedJob = updated
                        }
                    } else if updated.status == .failed {
                        errorMessage = updated.errorMessage ?? "Signing failed"
                    }
                }
            }
        }

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if let updated = store.signingJobs.first(where: { $0.id == job.id }) {
                signingProgress = updated.progress
                if updated.status == .completed || updated.status == .failed {
                    timer.invalidate()
                }
            }
        }
    }
}

struct CertPickerRow: View {
    let cert: Certificate
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .blue : .tertiaryLabel)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cert.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(cert.teamName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                CertExpiryBadge(cert: cert)
            }
        }
        .buttonStyle(.plain)
    }
}

struct IPAPickerRow: View {
    let ipa: IPAFile
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var icon: UIImage? = nil

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .blue : .tertiaryLabel)

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(width: 34, height: 34)
                    if let icon {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(.quaternary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(ipa.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("v\(ipa.version) · \(ipa.fileSizeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .onAppear { icon = IPAService.shared.loadIcon(for: ipa) }
    }
}
