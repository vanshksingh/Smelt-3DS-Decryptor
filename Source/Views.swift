import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Custom Styles
struct SecondaryActionStyle: ButtonStyle {
    var icon: String
    var color: Color
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            configuration.label
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(isEnabled ? color : .white.opacity(0.2))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(configuration.isPressed ? color.opacity(0.2) : (isHovered && isEnabled ? color.opacity(0.15) : color.opacity(0.08)))
        )
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            if isEnabled { isHovered = hovering }
        }
    }
}

struct PrimarySmeltButtonStyle: ButtonStyle {
    var isBusy: Bool
    var hasPending: Bool
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        let enabled = !isBusy && hasPending
        HStack(spacing: 8) {
            configuration.label
        }
        .font(.system(size: 14, weight: .black, design: .rounded))
        .foregroundColor(enabled ? BG : .white.opacity(0.3))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Group {
                if enabled {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: isHovered ? [BLU.opacity(1.2), PRP.opacity(1.2)] : [BLU, PRP], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: BLU.opacity(isHovered ? 0.6 : 0.3), radius: isHovered ? 12 : 6, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
            }
        )
        .scaleEffect(configuration.isPressed && enabled ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            if enabled { isHovered = hovering }
        }
    }
}

// MARK: - Header
struct HeaderView: View {
    @ObservedObject var st: AppState
    @ObservedObject var settings: Settings
    var pending: Int { st.files.filter{$0.state == .queued || $0.state == .failed}.count }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if let u = Bundle.main.url(forResource: "cover", withExtension: "png"), let img = NSImage(contentsOf: u) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else {
                    LinearGradient(colors: [PRP.opacity(0.9), BLU.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(height: 140)
                }
                LinearGradient(colors: [.clear, BG], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)
                
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smelt")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                        Text("3DS Decryptor & Flag Injector")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    
                    Button(action: st.run) {
                        HStack(spacing: 8) {
                            if st.busy {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.55).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(st.busy ? "Smelting..." : "Smelt All\(pending > 0 ? " (\(pending))" : "")")
                        }
                    }
                    .buttonStyle(PrimarySmeltButtonStyle(isBusy: st.busy, hasPending: pending > 0))
                    .disabled(st.busy || pending == 0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .frame(height: 140)
            
            // Settings Toolbar Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // Unified Location Selector
                    Menu {
                        Button(action: {
                            withAnimation { settings.mode = .same }
                        }) {
                            Label("Same as Source", systemImage: "doc.on.doc")
                        }
                        Button(action: {
                            withAnimation { settings.mode = .custom }
                            pickFolderAsync(s: settings)
                        }) {
                            Label("Choose Custom Folder...", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Destination:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                            
                            if settings.mode == .same {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(BLU)
                                Text("Same as Source")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.95))
                            } else if let folder = settings.folder {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(BLU)
                                Text(folder.lastPathComponent)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(BLU)
                            } else {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 10))
                                    .foregroundColor(ORG)
                                Text("Choose Folder...")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(ORG)
                            }
                            
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .fixedSize()
                    
                    Divider().frame(height: 16).background(BRD)
                    
                    HStack(spacing: 6) {
                        Text("Suffix:").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.4))
                        TextField("", text: $settings.suffix)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 90)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                    }
                    
                    Divider().frame(height: 16).background(BRD)
                    
                    HStack(spacing: 6) {
                        Text("Format:").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.4))
                        Picker("", selection: $settings.globalFormat) {
                            ForEach(OutputFormat.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 130)
                        .focusable(false)
                        .onChange(of: settings.globalFormat) {
                            st.requeueIfNeeded(for: settings.globalFormat)
                        }
                    }
                    
                    Divider().frame(height: 16).background(BRD)
                    
                    Toggle("Reveal in Finder", isOn: $settings.autoOpen)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Toggle("Console", isOn: $settings.showConsole)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    let hasDone = st.files.contains(where: { $0.state == .done || $0.state == .skipped })
                    if hasDone {
                        Button(action: { withAnimation { st.clearDone() } }) {
                            Text("Clear Done")
                        }
                        .buttonStyle(SecondaryActionStyle(icon: "checkmark.circle", color: GRN))
                        .disabled(st.busy)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    if !st.files.isEmpty {
                        Button(action: { withAnimation { st.clearAll() } }) {
                            Text("Clear All")
                        }
                        .buttonStyle(SecondaryActionStyle(icon: "trash", color: RED))
                        .disabled(st.busy)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(Color.white.opacity(0.02))
            .overlay(Rectangle().frame(height: 1).foregroundColor(BRD), alignment: .bottom)
        }
    }
    
    private func pickFolderAsync(s: Settings) {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Select Output"
        p.message = "Choose where decrypted/patched ROMs will be saved"
        
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK {
                DispatchQueue.main.async { s.folder = p.url }
            } else if s.folder == nil {
                DispatchQueue.main.async { s.mode = .same }
            }
        }
        
        if let window = NSApplication.shared.windows.first {
            p.beginSheetModal(for: window, completionHandler: completion)
        } else {
            p.begin(completionHandler: completion)
        }
    }
}

