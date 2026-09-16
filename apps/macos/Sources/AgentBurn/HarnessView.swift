import Charts
import SwiftUI

struct HarnessView: View {
  @Environment(UsageStore.self) private var store
  let agent: String
  var compact = false
  private var color: Color { BurnTheme.color(for: agent) }

  var body: some View {
    if compact {
      CompactHarnessView(agent: agent)
    } else {
      expandedBody
    }
  }

  private var expandedBody: some View {
    VStack(alignment: .leading, spacing: compact ? 20 : 28) {
      HStack(spacing: 10) {
        HarnessIcon(agent: agent)
        VStack(alignment: .leading, spacing: 3) {
          Text(harnessName(agent)).font(.system(size: 15, weight: .semibold))
          Text(store.reports[agent]?.plan ?? "Utilisation de l'abonnement")
            .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        }
        Spacer()
        StatusBadge(
          text: store.errors[agent] != nil
            ? "À vérifier" : store.offline ? "En cache" : "Relevé CLI",
          color: store.errors[agent] != nil ? BurnTheme.accent : color)
      }
      if let error = store.errors[agent] { ReportNotice(message: error) }
      if let error = store.errors["quotaService"] { ReportNotice(message: error) }
      if let report = store.reports[agent] {
        HStack {
          SpendMetric(
            title: "Dépense totale", value: currency(report.apiEquivalentPerMonth),
            detail: "30 derniers jours · équivalent API",
            explanation:
              "Ce que ces tokens auraient coûté au tarif API public, hors taxes. Ce n'est pas ce que tu paies."
          )
          if let price = report.pricePerMonth {
            SpendMetric(
              title: "Offre mensuelle", value: planPrice(price),
              detail: [report.plan, planPriceTaxNote].compactMap { $0 }.joined(separator: " · "),
              explanation: planPriceExplanation)
          }
          if !compact, let economics = report.economics {
            SpendMetric(
              title: "Valeur de l'abonnement",
              value:
                "\(economics.valueMultiple.formatted(.number.precision(.fractionLength(2)).locale(burnLocale))) ×",
              detail: "Utilisation / prix mensuel",
              explanation:
                "Valeur équivalente API divisée par le prix hors taxes de ton offre. À 9 ×, ton utilisation vaut neuf fois ce que tu paies."
            )
          }
        }
        if !compact, let economics = report.economics {
          HStack {
            Text("Équivalent API moins l'offre : \(currency(economics.subsidyPerMonth))")
            Spacer()
            Text(
              "Remise sur le tarif API : \(economics.discountPercent.formatted(.number.precision(.fractionLength(1)).locale(burnLocale)))%"
            )
          }.font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        }
      }
      if let forecast = store.forecast(for: agent) {
        if compact {
          quotaHeader(forecast)
          QuotaChart(
            forecast: forecast, samples: store.samples(for: agent), color: color, compact: true)
        } else {
          HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
              Text("Limite hebdomadaire").font(.system(size: 12)).foregroundStyle(BurnTheme.muted)
              quotaHeader(forecast)
              if !forecast.isLive {
                Text("\(currency(forecast.window.apiEquivalentSpent)) utilisés sur ce cycle")
                  .font(.system(size: 12)).foregroundStyle(BurnTheme.muted)
              }
            }.frame(width: 280, alignment: .leading)
            QuotaChart(forecast: forecast, samples: store.samples(for: agent), color: color)
          }.padding(.vertical, 10)
        }
        resetDetails(forecast)
        if let short = store.summary?.subscription?.agents.first(where: { $0.agent == agent })?
          .shortWindow
        {
          HStack {
            Text("Limite \(short.label)").foregroundStyle(BurnTheme.muted)
            Spacer()
            Text(
              "\(max(0, 100 - short.usedPercent).formatted(.number.precision(.fractionLength(0)).locale(burnLocale)))% restants"
            )
          }.font(.system(size: 12))
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Text(store.isLoading ? "Lecture de ton utilisation…" : "Quota indisponible")
            .font(.system(size: 24, weight: .semibold))
          Text(
            store.isLoading
              ? "Chargement des logs locaux et des limites d'abonnement. Cela peut prendre un moment."
              : "Connecte-toi à ce harness et lance une session pour enregistrer les limites. Tes données de dépense disponibles s'affichent ci-dessous."
          )
          .font(.system(size: 13)).foregroundStyle(BurnTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
      }
      if let report = store.reports[agent], !report.topModels.isEmpty {
        Rectangle().fill(BurnTheme.line).frame(height: 1)
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Utilisation par modèle", detail: "Équivalent API · 30 derniers jours")
          ForEach(Array(report.topModels.prefix(compact ? 2 : 6))) { model in
            HStack {
              Text(model.model).lineLimit(1).help(model.model)
              Spacer()
              Text(tokens(model.tokens)).foregroundStyle(BurnTheme.muted)
              Text(currency(model.cost)).frame(width: 80, alignment: .trailing)
            }.font(.system(size: 12)).monospacedDigit()
          }
        }
      }
      if !compact, let report = store.reports[agent] { HarnessSpendDetails(report: report) }
      if let error = store.errors["history"] { ReportNotice(message: error) }
    }
  }

  private func quotaHeader(_ forecast: Forecast) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(forecast.remaining.formatted(.number.precision(.fractionLength(0))))
          .font(.system(size: compact ? 52 : 64, weight: .medium, design: .rounded))
          .monospacedDigit()
        Text("% restants").font(.system(size: 16)).foregroundStyle(BurnTheme.muted)
        Spacer()
        if compact {
          Text("Limite hebdomadaire").font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        }
      }
      VStack(alignment: .leading, spacing: 5) {
        Label(
          forecast.remaining == 0
            ? "Limite atteinte"
            : forecast.daysEarly > 0.1 ? "Un peu au-dessus du rythme" : "De la marge pour continuer",
          systemImage: forecast.daysEarly > 0.1
            ? "gauge.with.dots.needle.67percent" : "checkmark.circle"
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(forecast.daysEarly > 0.1 ? BurnTheme.accent : BurnTheme.green)
        Text(
          forecast.projectedUse == nil
            ? "Une prévision apparaîtra dès que ce cycle aura enregistré de l'utilisation."
            : forecast.daysEarly > 0.1
              ? "À ce rythme, ton quota pourrait s'épuiser \(forecast.daysEarly.formatted(.number.precision(.fractionLength(1)).locale(burnLocale))) jours trop tôt."
              : "Ton rythme actuel devrait te mener jusqu'à la réinitialisation."
        )
        .font(.system(size: 12)).foregroundStyle(BurnTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func resetDetails(_ forecast: Forecast) -> some View {
    VStack(spacing: 12) {
      HStack {
        Label("Réinitialisation vers", systemImage: "clock").foregroundStyle(BurnTheme.muted)
        Spacer()
        Text(forecast.reset.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
      }
      HStack {
        Label("Réinitialisations enregistrées", systemImage: "arrow.counterclockwise").foregroundStyle(
          BurnTheme.muted)
        Spacer()
        Text(resetSummary(store.resets(for: agent)))
      }
      .help(
        "Les réinitialisations planifiées ont lieu en fin de cycle. Une réinitialisation possible est un saut du restant en milieu de cycle : réinitialisation manuelle ou correction du fournisseur."
      )
      HStack {
        Label("Rythme conseillé", systemImage: "speedometer").foregroundStyle(BurnTheme.muted)
        Spacer()
        Text(
          "\(forecast.dailyAllowance.formatted(.number.precision(.fractionLength(1)).locale(burnLocale)))% / jour"
        )
          .foregroundStyle(color)
      }
    }
    .font(.system(size: 12)).monospacedDigit()
    .padding(14).background(BurnTheme.surface, in: RoundedRectangle(cornerRadius: 10))
  }
}
