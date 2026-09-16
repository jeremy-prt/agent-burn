import SwiftUI

struct CompactHarnessView: View {
  @Environment(UsageStore.self) private var store
  let agent: String
  @State private var showsDetails = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        HarnessIcon(agent: agent, size: 22)
        Text(harnessName(agent)).font(.system(size: 13, weight: .semibold))
        Spacer()
        Text(store.reports[agent]?.plan ?? "Abonnement")
          .font(.system(size: 12)).foregroundStyle(BurnTheme.quotaMuted).lineLimit(1)
      }

      if let forecast = store.forecast(for: agent) {
        let range = store.chartRange(for: agent)
        QuotaSummary(
          forecast: forecast,
          samples: store.samples(
            for: agent, range: range, now: store.quotaCheckDate),
          now: store.quotaCheckDate,
          stale: !forecast.isFresh(at: store.quotaCheckDate)
            || store.quotaError(for: agent) != nil,
          staleHelp: store.quotaError(for: agent)
            ?? "Dernière mesure connue affichée. Mise à jour en attente.",
          compact: true,
          availableResets: store.reports[agent]?.resetCreditsAvailable,
          rates: store.blendRates(for: agent)
        )
        QuotaChart(
          forecast: forecast,
          samples: store.samples(
            for: agent, range: range, now: store.quotaCheckDate),
          color: BurnTheme.quotaColor(for: agent), compact: true,
          range: range, now: store.quotaCheckDate)

        if let short = store.summary?.subscription?.agents.first(where: { $0.agent == agent })?
          .shortWindow
        {
          detail(
            "Limite \(short.label)",
            "\(max(0, 100 - short.usedPercent).formatted(.number.precision(.fractionLength(0)).locale(burnLocale)))% restants"
          )
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Text(store.isLoading ? "Lecture de l'utilisation…" : "Quota indisponible")
            .font(.system(size: 24, weight: .semibold))
          Text(
            store.isLoading
              ? "Chargement de tes limites d'abonnement."
              : "Connecte-toi à \(harnessName(agent)), lance une session, puis actualise."
          )
          .font(.system(size: 13)).foregroundStyle(BurnTheme.quotaMuted)
          .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
      }

      if let error = store.errors[agent] { ReportNotice(message: error) }
      if let error = store.errors["quotaService"] { ReportNotice(message: error) }
      if let error = store.errors["history"] { ReportNotice(message: error) }

      if let report = store.reports[agent] {
        let rates = store.blendRates(for: agent)
        DisclosureGroup("Détail de l'utilisation", isExpanded: $showsDetails) {
          VStack(alignment: .leading, spacing: 12) {
            detail("Équivalent API · 30 jours", currency(report.apiEquivalentPerMonth))
            if let price = report.pricePerMonth {
              detail("Offre mensuelle \(planPriceTaxNote)", planPrice(price))
            }
            if let forecast = store.forecast(for: agent) {
              detail(
                "Rythme quotidien conseillé",
                "\(forecast.dailyAllowance.formatted(.number.precision(.fractionLength(1)).locale(burnLocale)))%\u{00A0}/ jour"
              )
            }
            if let dollars = quotaDollarsPerPercentLabel(rates?.dollarsPerPercent) {
              detail("Moyenne \(currencySymbol) / %", dollars)
            }
            if let tokensPer = quotaTokensPerCurrencyLabel(rates?.tokensPerDollar) {
              detail("Tokens par \(currencySymbol)", tokensPer)
            }
            ForEach(Array(report.topModels.prefix(2))) { model in
              detail(model.model, currency(model.cost))
            }
          }.padding(.top, 12)
        }
        .font(.system(size: 12)).tint(BurnTheme.quotaMuted)
      }
    }
  }

  private func detail(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).foregroundStyle(BurnTheme.quotaMuted).lineLimit(1)
      Spacer(minLength: 12)
      Text(value).monospacedDigit().lineLimit(1)
    }.font(.system(size: 12))
  }
}
