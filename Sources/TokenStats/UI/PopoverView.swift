import SwiftUI

/// Popover, 372 pt breit: Kopf mit Seitenwahl · Tabs je Client · Seite · Fußzeile (SPEC §3).
struct PopoverView: View {
    let store: UsageStore
    let consumption: ConsumptionStore
    let settings: AppSettings
    let openSettings: () -> Void

    @State private var selectedID: String?
    /// Beim Öffnen steht immer „Limits“ – die Auswahl wird absichtlich nicht gemerkt.
    @State private var page: Page = .limits

    static let width: CGFloat = 372
    static let maxVisibleTabs = 4
    /// Seitenrand aller Blöcke im Popover.
    static let inset: CGFloat = 16

    var body: some View {
        let providers = store.sortedProviders
        let selected = providers.first { $0.id == selectedID } ?? providers.first

        VStack(spacing: 0) {
            header
            if providers.isEmpty {
                emptyState
            } else {
                tabBar(providers, selected: selected?.id)
                Divider()
                if let selected {
                    ProviderPage(
                        provider: selected,
                        page: page,
                        state: store.states[selected.id] ?? .init(),
                        isLoading: store.loading.contains(selected.id),
                        consumption: consumption,
                        showMoney: settings.showMoney
                    )
                }
            }
            Divider()
            footer(account: selected.flatMap { store.states[$0.id]?.snapshot?.account })
        }
        .frame(width: Self.width)
        .background {
            // ⌘, öffnet die Einstellungen, solange das Popover offen ist.
            Button("", action: openSettings).keyboardShortcut(",", modifiers: .command).hidden()
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 8) {
            RobotIcon()
            Text("Token Stats").font(.system(size: 13.5, weight: .bold))
            Spacer()
            PageSwitch(selection: $page)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Tabs

    private func tabBar(_ providers: [any UsageProvider], selected: String?) -> some View {
        let visible = providers.prefix(Self.maxVisibleTabs)
        let overflow = providers.dropFirst(Self.maxVisibleTabs)
        return HStack(spacing: 2) {
            ForEach(visible, id: \.id) { provider in
                TabButton(
                    title: provider.displayName,
                    severity: store.states[provider.id]?.snapshot?.tightestWindow?.severity,
                    isActive: provider.id == selected
                ) { selectedID = provider.id }
            }
            if !overflow.isEmpty {
                Menu("+\(overflow.count)") {
                    ForEach(overflow, id: \.id) { provider in
                        Button(provider.displayName) { selectedID = provider.id }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.system(size: 11.5, design: .monospaced))
            }
            Spacer()
        }
        .padding(.horizontal, Self.inset - 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Kein Anbieter gefunden").font(.system(size: 12.5, weight: .semibold))
            Text("Token Stats sucht nach Claude Code (~/.claude) und Codex (~/.codex).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Fußzeile

    private func footer(account: AccountInfo?) -> some View {
        HStack(spacing: 8) {
            if let name = account?.name {
                HStack(spacing: 7) {
                    Text(name.prefix(1).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 19, height: 19)
                        .background(Circle().fill(Color.accentColor))
                    Text(name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 4)
            }
            Spacer(minLength: 6)
            if let last = store.lastUpdate {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Format.ago(last, now: context.date))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            FooterButton(help: "Aktualisieren") {
                if store.loading.isEmpty {
                    Image(systemName: "arrow.clockwise")
                } else {
                    ProgressView().controlSize(.mini)
                }
            } action: {
                store.refresh(manual: true)
            }
            FooterButton(help: "Einstellungen (⌘,)") {
                Label("Einstellungen", systemImage: "gearshape")
            } action: {
                openSettings()
            }
        }
        .padding(.horizontal, Self.inset - 4)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5))
    }
}

private struct TabButton: View {
    let title: String
    let severity: Severity?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(severity?.color ?? Color.secondary.opacity(0.4))
                    .frame(width: 5, height: 5)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 9)
            .overlay(alignment: .bottom) {
                Rectangle().fill(isActive ? Color.accentColor : .clear).frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FooterButton<Content: View>: View {
    let help: String
    @ViewBuilder let content: Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 7)
                .frame(minWidth: 26, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

// MARK: - Seiten „Limits“ und „Verbrauch“

private enum Page: String, CaseIterable {
    case limits = "Limits", usage = "Verbrauch"
}

/// Schlanker Umschalter in der Kopfzeile – bewusst leiser als ein Segmented Control.
private struct PageSwitch: View {
    @Binding var selection: Page

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Page.allCases, id: \.self) { option in
                let isOn = option == selection
                Button { selection = option } label: {
                    Text(option.rawValue)
                        .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
        .animation(.easeOut(duration: 0.12), value: selection)
    }
}

private struct ProviderPage: View {
    let provider: any UsageProvider
    let page: Page
    let state: UsageStore.ProviderState
    let isLoading: Bool
    let consumption: ConsumptionStore
    let showMoney: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(provider.displayName).font(.system(size: 13, weight: .bold))
                if let plan = state.snapshot?.account?.plan {
                    Text(plan).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                if page == .limits, let tightest = state.snapshot?.tightestWindow {
                    Text(Format.percent(tightest.percent))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tightest.severity.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(tightest.severity.color))
                }
            }

            if page == .usage {
                UsageView(
                    providerID: provider.id,
                    consumption: consumption,
                    showMoney: showMoney,
                    subscription: SubscriptionPrice.dollars(provider: provider.id, plan: state.snapshot?.account?.plan)
                )
            } else {
                limits
            }
        }
        .padding(.horizontal, PopoverView.inset)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var limits: some View {
            StatusLine(state: state)

            if let snapshot = state.snapshot {
                VStack(spacing: 18) {
                    ForEach(snapshot.windows) { MeterRow(window: $0) }
                }
                if !snapshot.extras.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        ForEach(snapshot.extras) { extra in
                            Text(extra.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        }
                    }
                }
            } else if isLoading {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.padding(.vertical, 20)
            }
    }
}

/// Hinweis bei Rate-Limit oder Fehler – die letzten Werte bleiben darunter sichtbar.
private struct StatusLine: View {
    let state: UsageStore.ProviderState

    var body: some View {
        if let retryAt = state.retryAt, state.isRateLimited {
            label("pause.circle", "Abfrage pausiert (Rate-Limit) · wieder ab \(Format.reset(retryAt))", .warn)
        } else if let error = state.error {
            label("exclamationmark.triangle", state.snapshot == nil ? error : "\(error) Zeige letzten Stand.", .crit)
        }
    }

    private func label(_ symbol: String, _ text: String, _ severity: Severity) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11))
            .foregroundStyle(severity.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Eine Meter-Zeile mit Balken, Pace-Marke und Reset-Zeit (SPEC §3.4).
private struct MeterRow: View {
    let window: LimitWindow

    var body: some View {
        let elapsed = window.elapsedFraction()
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name).font(.system(size: 12.5, weight: .semibold))
                    + Text(window.scopeNote.map { "  \($0)" } ?? "").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Text(Format.percent(window.percent))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(window.severity.color)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(window.severity.color)
                        .frame(width: geo.size.width * min(max(window.percent, 0), 1))
                    if let elapsed {
                        Rectangle()
                            .fill(.primary.opacity(0.45))
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * elapsed - 1)
                    }
                }
            }
            .frame(height: 6)
            HStack {
                if let resetsAt = window.resetsAt { Text("Reset \(Format.reset(resetsAt))") }
                Spacer()
                if let elapsed { Text(Format.pace(percent: window.percent, elapsed: elapsed)) }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}
