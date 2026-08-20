import SwiftUI

/// Wraps children onto additional centered rows when the window is too narrow.
struct CenteredFlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct Arrangement {
        var origins: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        let proposedWidth = proposal.width
        let unbounded = proposedWidth == nil || !(proposedWidth?.isFinite ?? false) || (proposedWidth ?? 0) <= 1
        let limit = unbounded ? CGFloat.greatestFiniteMagnitude : proposedWidth!

        var rows: [[CGSize]] = [[]]
        var rowWidths: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let rowIndex = rows.count - 1
            let extra = rowWidths[rowIndex] == 0 ? size.width : rowWidths[rowIndex] + spacing + size.width
            if extra > limit && !rows[rowIndex].isEmpty {
                rows.append([size])
                rowWidths.append(size.width)
                rowHeights.append(size.height)
            } else {
                rows[rowIndex].append(size)
                rowWidths[rowIndex] = extra
                rowHeights[rowIndex] = max(rowHeights[rowIndex], size.height)
            }
        }

        let containerWidth = unbounded ? (rowWidths.max() ?? 0) : limit
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var y: CGFloat = 0

        for rowIndex in rows.indices {
            var x = max(0, (containerWidth - rowWidths[rowIndex]) / 2)
            for size in rows[rowIndex] {
                origins.append(CGPoint(x: x, y: y + (rowHeights[rowIndex] - size.height) / 2))
                sizes.append(size)
                x += size.width + spacing
            }
            y += rowHeights[rowIndex]
            if rowIndex < rows.count - 1 {
                y += rowSpacing
            }
        }

        return Arrangement(origins: origins, sizes: sizes, size: CGSize(width: containerWidth, height: y))
    }
}
