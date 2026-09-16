import ServiceManagement
import SwiftUI

enum QuotaService {
  static let plistName = "dev.melvynx.agent-burn.quota.plist"
  static var service: SMAppService { .agent(plistName: plistName) }

  /// Refresh the ServiceManagement registration so an app replacement never
  /// leaves launchd pointing at the previous signed bundle.
  static func registerForCurrentBundle() async throws {
    if service.status == .enabled {
      try await service.unregister()
    }
    try service.register()
  }
}

struct QuotaCollectionSettings: View {
  @AppStorage("backgroundQuotas") private var enabled = true
  @State private var item = LoginItem(
    readStatus: { QuotaService.service.status },
    register: { try QuotaService.service.register() },
    unregister: { try await QuotaService.service.unregister() })

  var body: some View {
    Section("Historique des quotas en arrière-plan") {
      Toggle(
        "Relever les quotas toutes les 10 minutes",
        isOn: Binding(
          get: { item.isEnabled },
          set: { value in
            enabled = value
            Task { await item.setEnabled(value) }
          })
      )
      .disabled(item.isUpdating)
      Text(
        "Alimente la courbe de rythme même quand l'app est fermée. Anthropic limite ces appels : dix minutes est l'intervalle qui tient sans se faire bloquer."
      )
      .font(.caption).foregroundStyle(.secondary)
      if item.requiresApproval {
        Text("Autorise Agent Burn à s'exécuter en arrière-plan dans les Réglages Système pour activer le relevé.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Ouvrir les réglages d'ouverture…") { SMAppService.openSystemSettingsLoginItems() }
      }
      if let error = item.errorMessage {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
    .onAppear { item.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      item.refresh()
    }
  }
}