// MARK: - Drop Zone
struct DropZone: View {
    @ObservedObject var st: AppState
    @State private var tgt = false
    let browse: () -> Void
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(tgt ? 0.04 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            tgt ? LinearGradient(colors: [BLU, PRP], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 2, dash: [10, 6])
                        )
                )
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [BLU.opacity(0.2), PRP.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 100, height: 100)
                        .scaleEffect(tgt ? 1.1 : 1.0)
                        .opacity(tgt ? 1 : 0.5)
                    
                    Image(systemName: tgt ? "tray.and.arrow.down.fill" : "arrow.down.doc.fill")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(LinearGradient(colors: [BLU, PRP], startPoint: .top, endPoint: .bottom))
                        .shadow(color: BLU.opacity(tgt ? 0.6 : 0), radius: 12)
                        .offset(y: tgt ? 4 : 0)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: tgt)
                
                VStack(spacing: 8) {
                    Text("Drag & Drop ROMs or Folders")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Supports .3ds, .cia, .cci, .cxi files and directories")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Button(action: browse) {
                    Text("Browse Files...")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $tgt, perform: drop)
    }
    
    private func drop(_ pr:[NSItemProvider])->Bool {
        let g=DispatchGroup(); var urls:[URL]=[]
        for p in pr { g.enter(); p.loadItem(forTypeIdentifier:UTType.fileURL.identifier){i,_ in defer{g.leave()}
            if let d=i as? Data, let u=URL(dataRepresentation:d,relativeTo:nil){urls.append(u)}
            else if let u=i as? URL{urls.append(u)} }}
        g.notify(queue:.main){ st.add(urls) }; return true
    }
}

