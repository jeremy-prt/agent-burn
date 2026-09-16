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
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(
            "Ton abonnement : Claude " + (plan?.plan ?? "compte"),
            systemImage: "gauge.with.dots.needle.33percent"
          )
          .font(.headline)
          Spacer()
          if let price = plan?.pricePerMonth {
            Text(planPrice(price) + " / mois " + planPriceTaxNote)
              .foregroundStyle(.secondary).help(planPriceExplanation)
          }
        }
        if let account {
          // Une seule rangée : les quatre compteurs tiennent dans la largeur.
          HStack(alignment: .top, spacing: 0) {
            meter(
              title: "Session · 5 h", used: account.sessionUsedPercent,
              reset: account.sessionResetsAtMs, showsTime: true,
              help:
                "Fenêtre glissante de 5 heures. C'est elle qui te coupe en pleine session : si elle descend vite, ralentis ou passe sur un modèle plus léger."
            )
            separator
            meter(
              title: "Semaine · 7 j", used: account.weeklyUsedPercent,
              reset: account.weeklyResetsAtMs, showsTime: true,
              help:
                "Limite hebdomadaire tous modèles confondus. C'est le budget à faire durer jusqu'à la réinitialisation."
            )
            ForEach(account.scoped) { window in
              separator
              meter(
                title: window.name + " · 7 j", used: window.usedPercent,
                reset: window.resetsAtMs, showsTime: true,
                help:
                  "Limite hebdomadaire réservée au modèle \(window.name), comptée séparément de la limite globale."
              )
            }
            if showsExtra(account) {
              separator
              extraMeter(account)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
        } else {
          Label(
            claudeAccountUnavailableMessage(unavailableReason),
            systemImage: unavailableReason == "rate-limited"
              ? "clock.arrow.circlepath" : "exclamationmark.triangle"
          )
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }.padding(12)
    }
  }

  private var separator: some View {
    Divider().frame(height: 62)
  }

  /// Un compteur compact : restant, jauge colorée par le niveau, date de reset.
  private func meter(
    title: String, used: Double?, reset: Double?, showsTime: Bool = false, help: String
  ) -> some View {
    let remaining = used.map { max(0, min(100, 100 - $0)) }
    // Même lecture que Claude Code : le chiffre et la barre montent avec la conso.
    return VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
      Text(usedLabel(used))
        .font(.system(size: 22, weight: .semibold, design: .rounded))
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
      ProgressView(value: used ?? 0, total: 100).tint(meterTint(remaining))
      Text(remainingAndReset(remaining: remaining, reset: reset, showsTime: showsTime))
        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .help(help)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(remainingLabel(used) + " restants")
    .accessibilityHint(help)
  }

  /// Usage supplémentaire : un montant, pas un pourcentage de quota.
  private func extraMeter(_ account: ClaudeAccount) -> some View {
    let used = extraUsedPercent(account)
    return VStack(alignment: .leading, spacing: 5) {
      Text("Usage supp.").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
      Text(account.extraUsedUSD.map(currency) ?? "—")
        .font(.system(size: 22, weight: .semibold, design: .rounded))
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
      ProgressView(value: used ?? 0, total: 100).tint(.blue)
      Text(
        account.extraLimitUSD.map { "sur " + currency($0) }
          ?? (account.extraEnabled == true ? "activé" : "plafond inconnu")
      )
      .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .help(
      "Dépense facturée au-delà de ton abonnement, une fois les limites atteintes. Tant que c'est à zéro, tu n'as rien payé en plus."
    )
  }

  /// « 88 % restants · réinit. 13:20 » sous le pourcentage consommé.
  private func remainingAndReset(remaining: Double?, reset: Double?, showsTime: Bool) -> String {
    var parts: [String] = []
    if let remaining {
      parts.append(
        remaining.formatted(.number.precision(.fractionLength(0)).locale(burnLocale))
          + " % restants")
    }
    if reset != nil { parts.append("réinit. " + date(reset, time: showsTime)) }
    return parts.isEmpty ? " " : parts.joined(separator: " · ")
  }

  /// Vert : de la marge. Orange : à surveiller. Rouge : bientôt bloqué.
  private func meterTint(_ remaining: Double?) -> Color {
    guard let remaining else { return .secondary }
    if remaining < 15 { return .red }
    if remaining < 40 { return .orange }
    return BurnTheme.green
  }

  private func date(_ milliseconds: Double?, time: Bool = false) -> String {
    guard let milliseconds else { return "indisponible" }
    let date = Date(timeIntervalSince1970: milliseconds / 1000)
    guard time else {
      return date.formatted(.dateTime.day().month(.abbreviated).locale(burnLocale))
    }
    return date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(burnLocale))
  }
}

/// Pourcentage consommé, la convention qu'affiche Claude Code.
func usedLabel(_ used: Double?) -> String {
  guard let used else { return "—" }
  return max(0, min(100, used)).formatted(
    .number.precision(.fractionLength(1)).locale(burnLocale)) + "%"
}

func remainingLabel(_ used: Double?) -> String {
  guard let used else { return "Indisponible" }
  return max(0, min(100, 100 - used)).formatted(
    .number.precision(.fractionLength(1)).locale(burnLocale)) + "%"
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
