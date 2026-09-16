import SwiftUI

struct ClaudeAccount: Codable, Sendable {
  let sessionUsedPercent: Double?
  let sessionResetsAtMs: Double?
  let weeklyUsedPercent: Double?
  let weeklyResetsAtMs: Double?
  var scoped: [ClaudeScopedLimit]
  let extraEnabled: Bool?
  let extraUsedUSD: Double?
  let extraLimitUSD: Double?
  let extraUsedPercent: Double?

  init(
    sessionUsedPercent: Double? = nil, sessionResetsAtMs: Double? = nil,
    weeklyUsedPercent: Double? = nil, weeklyResetsAtMs: Double? = nil,
    scoped: [ClaudeScopedLimit] = [], extraEnabled: Bool? = nil, extraUsedUSD: Double? = nil,
    extraLimitUSD: Double? = nil, extraUsedPercent: Double? = nil
  ) {
    self.sessionUsedPercent = sessionUsedPercent
    self.sessionResetsAtMs = sessionResetsAtMs
    self.weeklyUsedPercent = weeklyUsedPercent
    self.weeklyResetsAtMs = weeklyResetsAtMs
    self.scoped = scoped
    self.extraEnabled = extraEnabled
    self.extraUsedUSD = extraUsedUSD
    self.extraLimitUSD = extraLimitUSD
    self.extraUsedPercent = extraUsedPercent
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sessionUsedPercent = try container.decodeIfPresent(Double.self, forKey: .sessionUsedPercent)
    sessionResetsAtMs = try container.decodeIfPresent(Double.self, forKey: .sessionResetsAtMs)
    weeklyUsedPercent = try container.decodeIfPresent(Double.self, forKey: .weeklyUsedPercent)
    weeklyResetsAtMs = try container.decodeIfPresent(Double.self, forKey: .weeklyResetsAtMs)
    scoped = try container.decodeIfPresent([ClaudeScopedLimit].self, forKey: .scoped) ?? []
    extraEnabled = try container.decodeIfPresent(Bool.self, forKey: .extraEnabled)
    extraUsedUSD = try container.decodeIfPresent(Double.self, forKey: .extraUsedUSD)
    extraLimitUSD = try container.decodeIfPresent(Double.self, forKey: .extraLimitUSD)
    extraUsedPercent = try container.decodeIfPresent(Double.self, forKey: .extraUsedPercent)
  }
}

struct ClaudeScopedLimit: Codable, Sendable, Identifiable {
  let name: String
  let usedPercent: Double?
  let resetsAtMs: Double?
  var id: String { name }
}

struct ClaudeAccountView: View {
  let account: ClaudeAccount?
  let plan: SubscriptionAgent?
  var unavailableReason: String? = nil

  var body: some View {
    HarnessAccountBox(
      title: "Ton abonnement : Claude " + (plan?.plan ?? "compte"),
      systemImage: "gauge.with.dots.needle.33percent", plan: plan
    ) {
      if account != nil {
        MeterRow(items: items)
      } else {
        Label(
          claudeAccountUnavailableMessage(unavailableReason),
          systemImage: unavailableReason == "rate-limited"
            ? "clock.arrow.circlepath" : "exclamationmark.triangle"
        )
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var items: [MeterItem] {
    guard let account else { return [] }
    var list: [MeterItem] = [
      MeterItem(
        id: "session", title: "Session · 5 h", usedPercent: account.sessionUsedPercent,
        caption: meterCaption(
          used: account.sessionUsedPercent,
          reset: meterDate(milliseconds: account.sessionResetsAtMs), showsTime: true),
        help:
          "Fenêtre glissante de 5 heures. C'est elle qui te coupe en pleine session : si elle monte vite, ralentis ou passe sur un modèle plus léger."
      ),
      MeterItem(
        id: "weekly", title: "Semaine · 7 j", usedPercent: account.weeklyUsedPercent,
        caption: meterCaption(
          used: account.weeklyUsedPercent,
          reset: meterDate(milliseconds: account.weeklyResetsAtMs), showsTime: true),
        help:
          "Limite hebdomadaire tous modèles confondus. C'est le budget à faire durer jusqu'à la réinitialisation."
      ),
    ]
    for window in account.scoped {
      list.append(
        MeterItem(
          id: "scoped-" + window.name, title: window.name + " · 7 j",
          usedPercent: window.usedPercent,
          caption: meterCaption(
            used: window.usedPercent, reset: meterDate(milliseconds: window.resetsAtMs),
            showsTime: true),
          help:
            "Limite hebdomadaire réservée au modèle \(window.name), comptée séparément de la limite globale."
        ))
    }
    if showsExtra(account) {
      list.append(
        MeterItem(
          id: "extra", title: "Usage supp.",
          usedPercent: extraUsedPercent(account),
          amount: account.extraUsedUSD.map(currency) ?? "—",
          caption: account.extraLimitUSD.map { "sur " + currency($0) }
            ?? (account.extraEnabled == true ? "activé" : "plafond inconnu"),
          help:
            "Dépense facturée au-delà de ton abonnement, une fois les limites atteintes. Tant que c'est à zéro, tu n'as rien payé en plus.",
          accent: .blue
        ))
    }
    return list
  }
}

func showsExtra(_ account: ClaudeAccount) -> Bool {
  account.extraEnabled == true || account.extraUsedUSD != nil || account.extraLimitUSD != nil
}

func extraUsedPercent(_ account: ClaudeAccount) -> Double? {
  if let used = account.extraUsedPercent { return max(0, min(100, used)) }
  guard let used = account.extraUsedUSD, let limit = account.extraLimitUSD, limit > 0 else {
    return nil
  }
  return max(0, min(100, used / limit * 100))
}

func extraRemaining(_ account: ClaudeAccount, used: Double) -> String {
  account.extraLimitUSD.map { currency(max(0, $0 - used)) } ?? currency(used) + " utilisés"
}
