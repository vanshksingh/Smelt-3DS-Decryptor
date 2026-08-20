import SwiftUI

struct DropZone: View {
    @ObservedObject var st: AppState
    @Environment(\.palette) private var palette
    @State private var targeted = false
    let browse: () -> Void

    var body: some View {
        Button(action: browse) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(targeted ? palette.dropFillActive : palette.dropFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(
                                targeted
                                    ? LinearGradient(colors: [Palette.blue, Palette.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [palette.dropStroke], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 2, dash: [10, 6])
                            )
                    )

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Palette.blue.opacity(0.2), Palette.purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 100, height: 100)
                            .scaleEffect(targeted ? 1.1 : 1.0)
                            .opacity(targeted ? 1 : 0.5)

                        Image(systemName: targeted ? "tray.and.arrow.down.fill" : "arrow.down.doc.fill")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(LinearGradient(colors: [Palette.blue, Palette.purple], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Palette.blue.opacity(targeted ? 0.6 : 0), radius: 12)
                            .offset(y: targeted ? 4 : 0)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: targeted)

                    VStack(spacing: 8) {
                        Text("Drag & Drop ROMs or Folders")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(palette.textPrimary)
                        Text("Supports .3ds, .cia, .cci, .cxi files and directories")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(palette.textTertiary)
                    }

                    Text("Browse Files...")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(palette.fieldFill))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border, lineWidth: 1))
                        .padding(.top, 10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse for ROM files")
        .onDrop(of: [.fileURL, .url], isTargeted: $targeted) { providers in
            DropService.collect(providers) { urls in
                st.add(urls)
            }
            return true
        }
    }
}

struct ROMRow: View {
    @Binding var r: ROM
    let globalFormat: OutputFormat
    let onRemove: () -> Void
    @Environment(\.palette) private var palette
    @State private var flash = false
    @State private var isHovered = false
    @State private var showPopover = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill((r.ext == "CIA" ? Palette.purple : Palette.blue).opacity(0.15))
                        .frame(width: 46, height: 46)
                    VStack(spacing: 4) {
                        Image(systemName: r.ext == "CIA" ? "shippingbox.fill" : (r.ext == "CCI" ? "opticaldiscdrive.fill" : "gamecontroller.fill"))
                            .font(.system(size: 16))
                        Text(r.ext)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(r.ext == "CIA" ? Palette.purple : Palette.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(r.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(r.size)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.textTertiary)

                        if r.analysis != .unknown {
                            HStack(spacing: 4) {
                                Image(systemName: r.analysis.icon)
                                    .font(.system(size: 9, weight: .bold))
                                Text(r.analysis.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(r.analysis.col)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(r.analysis.col.opacity(0.15)))
                        }

                        if !r.note.isEmpty && r.state != .running {
                            Text(r.note)
                                .font(.system(size: 11))
                                .italic()
                                .foregroundColor(r.state == .failed ? Palette.red : palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                let outExt = r.expectedOutputExt(globalFormat: globalFormat)
                Text("Output: \(outExt)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(outExt == "CIA" ? Palette.purple : Palette.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill((outExt == "CIA" ? Palette.purple : Palette.blue).opacity(0.12)))

                HStack(spacing: 6) {
                    if r.state == .running || r.state == .scanning {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.5).frame(width: 12, height: 12)
                    } else {
                        Circle().fill(r.state.col).frame(width: 8, height: 8)
                    }
                    Text(r.state.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(r.state.col)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(r.state.col.opacity(0.15)))

                HStack(spacing: 12) {
                    Button { showPopover.toggle() } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(showPopover ? Palette.purple : palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("ROM Metadata Details")
                    .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                        metadataPopover
                    }

                    if r.state == .done, let out = r.outputURL {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Palette.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                        .transition(.scale.combined(with: .opacity))
                    }

                    if r.state != .running {
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(palette.inverted.opacity(isHovered ? 0.55 : 0.22))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if r.state == .running {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(palette.fieldFill)
                        Rectangle()
                            .fill(LinearGradient(colors: [Palette.blue, Palette.purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(r.progress))
                    }
                }
                .frame(height: 3)
                .cornerRadius(1.5)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .animation(.easeOut(duration: 0.25), value: r.progress)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovered ? palette.cardHover : palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            r.state == .done
                                ? Palette.green.opacity(flash ? 0.8 : 0.2)
                                : (isHovered ? Palette.blue.opacity(0.3) : palette.border),
                            lineWidth: r.state == .done ? (flash ? 2 : 1) : 1
                        )
                )
        )
        .shadow(color: Palette.green.opacity(flash ? 0.4 : 0), radius: flash ? 12 : 0)
        .onHover { isHovered = $0 }
        .onChange(of: r.state) { newState in
            if newState == .done {
                withAnimation(.easeOut(duration: 0.5)) { flash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeIn(duration: 0.8)) { flash = false }
                }
            }
        }
    }

    private var metadataPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ROM Header Info")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Divider().background(palette.border)

            VStack(alignment: .leading, spacing: 8) {
                metaRow("Filename:", r.name)
                metaRow("Size:", r.size)
                HStack {
                    Text("Title ID:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(palette.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    Text(r.titleID ?? "Unknown (Scanning...)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(r.titleID != nil ? Palette.blue : palette.textFaint)
                }
                HStack {
                    Text("Product Code:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(palette.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    Text(r.productCode ?? "Unknown (Scanning...)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(r.productCode != nil ? Palette.blue : palette.textFaint)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(palette.licenseFill)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(palette.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(palette.textPrimary)
        }
    }
}

struct MainContentView: View {
    @ObservedObject var st: AppState
    @ObservedObject var settings: Settings
    @Environment(\.palette) private var palette
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            if st.files.isEmpty {
                DropZone(st: st, browse: openPicker)
                    .padding(32)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(st.files) { rom in
                            ROMRow(r: st.bindingFor(rom.id), globalFormat: settings.globalFormat) {
                                withAnimation { st.remove(rom) }
                            }
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                    }
                    .padding(24)
                }
                .frame(maxHeight: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: st.files.map(\.id))

                Button(action: openPicker) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(Palette.blue)
                        Text("Drop more files here or click to browse")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(targeted ? Palette.blue.opacity(0.15) : palette.dropFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(targeted ? Palette.blue : palette.dropStroke, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            ConsoleView(st: st)
                .frame(height: st.settings.showConsole ? 180 : 0)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .url], isTargeted: $targeted) { providers in
            DropService.collect(providers) { urls in
                st.add(urls)
            }
            return true
        }
    }

    private func openPicker() {
        FilePickerService.openFiles { urls in
            st.add(urls)
        }
    }
}
