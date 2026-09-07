import StampedeCore
import SwiftUI

/// Le nove posizioni del watermark disposte come appaiono sulla foto,
/// così cliccare "in alto a destra" significa letteralmente cliccare in alto a destra.
struct AnchorGrid: View {
    @Binding var anchor: Anchor

    private let rows: [[Anchor]] = [
        [.topLeft, .topCenter, .topRight],
        [.middleLeft, .center, .middleRight],
        [.bottomLeft, .bottomCenter, .bottomRight],
    ]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { candidate in
                        Button {
                            anchor = candidate
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(anchor == candidate ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
                                .frame(width: 22, height: 16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(candidate.cliName)
                    }
                }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
