import SwiftUI

struct StatusBarView: View {
    @ObservedObject var st: AppState
    @Environment(\.palette) private var palette

    private var statusText: String {
        if st.busy {
            return "Forging ROM containers..."
        } else if st.files.isEmpty {
            return "Waiting for files · Drag & drop ROMs or folders"
        } else {
            let doneCount = st.files.filter { $0.state == .done || $0.state == .skipped }.count
            if doneCount == st.files.count {
                return "All operations completed successfully"
            }
            return "Queue ready · \(st.files.count) ROM(s) loaded"
        }
    }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(st.busy ? Palette.blue : (st.files.isEmpty ? Color.gray : Palette.green))
                    .frame(width: 8, height: 8)
                    .shadow(color: st.busy ? Palette.blue : (st.files.isEmpty ? .clear : Palette.green), radius: 4)
                Text(statusText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            if st.busy {
                Text("Do not close the application during active forging.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.orange.opacity(0.9))
                    .transition(.opacity)
            } else {
                Text("Smelt v\(AppInfo.version)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(palette.textFaint)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(palette.statusFill)
        .overlay(Rectangle().frame(height: 1).foregroundColor(palette.border), alignment: .top)
    }
}
