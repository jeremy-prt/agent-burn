import SwiftUI

/// En-tête Codex, calqué sur celui de Claude : une rangée de compteurs
/// compacts au-dessus de la courbe de rythme.
struct CodexAccountView: View {
  @Environment(UsageStore.self) private var store
  let plan: SubscriptionAgent?

  private var forecast: Forecast? { store.forecast(for: "codex") }

  var body: some View {
    HarnessAccountBox(
      title: "Ton abonnement : Codex " + (plan?.plan ?? "compte"),
      systemImage: "gauge.with.dots.needle.33percent", plan: plan
    ) {
      if items.isEmpty {
        Label(
          store.isLoading
            ? "Lecture de tes limites Codex…"
            : "Limites du compte indisponibles : connecte-toi à Codex et lance une session.",
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        MeterRow(items: items)
      }
    }
  }

  private var items: [MeterItem] {
    var list: [MeterItem] = []
    if let short = plan?.shortWindow {
      list.append(
        MeterItem(
          id: "session", title: "Session · " + short.label, usedPercent: short.usedPercent,
          caption: meterCaption(used: short.usedPercent, reset: nil),
          help:
            "Fenêtre courte de Codex. C'est elle qui te coupe en pleine session : si elle monte vite, ralentis."
        ))
    }
    if let forecast {
      list.append(
        MeterItem(
          id: "weekly", title: "Semaine · 7 j", usedPercent: forecast.window.usedPercent,
          caption: meterCaption(
            used: forecast.window.usedPercent, reset: forecast.reset, showsTime: true),
          help:
            "Limite hebdomadaire de ton offre Codex. C'est le budget à faire durer jusqu'à la réinitialisation."
        ))
    }
    if let credits = store.reports["codex"]?.resetCreditsAvailable, credits > 0 {
      list.append(
        MeterItem(
          id: "resets", title: "Réinitialisations",
          amount: credits.formatted(.number.locale(burnLocale)),
          caption: "en réserve",
          help:
            "Réinitialisations de limite que tu peux utiliser maintenant pour repartir sur un quota neuf.",
          accent: .blue
        ))
    }
    return list
  }
}