// MARK: - Queue Row
struct ROMRow: View {
    @Binding var r: ROM
    let globalFormat: OutputFormat
    let onRemove: () -> Void
    @State private var flash = false
    @State private var isHovered = false
    @State private var showPopover = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill((r.ext == "CIA" ? PRP : BLU).opacity(0.15))
                        .frame(width: 46, height: 46)
                    VStack(spacing: 4) {
                        Image(systemName: r.ext == "CIA" ? "shippingbox.fill" : (r.ext == "CCI" ? "opticaldiscdrive.fill" : "gamecontroller.fill"))
                            .font(.system(size: 16))
                        Text(r.ext)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(r.ext == "CIA" ? PRP : BLU)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(r.size)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                        
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
                                .foregroundColor(r.state == .failed ? RED : .white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Format target display
                let outExt = r.expectedOutputExt(globalFormat: globalFormat)
                Text("Output: \(outExt)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(outExt == "CIA" ? PRP : BLU)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill((outExt == "CIA" ? PRP : BLU).opacity(0.12)))
                
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
                    // Info Popover Trigger Button
                    Button(action: { showPopover.toggle() }) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(showPopover ? PRP : .white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("ROM Metadata Details")
                    .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ROM Header Info")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Divider().background(BRD)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Filename:").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.5)).frame(width: 80, alignment: .leading)
                                    Text(r.name).font(.system(size: 11)).foregroundColor(.white)
                                }
                                HStack {
                                    Text("Size:").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.5)).frame(width: 80, alignment: .leading)
                                    Text(r.size).font(.system(size: 11)).foregroundColor(.white)
                                }
                                HStack {
                                    Text("Title ID:").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.5)).frame(width: 80, alignment: .leading)
                                    Text(r.titleID ?? "Unknown (Scanning...)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(r.titleID != nil ? BLU : .white.opacity(0.3))
                                }
                                HStack {
                                    Text("Product Code:").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.5)).frame(width: 80, alignment: .leading)
                                    Text(r.productCode ?? "Unknown (Scanning...)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(r.productCode != nil ? BLU : .white.opacity(0.3))
                                }
                            }
                        }
                        .padding(16)
                        .frame(width: 300)
                        .background(BG)
                        .preferredColorScheme(.dark)
                    }
                    
                    if r.state == .done, let out = r.outputURL {
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([out]) }) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(BLU)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    if r.state != .running {
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.2))
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
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.05))
                        Rectangle()
                            .fill(LinearGradient(colors: [BLU, PRP], startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * CGFloat(r.progress))
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
                .fill(Color.white.opacity(isHovered ? 0.05 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(r.state == .done ? GRN.opacity(flash ? 0.8 : 0.2) : (isHovered ? BLU.opacity(0.3) : BRD),
                                lineWidth: r.state == .done ? (flash ? 2 : 1) : 1)
                )
        )
        .shadow(color: GRN.opacity(flash ? 0.4 : 0), radius: flash ? 12 : 0)
        .onHover { isHovered = $0 }
        .onChange(of: r.state) {
            if r.state == .done {
                withAnimation(.easeOut(duration: 0.5)) { flash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeIn(duration: 0.8)) { flash = false }
                }
            }
        }
    }
}

// MARK: - Console
struct ConsoleView: View {
    @ObservedObject var st: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill").font(.system(size: 12)).foregroundColor(PRP)
                Text("Console Output")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Button(action: { st.exportLog() }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Export diagnostic log")
                
                Button(action: { withAnimation { st.console = "" } }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Clear console")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(st.console)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(GRN)
                        Color.clear.frame(height: 1).id("console_bottom")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: st.console) {
                    withAnimation { proxy.scrollTo("console_bottom", anchor: .bottom) }
                }
            }
        }
        .frame(height: 180)
        .background(Color.black.opacity(0.4))
        .overlay(Rectangle().frame(height: 1).foregroundColor(BRD), alignment: .top)
    }
}

// MARK: - Status Bar
struct StatusBarView: View {
    @ObservedObject var st: AppState
    
