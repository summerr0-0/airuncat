import SwiftUI

// MARK: - Global 탭 (Phase 15.1)

/// 글로벌 레시피 GUI — 훅 3종(HookRecipeManager) + statusline(StatuslineManager).
/// 토글 = 설치/제거(전역, ~/.claude/settings.json). 프로젝트 레시피(검토 후 켜기)와 다른
/// 의미라 "전역" 배지를 상시 표시. 행 클릭 = 스크립트 본문 펼침(설치 전에도 열람 가능).
struct GlobalRecipesView: View {
    @State private var hookStates: [String: Bool] = [:]        // recipe.id -> installed
    @State private var statuslineStatus: StatuslineManager.Status = .notInstalled
    @State private var busy: Set<String> = []                  // 진행 중 토글(연타 방지)
    @State private var expanded: Set<String> = []              // 스크립트 미리보기 펼침
    @State private var rowErrors: [String: String] = [:]       // id -> 인라인 오류

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("글로벌 레시피 — Claude Code 전역(~/.claude)에 설치됩니다")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                ForEach(HookRecipeManager.recipes) { recipe in
                    hookRow(recipe)
                    Divider().opacity(0.4)
                }
                statuslineRow
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 420)
        .task { reload() }
    }

    // MARK: - 훅 레시피 행

    private func hookRow(_ recipe: HookRecipe) -> some View {
        let installed = hookStates[recipe.id] ?? false
        let isBusy = busy.contains(recipe.id)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(recipe.name)
                            .font(.system(size: 11, weight: .medium))
                        eventTag(recipe.event)
                        scopeBadge
                    }
                    Text(recipe.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Text("새 세션부터 적용")   // 훅 설정은 세션 시작 시 스냅샷
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                Spacer(minLength: 6)
                toggle(installed: installed, busy: isBusy) {
                    toggleHook(recipe, currentlyInstalled: installed)
                }
            }
            if let err = rowErrors[recipe.id] {
                Text(err).font(.system(size: 9)).foregroundColor(.red)
            }
            if expanded.contains(recipe.id) {
                scriptPreview(recipe.script)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { toggleExpand(recipe.id) }
        .help("클릭: 스크립트 본문 보기")
    }

    // MARK: - statusline 행

    private var statuslineRow: some View {
        let isBusy = busy.contains("statusline")
        let installed: Bool = { if case .installed = statuslineStatus { return true }; return false }()
        let foreignCmd: String? = { if case .foreign(let c) = statuslineStatus { return c }; return nil }()
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("statusline")
                            .font(.system(size: 11, weight: .medium))
                        eventTag("상태줄")
                        scopeBadge
                    }
                    Text("네이티브 ctx %·rate limit 캐시 + \"모델 · ctx%\" 상태줄 표시 (즉시 적용)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    if let cmd = foreignCmd {
                        Text("기존 설정 있음 — airuncat이 덮지 않습니다: \(cmd)")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                toggle(installed: installed, busy: isBusy, disabled: foreignCmd != nil) {
                    toggleStatusline(currentlyInstalled: installed)
                }
            }
            if let err = rowErrors["statusline"] {
                Text(err).font(.system(size: 9)).foregroundColor(.red)
            }
            if expanded.contains("statusline") {
                scriptPreview(StatuslineManager.script)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { toggleExpand("statusline") }
        .help("클릭: 스크립트 본문 보기")
    }

    // MARK: - 공용 소품

    private var scopeBadge: some View {
        Text("전역")
            .font(.system(size: 8, weight: .semibold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(AiruncatDesign.aiColor(.claude).opacity(0.12))
            .clipShape(Capsule())
            .foregroundColor(AiruncatDesign.aiColor(.claude))
    }

    private func eventTag(_ event: String) -> some View {
        Text(event)
            .font(.system(size: 8, design: .monospaced))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Color.primary.opacity(0.07))
            .clipShape(Capsule())
            .foregroundColor(.secondary)
    }

    private func toggle(installed: Bool, busy: Bool, disabled: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if busy {
                ProgressView().controlSize(.small).frame(width: 22)
            } else {
                Image(systemName: installed ? "circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(disabled ? .secondary.opacity(0.3)
                                     : (installed ? AiruncatDesign.aiColor(.claude) : .secondary.opacity(0.5)))
            }
        }
        .buttonStyle(.plain)
        .disabled(busy || disabled)
        .help(disabled ? "외부 statusline 존재 — 덮지 않음" : (installed ? "제거" : "설치"))
    }

    private func scriptPreview(_ script: String) -> some View {
        ScrollView {
            Text(script)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
        .frame(maxHeight: 140)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - 액션

    private func toggleExpand(_ id: String) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    private func toggleHook(_ recipe: HookRecipe, currentlyInstalled: Bool) {
        busy.insert(recipe.id)
        rowErrors[recipe.id] = nil
        Task.detached(priority: .userInitiated) {
            let err = currentlyInstalled ? HookRecipeManager.uninstall(recipe)
                                         : HookRecipeManager.install(recipe)
            let nowInstalled = HookRecipeManager.isInstalled(recipe)
            await MainActor.run {
                busy.remove(recipe.id)
                rowErrors[recipe.id] = err
                hookStates[recipe.id] = nowInstalled
            }
        }
    }

    private func toggleStatusline(currentlyInstalled: Bool) {
        busy.insert("statusline")
        rowErrors["statusline"] = nil
        Task.detached(priority: .userInitiated) {
            let err = currentlyInstalled ? StatuslineManager.remove() : StatuslineManager.install()
            let now = StatuslineManager.status()
            await MainActor.run {
                busy.remove("statusline")
                rowErrors["statusline"] = err
                statuslineStatus = now
            }
        }
    }

    private func reload() {
        for r in HookRecipeManager.recipes { hookStates[r.id] = HookRecipeManager.isInstalled(r) }
        statuslineStatus = StatuslineManager.status()
    }
}
