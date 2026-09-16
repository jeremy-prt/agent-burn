import SwiftUI

struct CursorAccount: Codable, Sendable {
  let billingCycleStartMs: Double?
  let billingCycleEndMs: Double?
  let includedLimitUSD: Double?
  let includedRemainingUSD: Double?
  let includedPercentUsed: Double?
  let includedSpendUSD: Double?
  let bonusSpendUSD: Double?
  let planSpendUSD: Double?
  let onDemandSpentUSD: Double?
  let onDemandLimitUSD: Double?
  let activeLimitUSD: Double?
  let activeRemainingUSD: Double?
  let activePercentUsed: Double?
  let grants: [CursorCreditGrant]
}

struct CursorCreditGrant: Codable, Sendable {
  let kind: String?
  let totalUSD: Double?
  let remainingUSD: Double?
  let expiresAtMs: Double?
}

struct CursorAccountView: View {
  let account: CursorAccount?
  let plan: SubscriptionAgent?

  var body: some View {
    HarnessAccountBox(
      title: "Ton abonnement : Cursor " + (plan?.plan ?? "compte"),
      systemImage: "creditcard", plan: plan
    ) {
      if account == nil {
        Label(
          "Soldes du compte indisponibles : actualise avec les données en direct activées.",
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
    guard let account else { return [] }
    var list: [MeterItem] = []
    if let promo = account.grants.first(where: { $0.kind == "promo" && ($0.remainingUSD ?? 0) > 0 })
    {
      list.append(
        MeterItem(
          id: "promo", title: "Crédits promo",
          usedPercent: grantUsedPercent(promo),
          amount: promo.remainingUSD.map(currency) ?? "—",
          caption: [
            promo.totalUSD.map { "sur " + currency($0) },
            meterDate(milliseconds: promo.expiresAtMs).map { "exp. " + meterDate($0) },
          ].compactMap { $0 }.joined(separator: " · "),
          help:
            "Crédits offerts par Cursor. Ils sont consommés avant l'enveloppe incluse de ton offre."
        ))
    }
    list.append(
      MeterItem(
        id: "included", title: "Enveloppe incluse",
        usedPercent: account.includedPercentUsed,
        amount: account.includedRemainingUSD.map(currency) ?? "—",
        caption: account.includedLimitUSD.map { "sur " + currency($0) } ?? "plafond inconnu",
        help:
          "Montant d'utilisation compris dans ton abonnement. Il n'est pas entamé tant qu'il reste des crédits promotionnels."
      ))
    if account.onDemandSpentUSD != nil || account.onDemandLimitUSD != nil {
      let used = zip2Percent(account.onDemandSpentUSD, account.onDemandLimitUSD)
      list.append(
        MeterItem(
          id: "ondemand", title: "À la demande",
          usedPercent: used,
          amount: account.onDemandSpentUSD.map(currency) ?? "—",
          caption: account.onDemandLimitUSD.map { "plafond " + currency($0) } ?? "plafond inconnu",
          help:
            "Dépense facturée au-delà de l'enveloppe incluse. Tant que c'est à zéro, tu n'as rien payé en plus.",
          accent: .blue
        ))
    }
    if let renews = meterDate(milliseconds: account.billingCycleEndMs) {
      list.append(
        MeterItem(
          id: "cycle", title: "Cycle de facturation",
          amount: meterDate(renews),
          caption: meterDate(milliseconds: account.billingCycleStartMs).map {
            "depuis le " + meterDate($0)
          } ?? "",
          help: "Date de renouvellement de ton abonnement Cursor.",
          accent: .secondary
        ))
    }
    return list
  }
}

/// Pourcentage consommé d'une enveloppe exprimée en argent.
private func zip2Percent(_ spent: Double?, _ limit: Double?) -> Double? {
  guard let spent, let limit, limit > 0 else { return nil }
  return max(0, min(100, spent / limit * 100))
}

func grantUsedPercent(_ grant: CursorCreditGrant) -> Double? {
  guard let remaining = grant.remainingUSD, let total = grant.totalUSD, total > 0 else {
    return nil
  }
  return max(0, min(100, (total - remaining) / total * 100))
}
