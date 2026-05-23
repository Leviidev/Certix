import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSigningSheet = false
    @State private var selectedJob: SigningJob? = nil
    @State private var showAllSigned = false
    @State private var shareURL: URL? = nil
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statsRow
                    signedAppsSection
                    recentActivitySection
                    quickActionsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Certix")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSigningSheet = true
                    } label: {
                        Image(systemName: "signature")
                            .fontWeight(.medium)
                    }
                    .disabled(store.certificates.isEmpty || store.ipas.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showSigningSheet) {
            SigningView()
                .environmentObject(store)
        }
        .sheet(item: $selectedJob) { job in
            InstallView(job: job)
                .environmentObject(store)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(store.certificates.count)", label: "Certificates",
                     icon: "lock.shield.fill", color: .blue)
            StatCard(value: "\(store.ipas.count)", label: "Apps",
                     icon: "square.stack.3d.up.fill", color: .purple)
            StatCard(value: "\(store.completedJobs.count)", label: "Signed",
                     icon: "checkmark.seal.fill", color: .green)
        }
    }

    private var signedAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Signed Apps", icon: "checkmark.seal.fill")
                Spacer()
                if store.completedJobs.count > 3 {
                    Button(showAllSigned ? "Show Less" : "See All") {
                        withAnimation(.spring(response: 0.35)) { showAllSigned.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                }
            }

            if store.completedJobs.isEmpty {
                GlassCard {
                    HStack {
                        Image(systemName: "checkmark.seal").foregroundStyle(.tertiary)
                        Text("No signed apps yet")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else {
                let displayed = showAllSigned ? store.completedJobs : Array(store.completedJobs.prefix(3))
                VStack(spacing: 0) {
                    ForEach(displayed) { job in
                        SignedAppRow(job: job) {
                            selectedJob = job
                        } onShare: {
                            if let output = job.outputFileName {
                                let url = store.signingDirectory.appendingPathComponent(output)
                                shareURL = url
                                showShareSheet = true
                            }
                        }
                        if job.id != displayed.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent Activity", icon: "clock.fill")

            let activeJobs = store.signingJobs.filter { $0.status == .signing || $0.status == .queued || $0.status == .failed }

            if activeJobs.isEmpty {
                GlassCard {
                    HStack {
                        Image(systemName: "tray").foregroundStyle(.tertiary)
                        Text("No active jobs")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(activeJobs.prefix(5)) { job in
                        JobRow(job: job) {}
                        if job.id != activeJobs.prefix(5).last?.id {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick Actions", icon: "bolt.fill")

            VStack(spacing: 0) {
                QuickActionRow(icon: "signature", iconColor: .blue,
                               title: "Sign an App",
                               subtitle: store.certificates.isEmpty ? "Import a certificate first" : "Sign an IPA with a certificate") {
                    showSigningSheet = true
                }
                .disabled(store.certificates.isEmpty || store.ipas.isEmpty)

                Divider().padding(.horizontal, 16)

                QuickActionRow(icon: "plus.circle.fill", iconColor: .green,
                               title: "Add Certificate", subtitle: "Import a .p12 file") {}

                Divider().padding(.horizontal, 16)

                QuickActionRow(icon: "square.and.arrow.down.fill", iconColor: .purple,
                               title: "Import IPA", subtitle: "Add an app to sign") {}
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
        }
    }
}

struct SignedAppRow: View {
    let job: SigningJob
    let onInstall: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(job.ipaName)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(job.certificateName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let date = job.dateCompleted {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)

                Button(action: onInstall) {
                    Text("Install")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.title2.weight(.bold)).foregroundStyle(.primary)
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct JobRow: View {
    let job: SigningJob
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: job.status.systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.ipaName)
                        .font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(job.certificateName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge.forJob(job.status)
                    if job.status == .signing {
                        ProgressView(value: job.progress).frame(width: 60).tint(.blue)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch job.status {
        case .queued:     return .secondary
        case .signing:    return .blue
        case .completed:  return .green
        case .failed:     return .red
        case .installing: return .purple
        }
    }
}

struct QuickActionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
