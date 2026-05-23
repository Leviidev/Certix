import SwiftUI
import PhotosUI
import UIKit

struct SigningView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    var preselectedIPA: IPAFile? = nil

    @State private var selectedCertID: UUID? = nil
    @State private var selectedIPAID: UUID? = nil
    @State private var isSigning = false
    @State private var errorMessage: String? = nil
    @State private var signedJob: SigningJob? = nil
    @State private var currentJobID: UUID? = nil
    @State private var showAdvanced = false
    @State private var options = SigningOptions()
    @State private var iconPickerItem: PhotosPickerItem? = nil
    @State private var customIconPreview: UIImage? = nil

    var selectedCert: Certificate? { store.certificates.first(where: { $0.id == selectedCertID }) }
    var selectedIPA: IPAFile? { store.ipas.first(where: { $0.id == selectedIPAID }) }
    var canSign: Bool { selectedCertID != nil && selectedIPAID != nil && !isSigning }

    var currentProgress: Double {
        guard let id = currentJobID else { return 0 }
        return store.signingJobs.first(where: { $0.id == id })?.progress ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                certSection
                ipaSection
                customizationSection

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.caption)
                    }
                }

                if isSigning {
                    signingProgressSection
                    terminalSection
                }

                if !isSigning && canSign { signSection }
            }
            .navigationTitle("Sign App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSigning)
                }
            }
            .onAppear {
                if let pre = preselectedIPA { selectedIPAID = pre.id }
                if selectedCertID == nil, let first = store.certificates.first(where: { !$0.isExpired }) {
                    selectedCertID = first.id
                }
            }
        }
        .sheet(item: $signedJob) { job in
            InstallView(job: job).environmentObject(store)
        }
        .interactiveDismissDisabled(isSigning)
        .task(id: iconPickerItem) {
            guard let item = iconPickerItem else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                options.customIconData = data
                customIconPreview = UIImage(data: data)
            }
        }
    }

    private var certSection: some View {
        Section {
            if store.certificates.isEmpty {
                Label("No certificates imported", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange).font(.subheadline)
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
                    .foregroundStyle(.orange).font(.subheadline)
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
                Text("\(ipa.bundleID) · \(ipa.fileSizeFormatted)").foregroundStyle(.secondary)
            }
        }
    }

    private var customizationSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Bundle ID")
                            .font(.subheadline).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        TextField("com.yourteam.appname", text: $options.customBundleID)
                            .font(.subheadline)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 8)

                    Divider()

                    HStack {
                        Text("App Name")
                            .font(.subheadline).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        TextField("Leave blank to keep original", text: $options.customAppName)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 8)

                    Divider()

                    HStack {
                        Text("Version")
                            .font(.subheadline).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        TextField("e.g. 2.0.0", text: $options.customVersion)
                            .font(.subheadline)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    .padding(.vertical, 8)

                    Divider()

                    HStack(spacing: 12) {
                        Text("Icon")
                            .font(.subheadline).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)

                        if let preview = customIconPreview {
                            Image(uiImage: preview)
                                .resizable().scaledToFill()
                                .frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }

                        PhotosPicker(selection: $iconPickerItem, matching: .images) {
                            Text(options.hasIconOverride ? "Change Icon" : "Pick Icon")
                                .font(.subheadline).foregroundStyle(.blue)
                        }

                        if options.hasIconOverride {
                            Spacer()
                            Button("Remove") {
                                options.customIconData = nil
                                customIconPreview = nil
                                iconPickerItem = nil
                            }
                            .font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } label: {
                Label("Customization", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
            }
        } header: {
            Label("Options", systemImage: "gearshape")
        } footer: {
            Text("Leave fields blank to keep original values from the IPA.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var signingProgressSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    Text(progressLabel).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(currentProgress * 100))%")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.blue).monospacedDigit()
                }
                ProgressView(value: currentProgress).tint(.blue)
                    .animation(.easeInOut(duration: 0.3), value: currentProgress)
            }
            .padding(.vertical, 4)
        } header: {
            Label("Signing in Progress", systemImage: "signature")
        }
    }

    private var terminalSection: some View {
        Section {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(store.activeJobLogs.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(terminalLineColor(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 180)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: store.activeJobLogs.count) { count in
                    if let last = store.activeJobLogs.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } header: {
            Label("Build Log", systemImage: "terminal.fill")
        }
    }

    private var signSection: some View {
        Section {
            Button { startSigning() } label: {
                HStack {
                    Spacer()
                    Label("Sign App", systemImage: "signature").font(.headline)
                    Spacer()
                }
            }
            .disabled(!canSign)
            .listRowBackground(canSign ? Color.blue : Color.blue.opacity(0.4))
            .foregroundStyle(.white)
        }
    }

    private var progressLabel: String {
        switch currentProgress {
        case 0 ..< 0.1:    return "Loading certificate..."
        case 0.1 ..< 0.25: return "Extracting IPA..."
        case 0.25 ..< 0.45: return "Analyzing app bundle..."
        case 0.45 ..< 0.9: return "Signing binaries..."
        case 0.9 ..< 1.0:  return "Repackaging..."
        default:            return "Complete"
        }
    }

    private func terminalLineColor(for line: String) -> Color {
        if line.contains("✓") { return Color.green }
        if line.contains("✗") || line.contains("Error") { return Color.red }
        if line.contains("⚠") { return Color.yellow }
        return Color.green.opacity(0.85)
    }

    private func startSigning() {
        guard let certID = selectedCertID, let ipaID = selectedIPAID,
              let cert = selectedCert, let ipa = selectedIPA else { return }

        isSigning = true
        errorMessage = nil

        let job = SigningJob(
            ipaID: ipaID, certificateID: certID,
            ipaName: ipa.name, certificateName: cert.name,
            status: .queued, progress: 0, dateCreated: Date()
        )
        currentJobID = job.id
        store.addSigningJob(job)

        let capturedOptions = options

        Task {
            await SigningService.shared.sign(job: job, store: store, options: capturedOptions)
            await MainActor.run {
                isSigning = false
                if let updated = store.signingJobs.first(where: { $0.id == job.id }) {
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
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cert.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(cert.teamName).font(.caption).foregroundStyle(.secondary)
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
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.systemGray5)).frame(width: 34, height: 34)
                    if let icon {
                        Image(uiImage: icon).resizable().scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 16, weight: .light)).foregroundStyle(.quaternary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ipa.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text("v\(ipa.version) · \(ipa.fileSizeFormatted)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .onAppear { icon = IPAService.shared.loadIcon(for: ipa) }
    }
}
