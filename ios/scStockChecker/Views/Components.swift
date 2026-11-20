import SwiftUI

// Shared look: neutral grouped background, rounded cards, small caps labels,
// and one colour per meaning: green = your size in stock, blue = coming soon,
// orange = other sizes in stock / warnings, red = sold out, purple = priority.

enum Palette {
    static let inStock = Color.green
    static let soon = Color.blue
    static let otherSizes = Color.orange
    static let warning = Color.orange
    static let soldOut = Color.red
    static let priority = Color.purple
    static let card = Color(.secondarySystemGroupedBackground)
    static let page = Color(.systemGroupedBackground)
}

extension TrackedItem.StockState {
    var color: Color {
        switch self {
        case .wantedInStock: Palette.inStock
        case .wantedComingSoon: Palette.soon
        case .otherSizesInStock: Palette.otherSizes
        case .soldOut: Palette.soldOut
        case .unknown: Color.secondary.opacity(0.4)
        }
    }
}

/// Colours the frame of a product card by its stock state.
struct StockFrame: ViewModifier {
    let state: TrackedItem.StockState
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(state.color, lineWidth: state == .unknown ? 1 : 2)
        )
    }
}

extension View {
    func stockFrame(_ state: TrackedItem.StockState, cornerRadius: CGFloat = 16) -> some View {
        modifier(StockFrame(state: state, cornerRadius: cornerRadius))
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Small uppercase heading above a card.
struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased(with: Locale(identifier: "tr_TR")))
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Pulsing dot used for "live" states.
struct LiveDot: View {
    let color: Color
    var animated = true
    @State private var pulse = false

    var body: some View {
        ZStack {
            if animated {
                Circle().fill(color.opacity(0.35))
                    .scaleEffect(pulse ? 2.2 : 1).opacity(pulse ? 0 : 1)
            }
            Circle().fill(color)
        }
        .frame(width: 9, height: 9)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct ProductImage: View {
    let url: String?
    var cornerRadius: CGFloat = 10

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.secondary.opacity(0.08)
                Image(systemName: "tshirt").foregroundStyle(.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Wanted sizes with their availability (all sizes when none are chosen).
struct SizeChips: View {
    let item: TrackedItem
    var compact = false

    var body: some View {
        let shown = item.wantedSizes.isEmpty ? item.sizes : item.sizes.filter { item.isWanted($0.name) }
        if shown.isEmpty {
            Text(item.lastCheckedAt == nil ? "İlk kontrol bekleniyor" : "Beden bilgisi yok")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 4) {
                ForEach(shown, id: \.name) { SizeChip(size: $0, compact: compact) }
            }
        }
    }
}

struct SizeChip: View {
    let size: StoredSize
    var compact = false

    var body: some View {
        let color = availabilityColor(size.availability)
        Text(TrackedItem.shortSize(size.name))
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .strikethrough(size.availability == .outOfStock, color: .secondary)
            .foregroundStyle(size.availability == .outOfStock ? Color.secondary : color)
            .padding(.horizontal, compact ? 5 : 7).padding(.vertical, compact ? 2 : 3)
            .background(
                (size.availability == .outOfStock ? Color.secondary : color).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }
}

func availabilityColor(_ a: Availability) -> Color {
    switch a {
    case .inStock, .lowOnStock: Palette.inStock
    case .comingSoon: Palette.soon
    case .outOfStock: Palette.soldOut
    case .unknown: .secondary
    }
}

/// Small live "12 sn" label showing when the server last checked an item.
struct CheckedAgo: View {
    let date: Date?
    var failed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label(date.map { agoText($0, now: context.date) } ?? "—", systemImage: failed ? "exclamationmark.triangle.fill" : "arrow.clockwise")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(failed ? Palette.warning : Color.secondary)
                .labelStyle(.titleAndIcon)
        }
    }
}

struct BellIcon: View {
    let count: Int

    var body: some View {
        Image(systemName: "bell")
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Palette.soldOut, in: Capsule())
                        .offset(x: 10, y: -8)
                }
            }
    }
}

/// Simple wrapping layout for size chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, point) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}
