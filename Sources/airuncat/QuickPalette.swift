import AppKit
import SwiftUI

// MARK: - Panel controller

@MainActor
final class QuickPalette: NSObject, NSWindowDelegate {
    static let shared = QuickPalette()

    private var panel: NSPanel?
    let viewModel = PaletteViewModel()

    func show(sessions: [SessionInfo]) {
        if let p = panel, p.isVisible {
            hide()
            return
        }

        let p = panel ?? makePanel()

        Task {
            await viewModel.load(sessions: sessions)
        }

        if let screen = NSScreen.main {
            let sx = screen.frame.midX - 240
            let sy = screen.frame.midY + screen.frame.height * 0.1
            p.setFrameOrigin(NSPoint(x: sx, y: sy))
        }
        p.makeKeyAndOrderFront(nil as Any?)
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(rootView: PaletteView(vm: viewModel))
        hosting.view.frame = NSRect(x: 0, y: 0, width: 480, height: 300)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.titlebarAppearsTransparent = true
        p.titleVisibility = NSWindow.TitleVisibility.hidden
        p.isMovableByWindowBackground = true
        p.level = NSWindow.Level.floating
        p.collectionBehavior = NSWindow.CollectionBehavior([.canJoinAllSpaces, .fullScreenAuxiliary])
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.contentViewController = hosting
        p.delegate = self
        panel = p
        return p
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

// MARK: - PaletteView

struct PaletteView: View {
    @ObservedObject var vm: PaletteViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultList
            Divider()
            footer
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            TextField("스킬·프롬프트 검색", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onKeyPress(.escape)    { vm.close();    return .handled }
                .onKeyPress(.upArrow)   { vm.moveUp();   return .handled }
                .onKeyPress(.downArrow) { vm.moveDown(); return .handled }
                .onKeyPress(characters: .init(charactersIn: "\r"), phases: .down) { press in
                    if press.modifiers.contains(.command) { vm.copyOnly(); return .handled }
                    vm.inject()
                    return .handled
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.clear)
    }

    // MARK: - Result list

    private var resultList: some View {
        Group {
            if vm.filtered.isEmpty {
                Text(vm.query.isEmpty ? "항목 없음" : "일치하는 항목 없음")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.filtered.indices, id: \.self) { i in
                                PaletteRow(
                                    item: vm.filtered[i],
                                    isSelected: vm.selectedIndex == i
                                )
                                .id(i)
                                .onTapGesture {
                                    vm.selectedIndex = i
                                    vm.inject()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                    .onChange(of: vm.selectedIndex) { _, newVal in
                        proxy.scrollTo(newVal, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            sessionPicker
            Spacer()
            Text("↩ 삽입")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text("⌘↩ 복사")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text("Esc 닫기")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var sessionPicker: some View {
        if vm.availableSessions.isEmpty {
            Text("삽입 대상 없음")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
        } else {
            Menu {
                ForEach(vm.availableSessions) { session in
                    Button {
                        vm.selectTarget(session)
                    } label: {
                        HStack {
                            if vm.targetSession?.id == session.id {
                                Image(systemName: "checkmark")
                            }
                            Image(systemName: "circle.fill")
                                .foregroundColor(statusColor(for: session))
                                .font(.system(size: 7))
                            Text(session.displayName)
                            Spacer()
                            Text((session.cwd as NSString).lastPathComponent)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                    Text(vm.targetSession?.displayName ?? "대상 없음")
                        .font(.system(size: 10))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func statusColor(for session: SessionInfo) -> Color {
        switch session.status {
        case .active:  return .green
        case .idle:    return .yellow
        case .resting: return .secondary
        }
    }
}

// MARK: - Row

private struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(item.title)
                .font(.system(size: 13, design: item.kind == .skill ? .monospaced : .default))
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)
            Spacer()
            if item.lastUsed != nil {
                Text("최근")
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.6))
            }
            Text(item.kind == .skill ? "Skills" : "Prompts")
                .font(.system(size: 10))
                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
    }
}
