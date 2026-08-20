import SwiftUI

struct ConsoleView: View {
    @ObservedObject var st: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.purple)
                Text("Console Output")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Button { st.exportLog() } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundColor(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Export diagnostic log")

                Button {
                    withAnimation { st.console = "" }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear console")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(palette.consoleChrome)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(st.console)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Palette.green)
                        Color.clear.frame(height: 1).id("console_bottom")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: st.console) { _ in
                    withAnimation { proxy.scrollTo("console_bottom", anchor: .bottom) }
                }
            }
        }
        .frame(height: 180)
        .background(palette.consoleFill)
        .overlay(Rectangle().frame(height: 1).foregroundColor(palette.border), alignment: .top)
    }
}
