import SwiftUI

struct OverviewView: View {
  @Environment(UsageStore.self) private var store
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 20 : 28) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 6) {
          Text(compact ? "Tous tes harnesses" : "Utilisation en un coup d'œil")
            .font(.system(size: compact ? 21 : 28, weight: .semibold))
          Text("Un seul endroit pour tous tes agents.").font(.system(size: 13)).foregroundStyle(
            BurnTheme.muted)
        }
        Spacer()
        PeriodPicker()
      }
      if let error = store.errors["summary"] { ReportNotice(message: error) }
      if let report = store.summary {
        HStack(spacing: 0) {
          metric("Valeur équivalente API", value: currency(report.totals.totalCost))
          if !compact {
            Rectangle().fill(BurnTheme.line).frame(width: 1, height: 44).padding(.horizontal, 28)
          } else {
            Spacer()
          }
          metric("Tokens traités", value: tokens(report.totals.totalTokens))
          if !compact {
            Rectangle().fill(BurnTheme.line).frame(width: 1, height: 44).padding(.horizontal, 28)
            metric("Harnesses actifs", value: String(report.agents.count))
          }
        }
        .padding(.vertical, compact ? 8 : 18)
        if !compact, let daily = report.daily, !daily.isEmpty {
          DailySpendChart(title: "Utilisation par jour", days: daily, domain: store.chartDomain)
        }
        VStack(alignment: .leading, spacing: 18) {
          SectionLabel(title: "Utilisation par harness", detail: store.period.label)
          if report.agents.isEmpty {
            ReportNotice(
              message:
                "Aucune utilisation locale sur cette période. Lance une session d'agent ou choisis une plage plus large."
            )
          }
          ForEach(report.agents) { agent in
            agentRow(agent, totals: report.totals)
          }
        }
        if !report.models.isEmpty {
          Rectangle().fill(BurnTheme.line).frame(height: 1)
          VStack(alignment: .leading, spacing: 0) {
            SectionLabel(
              title: "Détail par modèle",
              detail: "\(report.models.count) modèle\(report.models.count > 1 ? "s" : "")")
              .padding(.bottom, 18)
            ForEach(Array(report.models.prefix(compact ? 3 : report.models.count))) { model in
              HStack(spacing: 14) {
                Text(model.model).lineLimit(1).help(model.model).frame(
                  maxWidth: .infinity, alignment: .leading)
                Text(tokens(model.totalTokens)).foregroundStyle(BurnTheme.muted).frame(
                  width: 68, alignment: .trailing)
                Text(currency(model.totalCost)).frame(width: 90, alignment: .trailing)
              }
              .font(.system(size: 12)).monospacedDigit().padding(.vertical, 12)
              Rectangle().fill(BurnTheme.line).frame(height: 1)
            }
          }
        }
        if !compact, let subscription = report.subscription, !subscription.agents.isEmpty {
          VStack(alignment: .leading, spacing: 14) {
            SectionLabel(
              title: "Abonnements", detail: "Prix mensuels \(planPriceTaxNote)")
            ForEach(subscription.agents) { agent in
              HStack {
                Text(harnessName(agent.agent))
                Text(agent.plan ?? "Offre inconnue").foregroundStyle(BurnTheme.muted)
                Spacer()
                Text(agent.pricePerMonth.map(planPrice) ?? "Prix indisponible")
                  .help(planPriceExplanation)
              }.font(.system(size: 12))
            }
          }
        }
        Label(
          "La valeur équivalente API estime le coût des tokens, pas le montant de ton abonnement.",
          systemImage: "info.circle"
        )
        .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          Text(store.isLoading ? "Collecte de ton utilisation locale…" : "Connecte ton utilisation")
            .font(.system(size: 20, weight: .medium))
          Text(
            "Agent Burn lit les mêmes logs locaux que le CLI. Choisis l'exécutable dans les Réglages s'il n'est pas détecté automatiquement."
          )
          .font(.system(size: 13)).foregroundStyle(BurnTheme.muted)
        }.frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
      }
    }
  }

  private func metric(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(label).font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
      Text(value).font(.system(size: compact ? 25 : 32, weight: .medium, design: .rounded))
        .monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func agentRow(_ agent: AgentUsage, totals: Totals) -> some View {
    let share =
      totals.totalCost > 0
      ? agent.totalCost / totals.totalCost
      : totals.totalTokens > 0 ? Double(agent.totalTokens) / Double(totals.totalTokens) : 0
    return HStack(spacing: 12) {
      HarnessIcon(agent: agent.agent, size: compact ? 30 : 38)
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(harnessName(agent.agent)).font(.system(size: 13, weight: .medium))
          Spacer()
          Text(tokens(agent.totalTokens)).font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
          Text(currency(agent.totalCost)).font(.system(size: 13, weight: .medium)).frame(
            width: 85, alignment: .trailing)
        }
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(BurnTheme.elevated)
            Capsule().fill(BurnTheme.color(for: agent.agent)).frame(
              width: geometry.size.width * max(0, min(1, share)))
          }
        }.frame(height: 4).accessibilityLabel(
          "\(Int(share * 100)) pour cent de \(totals.totalCost > 0 ? "la valeur d'utilisation" : "des tokens")")
      }
    }.monospacedDigit().padding(.vertical, 5)
  }
}
