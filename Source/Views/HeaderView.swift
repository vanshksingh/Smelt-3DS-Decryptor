import SwiftUI
import AppKit

struct HeaderView: View {
    @ObservedObject var st: AppState
    @ObservedObject var settings: Settings
    @Environment(\.palette) private var palette

    var pending: Int { st.pendingCount }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if let url = Bundle.main.url(forResource: "cover", withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Palette.purple.opacity(0.9), Palette.blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 140)
                }
                LinearGradient(colors: [.clear, palette.headerScrim], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)

                HStack(alignment: .bottom) {
                    titleBlock
                    Spacer()
                    smeltButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .frame(height: 140)

            CenteredFlowLayout(spacing: 12, rowSpacing: 10) {
                destinationMenu
                suffixField
                formatPicker
                Toggle("Reveal in Finder", isOn: $settings.autoOpen)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.textSecondary)
                    .fixedSize()
                Toggle("Console", isOn: $settings.showConsole)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.textSecondary)
                    .fixedSize()
                queueActions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(palette.toolbarFill)
            .overlay(Rectangle().frame(height: 1).foregroundColor(palette.border), alignment: .bottom)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Smelt")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            Text("3DS Decryptor & Flag Injector")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var smeltButton: some View {
        Button(action: st.run) {
            HStack(spacing: 8) {
                if st.busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "bolt.fill")
                }
                Text(st.busy ? "Smelting..." : "Smelt All\(pending > 0 ? " (\(pending))" : "")")
            }
        }
        .buttonStyle(PrimarySmeltButtonStyle(isBusy: st.busy, hasPending: pending > 0))
        .disabled(st.busy || pending == 0)
        .contentShape(Rectangle())
    }

    private var destinationMenu: some View {
        Menu {
            Button {
                withAnimation { st.useSameOutputFolder() }
            } label: {
                Label("Same as Source", systemImage: "doc.on.doc")
            }
            Button {
                pickCustomOutputFolder()
            } label: {
                Label("Choose Custom Folder...", systemImage: "folder.badge.plus")
            }
        } label: {
            destinationChip
        }
        .buttonStyle(.plain)
        .focusable(false)
        .fixedSize()
    }

    private var destinationChip: some View {
        HStack(spacing: 6) {
            Text("Destination:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.textTertiary)

            if settings.mode == .same {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.blue)
                Text("Same as Source")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.textPrimary)
            } else if let folder = settings.folder {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.blue)
                Text(folder.lastPathComponent)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Palette.blue)
            } else {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.orange)
                Text("Choose Folder...")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Palette.orange)
            }

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
                .foregroundColor(palette.textFaint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.chipFill))
    }

    private func pickCustomOutputFolder() {
        FilePickerService.pickOutputFolder(current: settings.folder) { selected in
            DispatchQueue.main.async {
                if let selected {
                    withAnimation {
                        st.setCustomOutputFolder(selected)
                    }
                } else if settings.folder == nil {
                    withAnimation {
                        st.useSameOutputFolder()
                    }
                }
            }
        }
    }

    private var suffixField: some View {
        HStack(spacing: 6) {
            Text("Suffix:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.textTertiary)
            TextField("", text: $settings.suffix)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(palette.textPrimary)
                .frame(width: 90)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(palette.fieldFill))
        }
    }

    private var formatPicker: some View {
        HStack(spacing: 6) {
            Text("Format:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.textTertiary)
            Picker("", selection: $settings.globalFormat) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)
            .focusable(false)
            .onChange(of: settings.globalFormat) { newValue in
                st.requeueIfNeeded(for: newValue)
            }
        }
    }

    private var queueActions: some View {
        HStack(spacing: 8) {
            let hasDone = st.files.contains { $0.state == .done || $0.state == .skipped }
            if hasDone {
                Button {
                    withAnimation { st.clearDone() }
                } label: {
                    Text("Clear Done")
                }
                .buttonStyle(SecondaryActionStyle(icon: "checkmark.circle", color: Palette.green))
                .disabled(st.busy)
                .transition(.scale.combined(with: .opacity))
            }

            if !st.files.isEmpty {
                Button {
                    withAnimation { st.clearAll() }
                } label: {
                    Text("Clear All")
                }
                .buttonStyle(SecondaryActionStyle(icon: "trash", color: Palette.red))
                .disabled(st.busy)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