    private var statusText: String {
        if st.busy {
            return "Forging ROM containers..."
        } else if st.files.isEmpty {
            return "Waiting for files · Drag & drop ROMs or folders"
        } else {
            let doneCount = st.files.filter { $0.state == .done || $0.state == .skipped }.count
            if doneCount == st.files.count {
                return "All operations completed successfully"
            } else {
                return "Queue ready · \(st.files.count) ROM(s) loaded"
            }
        }
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(st.busy ? BLU : (st.files.isEmpty ? .gray : GRN))
                    .frame(width: 8, height: 8)
                    .shadow(color: st.busy ? BLU : (st.files.isEmpty ? .clear : GRN), radius: 4)
                Text(statusText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            if st.busy {
                Text("Do not close the application during active forging.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ORG.opacity(0.8))
                    .transition(.opacity)
            } else {
                Text("Smelt v1.0.0")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
        .overlay(Rectangle().frame(height: 1).foregroundColor(BRD), alignment: .top)
    }
}

// MARK: - Main Panel
struct MainContentView: View {
    @ObservedObject var st: AppState
    @ObservedObject var settings: Settings
    @State private var tgt = false
    
    var body: some View {
        VStack(spacing: 0) {
            if st.files.isEmpty {
                DropZone(st: st, browse: openPicker)
                    .padding(32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(st.files) { r in
                            ROMRow(r: st.bindingFor(r.id), globalFormat: settings.globalFormat) {
                                withAnimation { st.remove(r) }
                            }
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                    }
                    .padding(24)
                }
                .frame(maxHeight: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: st.files)
                
                Button(action: openPicker) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 15)).foregroundColor(BLU)
                        Text("Drop more files here or click to browse").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(tgt ? BLU.opacity(0.15) : Color.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tgt ? BLU : Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
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
        .background(Color.white.opacity(0.01))
        .onDrop(of: [.fileURL], isTargeted: $tgt, perform: drop)
    }
    
    private func drop(_ pr:[NSItemProvider])->Bool {
        let g=DispatchGroup(); var urls:[URL]=[]
        for p in pr { g.enter(); p.loadItem(forTypeIdentifier:UTType.fileURL.identifier){i,_ in defer{g.leave()}
            if let d=i as? Data, let u=URL(dataRepresentation:d,relativeTo:nil){urls.append(u)}
            else if let u=i as? URL{urls.append(u)} }}
        g.notify(queue:.main){ st.add(urls) }; return true
    }
    
    private func openPicker() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowedContentTypes = (["3ds", "cia", "cci", "cxi"].compactMap { UTType(filenameExtension: $0) }) + [.folder]
        p.prompt = "Add to Queue"
        p.message = "Select 3DS ROM files, CIA packages, or folders containing them"
        
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK { st.add(p.urls) }
        }
        
        if let window = NSApplication.shared.windows.first {
            p.beginSheetModal(for: window, completionHandler: completion)
        } else {
            p.begin(completionHandler: completion)
        }
    }
}

// MARK: - Root
// MARK: - License Agreement
struct LicenseView: View {
    @Binding var isPresented: Bool
    @State private var hasAcceptedCheckbox = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20))
                    .foregroundColor(BLU)
                Text("END-USER LICENSE AGREEMENT AND TERMS OF SERVICE")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("IMPORTANT - READ CAREFULLY: This End-User License Agreement (\"EULA\") is a legal agreement between you (either an individual or a single entity) and the developer of the Smelt software utility (\"Software\"). By clicking \"Agree\" and using the Software, you agree to be bound by the terms of this EULA. If you do not agree to the terms of this EULA, do not use the Software and click \"Disagree & Exit\".")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("0. DECLARATION OF REALITY AND INTENT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("By using Smelt, you acknowledge that this Software is simply a graphical user interface (frontend) that coordinates external, third-party CLI tools (ctrtool, makerom, and ctrdecrypt) to assist with file decryption. You agree that if your Mac runs hot enough to fry eggs, sounds like a commercial airplane preparing for takeoff, or if you run out of drive space because you attempted to decrypt massive file dumps all at once, that is entirely your issue. You certify that you are using this utility exclusively for personal backups of games you legally purchased and physically own, and you will not hold the developer responsible when your emulators act up because you chose the wrong configuration settings.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("1. DISCLAIMER OF AFFILIATION AND ENDORSEMENT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("This Software is an independent, unofficial utility. The developer of this Software is strictly independent and is NOT affiliated, associated, authorized, endorsed by, or in any way officially connected with Nintendo Co., Ltd., Nintendo of America, Inc., or any of their subsidiaries, affiliates, or licensors. All registered trademarks, including but not limited to 'Nintendo', '3DS', 'CTR', and 'Citra', are the exclusive property of their respective owners. The use of these names is for interoperability and descriptive purposes only and does not imply any association or endorsement.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))

