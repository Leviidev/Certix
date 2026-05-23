import SwiftUI

struct StatusBadge: View {
    let label: String
    let color: Color
    let icon: String?

    init(_ label: String, color: Color, icon: String? = nil) {
        self.label = label
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            }
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

extension StatusBadge {
    static func forExpiry(_ status: Certificate.ExpiryStatus) -> StatusBadge {
        switch status {
        case .valid:
            return StatusBadge("Valid", color: .green, icon: "checkmark.circle.fill")
        case .expiringSoon:
            return StatusBadge("Expiring Soon", color: .orange, icon: "exclamationmark.circle.fill")
        case .expired:
            return StatusBadge("Expired", color: .red, icon: "xmark.circle.fill")
        }
    }

    static func forJob(_ status: SigningJob.Status) -> StatusBadge {
        switch status {
        case .queued:
            return StatusBadge(status.rawValue, color: .secondary, icon: status.systemImage)
        case .signing:
            return StatusBadge(status.rawValue, color: .blue, icon: status.systemImage)
        case .completed:
            return StatusBadge(status.rawValue, color: .green, icon: status.systemImage)
        case .failed:
            return StatusBadge(status.rawValue, color: .red, icon: status.systemImage)
        case .installing:
            return StatusBadge(status.rawValue, color: .purple, icon: status.systemImage)
        }
    }
}

struct CertExpiryBadge: View {
    let cert: Certificate
    var body: some View {
        StatusBadge.forExpiry(cert.expiryStatus)
    }
}
