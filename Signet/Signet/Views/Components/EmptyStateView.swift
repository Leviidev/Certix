import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Add"

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if #available(iOS 17, *) {
                    Image(systemName: systemImage)
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.quaternary)
                        .symbolEffect(.pulse, isActive: false)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.quaternary)
                }
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.blue, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
