import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSigningSheet = false
    @State private var selectedJob: SigningJob? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statsRow
                    recentJobsSection
                    quickActionsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Signet")
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
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                value: "\(store.certificates.count)",
                label: "Certificates",
                icon: "lock.shield.fill",
                color: .blue
            )
            StatCard(
                value: "\(store.ipas.count)",
                label: "Apps",
                icon: "square.stack.3d.up.fill",
                color: .purple
            )
            StatCard(
                value: "\(store.completedJobs.count)",
                label: "Signed",
                icon: "checkmark.seal.fill",
                color: .green
            )
        }
    }

    private var recentJobsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent Activity", icon: "clock.fill")

            if store.signingJobs.isEmpty {
                GlassCard {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundStyle(.tertiary)
                        Text("No signing jobs yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(store.recentJobs) { job in
                        JobRow(job: job) {
                            if job.status == .completed {
                                selectedJob = job
                            }
                        }
                        if job.id != store.recentJobs.last?.id {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick Actions", icon: "bolt.fill")

            VStack(spacing: 0) {
                QuickActionRow(
                    icon: "signature",
                    iconColor: .blue,
                    title: "Sign an App",
                    subtitle: store.certificates.isEmpty ? "Import a certificate first" : "Sign an IPA with a certificate"
                ) {
                    showSigningSheet = true
                }
                .disabled(store.certificates.isEmpty || store.ipas.isEmpty)

                Divider().padding(.horizontal, 16)

                NavigationLink(value: "certificates") {
                    QuickActionRow(
                        icon: "plus.circle.fill",
                        iconColor: .green,
                        title: "Add Certificate",
                        subtitle: "Import a .p12 file"
                    ) {}
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, 16)

                NavigationLink(value: "apps") {
                    QuickActionRow(
                        icon: "square.and.arrow.down.fill",
                        iconColor: .purple,
                        title: "Import IPA",
                        subtitle: "Add an app to sign"
                    ) {}
                }
                .buttonStyle(.plain)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            )
        }
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
                    Text(value)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(job.certificateName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge.forJob(job.status)
                    if job.status == .signing {
                        ProgressView(value: job.progress)
                            .frame(width: 60)
                            .tint(.blue)
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
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiaryLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
