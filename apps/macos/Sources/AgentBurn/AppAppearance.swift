import AppKit
import Observation
import SwiftUI

@Observable @MainActor final class AppAppearance {
  static let shared = AppAppearance()
  private let defaults: UserDefaults
  private let applyPolicy: (NSApplication.ActivationPolicy) -> Void

  var menuBarOnly: Bool {
    didSet {
      defaults.set(menuBarOnly, forKey: "menuBarOnly")
      apply()
    }
  }

  /// Présence de l'icône Agent Burn dans la barre des menus.
  var menuBarVisible: Bool {
    didSet {
      defaults.set(menuBarVisible, forKey: "menuBarVisible")
      // Sans icône dans la barre des menus, l'app doit rester joignable par le Dock.
      if !menuBarVisible, menuBarOnly { menuBarOnly = false }
    }
  }

  init(
    defaults: UserDefaults = .standard,
    applyPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = {
      NSApplication.shared.setActivationPolicy($0)
    }
  ) {
    self.defaults = defaults
    self.applyPolicy = applyPolicy
    menuBarOnly = defaults.bool(forKey: "menuBarOnly")
    menuBarVisible = defaults.object(forKey: "menuBarVisible") as? Bool ?? true
  }

  func apply() { applyPolicy(menuBarOnly ? .accessory : .regular) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.applicationIconImage = AppLogo.window
    applyWindowLogo()
    AppAppearance.shared.apply()
    if AppAppearance.shared.menuBarOnly {
      // SwiftUI has finished creating its initial dashboard at this point.
      for window in NSApplication.shared.windows where window.title == "Agent Burn" {
        window.orderOut(nil)
      }
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) { applyWindowLogo() }

  private func applyWindowLogo() {
    for window in NSApplication.shared.windows where window.title == "Agent Burn" {
      window.representedURL = Bundle.main.bundleURL
      window.standardWindowButton(.documentIconButton)?.image = AppLogo.window
    }
  }

  /// Sans icône dans la barre des menus, la fenêtre est le seul accès à l'app :
  /// la fermer doit donc quitter, comme pour n'importe quelle app à fenêtre.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    !AppAppearance.shared.menuBarVisible
  }
}

struct AppearanceSettings: View {
  @Bindable private var appearance = AppAppearance.shared
  var body: some View {
    Section("Apparence") {
      Toggle("Icône dans la barre des menus", isOn: $appearance.menuBarVisible)
      Text(
        "Affiche Agent Burn et son quota restant dans la barre des menus. Décoche pour n'utiliser que la fenêtre du tableau de bord."
      )
      .font(.caption).foregroundStyle(.secondary)
      Toggle("Barre des menus uniquement", isOn: $appearance.menuBarOnly)
        .disabled(!appearance.menuBarVisible)
      Text(
        "Masque Agent Burn du Dock et de Command-Tab : le tableau de bord et les réglages s'ouvrent alors depuis la barre des menus. Ce choix est conservé au redémarrage de l'app."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}
