import ResetRadarApplication
import ResetRadarDomain
import ResetRadarUI
import SwiftUI

/// One compact Account Row: alias and product, the two standard rings, and the neutral
/// Account Details arrow. Accessibility sizes reflow it without changing the logical order.
struct AccountRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the ring captions so Percentage Used stays legible inside the ring, capped so
    /// two rings and the arrow still share one line at accessibility sizes.
    @ScaledMetric(relativeTo: .caption2) private var scaledRingDiameter: CGFloat = 54
    let row: AccountRow
    let selected: Bool
    let refreshLine: String?
    let open: (AccountWindow.StandardWindow?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    identity
                    HStack(spacing: 14) {
                        rings
                        Spacer(minLength: 0)
                        detailsButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    identity.frame(maxWidth: .infinity, alignment: .leading)
                    rings
                    detailsButton
                }
            }
            if let refreshLine {
                Text(refreshLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("refreshLine.\(row.account.number)")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    selected ? Color.accentColor : Color.secondary.opacity(0.18),
                    lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { open(nil) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accountRow.\(row.account.number)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.account.effectiveDisplayLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(row.account.effectiveDisplayLabel)
            Text(ReaderVocabulary.productName(row.source.product))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rings: some View {
        HStack(spacing: 10) {
            ForEach(row.standardWindows, id: \.accountWindow) { ring in
                let display = AllowanceDisplay(ring: ring, product: row.account.product)
                let window = ring.accountWindow.window
                Button {
                    open(window)
                } label: {
                    AllowanceRing(
                        display: display, caption: ReaderVocabulary.windowCaption(window),
                        diameter: ringDiameter)
                }
                .buttonStyle(.plain)
                // Never narrower than the drawn circle, so a tight column truncates the alias
                // or scales the captions instead of overlapping the rings.
                .frame(minWidth: max(44, ringDiameter), minHeight: 44)
                .accessibilityLabel(
                    display.accessibilityLabel(
                        account: row.account, window: ReaderVocabulary.windowName(window))
                )
                .accessibilityHint("Opens Account Details for this window")
                .accessibilityIdentifier("ring.\(row.account.number).\(window.rawValue)")
            }
        }
    }

    private var ringDiameter: CGFloat { min(scaledRingDiameter, 96) }

    private var detailsButton: some View {
        Button {
            open(nil)
        } label: {
            Image("AccountDetails")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account Details")
        .accessibilityIdentifier("accountDetails.\(row.account.number)")
    }
}
