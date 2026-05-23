import SwiftUI
import UniformTypeIdentifiers

struct IPAsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showImport = false
    @State private var isImporting = false
    @State private var selectedIPA: IPAFile? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var showSigningSheet = false
    @State private var ipaToSign: IPAFile? = nil

    var body: some View {
        NavigationStack {
            Group {
                if store.ipas.isEmpty {
                    EmptyStateView(
                        systemImage: "square.stack.3d.up",
                        title: "No Apps",
                        message: "Import IPA files to sign and install.",
                        action: { showImport = true },
                        actionLabel: "Import IPA"
                    )
                } else {
                    List {
                        ForEach(store.ipas) { ipa in
                            IPARow(ipa: ipa)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedIPA = ipa }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        store.removeIPA(ipa)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        ipaToSign = ipa
                                        showSigningSheet = true
                                    } label: {
                                        Label("Sign", systemImage: "signature")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .overlay {
                        if isImporting {
                            ZStack {
                                Color.black.opacity(0.3).ignoresSafeArea()
                                VStack(spacing: 12) {
                                    ProgressView().tint(.white).scaleEffect(1.5)
                                    Text("Importing…").foregroundStyle(.white).font(.subheadline)
                                }
                                .padding(24)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Apps")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImport = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImport,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]
        ) { result in
            if case .success(let url) = result { importIPA(from: url) }
        }
        .sheet(item: $selectedIPA) { ipa in
            IPADetailView(ipa: ipa).environmentObject(store)
        }
        .sheet(isPresented: $showSigningSheet) {
            SigningView(preselectedIPA: ipaToSign).environmentObject(store)
        }
        .alert("Import Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    private func importIPA(from url: URL) {
        isImporting = true
        Task {
            do {
                let ipa = try await IPAService.shared.importIPA(from: url, store: store)
                await MainActor.run {
                    store.addIPA(ipa)
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isImporting = false
                }
            }
        }
    }
}

struct IPARow: View {
    let ipa: IPAFile
    @State private var icon: UIImage? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                if let icon {
                    Image(uiImage: icon)
                        .resizable().scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 24, weight: .light)).foregroundStyle(.quaternary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(ipa.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(ipa.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text("v\(ipa.version) (\(ipa.buildNumber))").font(.caption2).foregroundStyle(.tertiary)
                    Text("·").font(.caption2).foregroundStyle(.quaternary)
                    Text(ipa.fileSizeFormatted).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiaryLabel)
        }
        .padding(.vertical, 4)
        .onAppear { icon = IPAService.shared.loadIcon(for: ipa) }
    }
}

struct IPADetailView: View {
    let ipa: IPAFile
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var showSigningSheet = false
    @State private var icon: UIImage? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(.systemGray5)).frame(width: 80, height: 80)
                                if let icon {
                                    Image(uiImage: icon)
                                        .resizable().scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                } else {
                                    Image(systemName: "app.fill")
                                        .font(.system(size: 36, weight: .light)).foregroundStyle(.quaternary)
                                }
                            }
                            Text(ipa.name).font(.title3.weight(.semibold))
                            Text("v\(ipa.version) (\(ipa.buildNumber))").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }

                Section("App Info") {
                    DetailRow(label: "Bundle ID", value: ipa.bundleID)
                    DetailRow(label: "Version", value: "\(ipa.version) (\(ipa.buildNumber))")
                    DetailRow(label: "Min. iOS", value: "iOS \(ipa.minimumOSVersion)+")
                    DetailRow(label: "Size", value: ipa.fileSizeFormatted)
                    DetailRow(label: "Added", value: ipa.dateAdded.formatted(date: .abbreviated, time: .shortened))
                }

                Section {
                    Button { showSigningSheet = true } label: {
                        HStack {
                            Spacer()
                            Label("Sign This App", systemImage: "signature").font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                    .disabled(store.certificates.isEmpty)

                    Button(role: .destructive) {
                        store.removeIPA(ipa)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete IPA", systemImage: "trash").font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("App Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { icon = IPAService.shared.loadIcon(for: ipa) }
        }
        .sheet(isPresented: $showSigningSheet) {
            SigningView(preselectedIPA: ipa).environmentObject(store)
        }
    }
}
