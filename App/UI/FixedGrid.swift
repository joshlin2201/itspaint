import SwiftUI

/// A grid of fixed-size cells, laid out as rows.
///
/// **Not `LazyVGrid`.** A lazy grid asks for as much width as it is offered,
/// and inside a `fixedSize` container — which every panel in this app is, so
/// the chrome never resizes with the window — "as much as offered" resolves to
/// the whole screen. The result is a control that renders hundreds of points
/// wide with three enormous glyphs in it.
///
/// Chunking into explicit rows makes the size arithmetic, not negotiation:
/// `columns × cell + gaps`, every time, at any nesting depth.
struct FixedGrid<Item, Cell: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let cell: (Item) -> Cell

    init(
        _ items: [Item],
        columns: Int,
        spacing: CGFloat = 2,
        @ViewBuilder cell: @escaping (Item) -> Cell
    ) {
        self.items = items
        self.columns = max(1, columns)
        self.spacing = spacing
        self.cell = cell
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        cell(item)
                    }
                }
            }
        }
    }

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
    }
}
