import SwiftUI

@main
enum AgentBurnMain {
  @MainActor static func main() async {
    if CommandLine.arguments.contains("--collect-quotas") {
      do { try await QuotaCollector.collect() } catch {
        FileHandle.standardError.write(
          Data("Quota collection failed: \(error.localizedDescription)\n".utf8))
        exit(1)
      }
    } else {
      AgentBurnApp.main()
    }
  }
}

struct AgentBurnApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store: UsageStore
  @Bindable private var appearance = AppAppearance.shared

  init() {
    let store = UsageStore()
    _store = State(initialValue: store)
    Task { await store.start() }
    Task { await CurrencyRate.shared.refreshIfNeeded() }
  }
  var body: some Scene {
    Window("Agent Burn", id: "overview") {
      DashboardView().environment(store).environment(\.locale, burnLocale)
    }
    .defaultSize(width: 1060, height: 780)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unified)
    .commands { UpdateCommands() }
    MenuBarExtra(isInserted: $appearance.menuBarVisible) {
      MenuPopover().environment(store).environment(\.locale, burnLocale)
    } label: {
      // TimelineView in a MenuBarExtra label can continuously invalidate the status item.
      MenuBarLabel(
        remaining: store.remainingPercent, stale: store.quotaIsStale(at: store.quotaCheckDate))
    }
    .menuBarExtraStyle(.window)
    Settings { SettingsView().environment(store).environment(\.locale, burnLocale) }
  }
}

struct MenuBarLabel: View {
  let remaining: Double?
  var stale = false
  var body: some View {
    HStack(spacing: 4) {
      Image(nsImage: AppLogo.menuBar)
        .resizable()
        .renderingMode(.original)
        .frame(width: 18, height: 18)
      Text(menuBarQuotaText(remaining, stale: stale)).monospacedDigit()
    }
    .accessibilityLabel("Agent Burn \(menuBarQuotaText(remaining, stale: stale))")
  }
}
