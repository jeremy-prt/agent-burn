import SwiftUI

struct MenuPopover: View {
  @Environment(UsageStore.self) private var store
  @Environment(\.openWindow) private var openWindow
  private var tab: String { store.selection }

  var body: some View {
    @Bindable var store = store
    VStack(spacing: 0) {
      HStack {
        Label("Agent Burn", systemImage: "flame.fill").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(BurnTheme.ink)
        Spacer()
        SettingsLink { Image(systemName: "gearshape") }
          .buttonStyle(.plain).foregroundStyle(BurnTheme.muted).help("Réglages")
          .accessibilityLabel("Réglages")
          .frame(minWidth: 24, minHeight: 24)
      }.padding(.horizontal, 22).padding(.top, 19).padding(.bottom, 17)
      HarnessTabs(selection: $store.selection)
        .padding(4)
        .padding(.horizontal, 18).padding(.bottom, 20)
      ScrollView {
        Group {
          if tab == "summary" {
            OverviewView(compact: true)
          } else if ["codex", "claude"].contains(tab) {
            HarnessView(agent: tab, compact: true)
          } else {
            SourceUsageView(agent: tab, compact: true)
          }
        }.padding(.horizontal, 22).padding(.bottom, 20)
      }.frame(height: ["codex", "claude"].contains(tab) ? 440 : 520)
      Rectangle().fill(BurnTheme.line).frame(height: 1)
      VStack(spacing: 10) {
        RefreshFooter(source: ["codex", "claude"].contains(tab) ? tab : "summary", compact: true)
        HStack {
          Button {
            store.selection = tab
            openWindow(id: "overview")
            NSApp.activate(ignoringOtherApps: true)
          } label: {
            HStack {
              Text("Ouvrir le tableau de bord")
              Spacer()
              Image(systemName: "arrow.up.right")
            }.font(.system(size: 12, weight: .medium))
              .padding(.horizontal, 12).padding(.vertical, 10)
              .background(BurnTheme.elevated, in: RoundedRectangle(cornerRadius: 7))
          }.buttonStyle(.plain)
          Button {
            NSApp.terminate(nil)
          } label: {
            Image(systemName: "power")
          }
          .buttonStyle(.plain).foregroundStyle(BurnTheme.muted).help("Quitter Agent Burn")
          .accessibilityLabel("Quitter Agent Burn").padding(.leading, 8)
        }
      }.padding(18)
    }
    .frame(width: 440).background(.regularMaterial).foregroundStyle(BurnTheme.ink)
  }

}

struct DashboardView: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    VStack(spacing: 0) {
      ScrollView {
        NativeUsageView(agent: store.selection == "summary" ? nil : store.selection)
          .padding(24).frame(maxWidth: 1280).frame(maxWidth: .infinity)
      }
      Divider()
      RefreshFooter(source: "summary").padding(.horizontal, 20).padding(.vertical, 9)
    }
    .frame(minWidth: 900, minHeight: 650)
    .background(BurnTheme.background)
    .toolbar {
      ToolbarItem(placement: .principal) {
        HarnessTabs(selection: $store.selection)
          .padding(.horizontal, 6)
          .fixedSize(horizontal: true, vertical: false)
      }
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          Task { await store.refreshAll() }
        } label: {
          Label("Actualiser", systemImage: "arrow.clockwise")
        }
        .help("Actualiser l'utilisation et les quotas en direct")
        SettingsLink { Label("Réglages", systemImage: "gearshape") }.help("Réglages")
      }
    }
  }
}

struct HarnessTabs: View {
  @Environment(UsageStore.self) private var store
  @Binding var selection: String
  private static let pinned = ["summary", "claude", "codex", "cursor"]
  /// Harnesses détectés en plus des quatre onglets fixes (OpenCode, Pi...).
  private var others: [String] {
    store.knownAgents.filter { !Self.pinned.contains($0) }
  }
  var body: some View {
    HStack(spacing: 8) {
      Picker("Harness", selection: $selection) {
        Text("Général").tag("summary")
        Text("Claude").tag("claude")
        Text("Codex").tag("codex")
        Text("Cursor").tag("cursor")
      }.pickerStyle(.segmented).labelsHidden()
      if !others.isEmpty {
        Menu {
          ForEach(others, id: \.self) { agent in Button(harnessName(agent)) { selection = agent } }
        } label: {
          HStack(spacing: 4) {
            Text(others.contains(selection) ? harnessName(selection) : "Autres")
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
          }
        }
        .menuIndicator(.hidden)
        .fixedSize()
      }
    }.controlSize(.regular)
  }

}

struct QuotaSourceSettings: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    Section("Quota dans la barre des menus") {
      Picker("Afficher le restant de", selection: $store.quotaSource) {
        ForEach(QuotaSource.allCases) { source in
          Text(source.label).tag(source)
        }
      }
      Text(
        "La flamme de la barre des menus affiche ce pourcentage restant. Codex s'appuie sur le compteur hebdomadaire de ton compte, Claude sur sa limite hebdomadaire, et Cursor sur les crédits promotionnels tant qu'il en reste, sinon sur l'enveloppe incluse."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct SettingsView: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    Form {
      LoginItemSettings()
      AppearanceSettings()
      CurrencySettings()
      QuotaSourceSettings()
      UpdateSettings()
      Section("Source des données") {
        TextField("Exécutable du CLI", text: $store.customPath, prompt: Text("agent-burn intégré"))
          .help("Chemin absolu vers l'exécutable agent-burn natif")
        Button("Choisir l'exécutable…") {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = false
          panel.allowsMultipleSelection = false
          panel.message = "Choisis l'exécutable agent-burn natif."
          if panel.runModal() == .OK, let url = panel.url { store.customPath = url.path }
        }
        Toggle("Utiliser les tarifs et limites en cache", isOn: $store.offline)
        Text(
          "Le mode cache évite les requêtes vers les abonnements en direct. Sinon, le CLI peut interroger les fournisseurs de tarifs et de harness."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Dossiers de logs") {
        TextField("Dossiers Codex", text: $store.codexHomes, axis: .vertical)
          .lineLimit(2...4).font(.system(.caption, design: .monospaced))
        Text(
          "Dossiers Codex séparés par des virgules. Le dossier ~/.codex habituel est inclus en plus du profil de lancement. Les sessions et les sessions archivées sont lues par le CLI."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Actualisation") {
        Picker("Actualiser automatiquement", selection: $store.refreshMinutes) {
          Text("Chaque minute").tag(1)
          Text("Toutes les 5 minutes").tag(5)
          Text("Toutes les 15 minutes").tag(15)
          Text("Toutes les 30 minutes").tag(30)
        }
        Button(store.isLoading ? "Actualisation…" : "Appliquer et actualiser") {
          Task { await store.refreshAll() }
        }
      }
      QuotaCollectionSettings()
    }
    .formStyle(.grouped).padding(12).frame(width: 560, height: 520)
  }
}
