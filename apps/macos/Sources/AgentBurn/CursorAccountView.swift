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
  @Environment(UsageStore.self) private var store
  let account: CursorAccount?
  let plan: SubscriptionAgent?
  @State private var range = QuotaChartRange.rtd
  private var promoForecast: Forecast? {
    cursorMeterForecast(
      account: account, now: store.quotaCheckDate, stored: store.forecast(for: "cursor"))
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Label("Cursor " + (plan?.plan ?? "compte"), systemImage: "creditcard")
            .font(.headline)
          Spacer()
          if let price = plan?.pricePerMonth {
            Text(planPrice(price) + " / mois " + planPriceTaxNote)
              .foregroundStyle(.secondary).help(planPriceExplanation)
          }
        }
        if let account {
          if let forecast = promoForecast, cursorHasPromotionalCredits(account) {
            promoMeter(forecast, account: account)
          } else {
            allowanceAndBilling(account)
            grantBars(account)
          }
          Text(
            "L'enveloppe de l'offre, les crédits promotionnels et la valeur équivalente API sont trois soldes distincts. Un montant de facturation absent n'est pas compté comme zéro."
          )
          .font(.caption).foregroundStyle(.secondary)
        } else {
          Text(
            "Soldes du compte indisponibles. Actualise avec les données en direct activées pour récupérer l'enveloppe, les crédits et le cycle de facturation de Cursor."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }.padding(12)
    }
  }

  @ViewBuilder private func promoMeter(_ forecast: Forecast, account: CursorAccount) -> some View {
    HStack(alignment: .top, spacing: 28) {
      QuotaSummary(
        forecast: forecast,
        samples: store.samples(for: "cursor", range: range, now: store.quotaCheckDate),
        now: store.quotaCheckDate,
        stale: !forecast.isFresh(at: store.quotaCheckDate)
          || store.quotaError(for: "cursor") != nil,
        staleHelp: store.quotaError(for: "cursor")
          ?? "Dernière mesure connue affichée. Mise à jour en attente.",
        rates: store.blendRates(for: "cursor"),
        style: .promotionalCredits
      )
      .frame(width: 236, alignment: .leading)
      VStack(alignment: .trailing, spacing: 8) {
        QuotaChartRangePicker(range: $range)
        QuotaChart(
          forecast: forecast,
          samples: store.samples(for: "cursor", range: range, now: store.quotaCheckDate),
          color: BurnTheme.color(for: "cursor"),
          range: range, now: store.quotaCheckDate,
          resetLabel: QuotaMeterStyle.promotionalCredits.chartResetLabel
        )
        .id(range)
      }
    }
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Crédits promotionnels").font(.subheadline.weight(.medium))
        Text("Expiration " + date(account.grants.first { $0.kind == "promo" }?.expiresAtMs))
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
Text(account.activeRemainingUSD.map(currency) ?? "Indisponible")
          .font(.title2.weight(.semibold)).monospacedDigit()
        Text("restants sur " + (account.activeLimitUSD.map(currency) ?? "un plafond inconnu"))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    if unusedIncludedWhileCreditsRemain(account) {
      Text("L'enveloppe incluse n'est pas entamée tant qu'il reste des crédits promotionnels.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func allowanceAndBilling(_ account: CursorAccount) -> some View {
    HStack(alignment: .top, spacing: 28) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Enveloppe incluse").font(.subheadline.weight(.medium))
        Text(account.includedRemainingUSD.map(currency) ?? "Indisponible")
          .font(.title.weight(.semibold)).monospacedDigit()
        Text("restants sur " + (account.includedLimitUSD.map(currency) ?? "un plafond inconnu"))
          .font(.caption).foregroundStyle(.secondary)
        if let used = account.includedPercentUsed {
          ProgressView(value: used, total: 100).tint(.purple)
          Text(
            used.formatted(.number.precision(.fractionLength(1)).locale(burnLocale))
              + "% utilisés · rapporté par Cursor"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      Divider()
      VStack(alignment: .leading, spacing: 8) {
        Text("Cycle de facturation").font(.subheadline.weight(.medium))
        Text("Renouvellement " + date(account.billingCycleEndMs)).font(.subheadline)
        Text("Début " + date(account.billingCycleStartMs))
          .font(.caption).foregroundStyle(.secondary)
        Text("Dépense à la demande : " + (account.onDemandSpentUSD.map(currency) ?? "non communiquée"))
          .font(.caption).foregroundStyle(.secondary)
        Text("Plafond à la demande : " + (account.onDemandLimitUSD.map(currency) ?? "non communiqué"))
          .font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private func grantBars(_ account: CursorAccount) -> some View {
    ForEach(Array(account.grants.enumerated()), id: \.offset) { _, grant in
      Divider()
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(grant.kind == "promo" ? "Crédits promotionnels" : "Crédits du compte")
            .font(.subheadline.weight(.medium))
          Text("Expiration " + date(grant.expiresAtMs)).font(.caption).foregroundStyle(
            .secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
          Text(grant.remainingUSD.map(currency) ?? "Indisponible")
            .font(.title2.weight(.semibold)).monospacedDigit()
          Text("restants sur " + (grant.totalUSD.map(currency) ?? "un plafond inconnu"))
            .font(.caption).foregroundStyle(.secondary)
          if let used = grantUsedPercent(grant) {
            ProgressView(value: used, total: 100)
            Text(
              used.formatted(.number.precision(.fractionLength(1)).locale(burnLocale)) + "% utilisés"
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func date(_ milliseconds: Double?) -> String {
    guard let milliseconds else { return "indisponible" }
    return Date(timeIntervalSince1970: milliseconds / 1000).formatted(
      Date.FormatStyle(date: .abbreviated, time: .omitted, locale: burnLocale))
  }
}

private func unusedIncludedWhileCreditsRemain(_ account: CursorAccount) -> Bool {
  (account.includedPercentUsed ?? 0) == 0
    && account.grants.contains { ($0.remainingUSD ?? 0) > 0 }
}

private func grantUsedPercent(_ grant: CursorCreditGrant) -> Double? {
  guard let remaining = grant.remainingUSD, let total = grant.totalUSD, total > 0 else {
    return nil
  }
  return max(0, min(100, (total - remaining) / total * 100))
}
