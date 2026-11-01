import SwiftUI

/// Fits the largest complete preview at its natural width, retaining a minimum
/// number of items when the narrow layout needs compact labels.
struct AdaptiveInlinePreview<Content: View>: View {
    let count: Int
    var minimum = 3
    @ViewBuilder var content: (Int, Bool) -> Content

    var body: some View {
        let smallest = min(minimum, count)
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: count, through: smallest, by: -1)), id: \.self) { visible in
                content(visible, false).fixedSize(horizontal: true, vertical: true)
            }
            content(smallest, true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