                    Text("2. STRICT PROHIBITION OF PIRACY AND COPYRIGHT INFRINGEMENT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("This Software is designed solely for the purpose of personal data archival, format shifting, and interoperability of legally obtained, physically owned game media. \n\n(a) You explicitly represent and warrant that any and all files (including ROMs, CIAs, CCIs, CXIs, DLCs, and Updates) processed through this Software have been legally dumped directly from hardware or media that you legally purchased and own.\n(b) You shall not use this Software to process, decrypt, distribute, or otherwise interact with unauthorized, pirated, or illegally downloaded copyrighted material.\n(c) The developer strictly condemns software piracy. The developer shall not be held responsible for your actions should you choose to violate international copyright laws.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))

                    Text("3. THIRD-PARTY COMPONENTS AND LICENSES")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("This Software utilizes third-party command-line utilities (including but not limited to ctrtool, makerom, and ctrdecrypt) which are provided under their respective open-source licenses (such as the MIT License or GNU General Public License). These tools are executed in a sandbox environment and their respective licenses apply to their usage. The developer claims no ownership over these specific external binary components.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("4. IMPOSSIBILITY OF CIA REPACKAGING")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("The developer expressly declines to offer the ability to output encrypted .cia containers. The mathematical and cryptographic reality is that generating a valid CIA container requires Nintendo's RSA Private Keys. Unless you are planning on personally breaking into Nintendo Headquarters in Kyoto, bypassing their biometric security, and stealing their internal signing servers, any CIA you generate would be universally rejected by standard hardware and emulators anyway. Therefore, Smelt outputs .cci or .3ds formats exclusively.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("5. MIT LICENSE & DISCLAIMER OF WARRANTY")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. \n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))

                    Text("6. LIMITATION OF LIABILITY")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("IN NO EVENT SHALL THE AUTHORS, DEVELOPERS, OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. \n\nUnder no circumstances shall the developer be liable for any direct, indirect, incidental, special, exemplary, or consequential damages (including, but not limited to, procurement of substitute goods or services; loss of use, data, or profits; hardware failure; thermal damage to your machine; or business interruption) however caused and on any theory of liability, whether in contract, strict liability, or tort (including negligence or otherwise) arising in any way out of the use of this Software, even if advised of the possibility of such damage.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))

                    Text("7. INDEMNIFICATION")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("You agree to indemnify, defend, and hold harmless the developer from and against any and all claims, liabilities, damages, losses, costs, expenses, or fees (including reasonable attorneys' fees) that arise from your violation of this EULA or your unauthorized use of the Software. Should your actions attract legal scrutiny or litigation, you assume sole and absolute responsibility.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))

                    Text("8. SEVERABILITY")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BLU)
                    Text("If any provision of this EULA is held to be unenforceable or invalid, such provision will be changed and interpreted to accomplish the objectives of such provision to the greatest extent possible under applicable law, and the remaining provisions will continue in full force and effect.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Divider().background(BRD).padding(.vertical, 8)
                    
                    Toggle(isOn: $hasAcceptedCheckbox) {
                        Text("I certify that I have read the terms and agree to be bound by them.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(20)
            }
            .background(Color.black.opacity(0.2))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            
            HStack(spacing: 12) {
                Spacer()
                Button(action: {
                    exit(0)
                }) {
                    Text("Disagree & Exit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    isPresented = false
                }) {
                    Text("Agree & Open")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(hasAcceptedCheckbox ? BG : .white.opacity(0.2))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(hasAcceptedCheckbox ? GRN : Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .disabled(!hasAcceptedCheckbox)
            }
            .padding(24)
        }
        .frame(width: 600, height: 480)
        .background(BG)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Root
struct ContentView: View {
    @StateObject private var st = AppState()
    @State private var showLicense = true
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(st: st, settings: st.settings)
            MainContentView(st: st, settings: st.settings)
            StatusBarView(st: st)
        }
        .frame(minWidth: 840, minHeight: 560)
        .background(BG.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLicense) {
            LicenseView(isPresented: $showLicense)
                .interactiveDismissDisabled()
        }
    }
}

@main struct SmeltApp: App {
    var body: some Scene {
        WindowGroup{ ContentView() }
            .windowStyle(.titleBar)
            .windowToolbarStyle(.unifiedCompact)
    }
}
