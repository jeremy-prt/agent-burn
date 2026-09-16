import Combine
import Sparkle
import SwiftUI

@MainActor final class AppUpdater: ObservableObject {
  static let shared = AppUpdater()
  private let controller: SPUStandardUpdaterController
  @Published private(set) var canCheck = false
  private var observation: AnyCancellable?

  private init() {
    // Plain SwiftPM executables and render tests have no update configuration.
    let configured = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    controller = SPUStandardUpdaterController(
      startingUpdater: configured, updaterDelegate: nil, userDriverDelegate: nil)
    observation = controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.canCheck = $0 }
  }

  var automaticallyChecks: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set { controller.updater.automaticallyChecksForUpdates = newValue }
  }

  func check() { controller.checkForUpdates(nil) }
}

struct UpdateSettings: View {
  @ObservedObject private var updater = AppUpdater.shared
  var body: some View {
    Section("Mises à jour") {
      Toggle(
        "Vérifier automatiquement les mises à jour",
        isOn: Binding(
          get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
      Button("Vérifier les mises à jour…") { updater.check() }.disabled(!updater.canCheck)
      Text("Les mises à jour signées proviennent des releases GitHub du projet open source.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct UpdateCommands: Commands {
  @ObservedObject private var updater = AppUpdater.shared
  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Vérifier les mises à jour…") { updater.check() }.disabled(!updater.canCheck)
    }
  }
}
