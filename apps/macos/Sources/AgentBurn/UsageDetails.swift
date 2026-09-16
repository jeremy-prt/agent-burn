import Charts
import SwiftUI

struct SpendMetric: View {
  let title: String
  let value: String
  var detail = ""
  /// Phrase expliquant ce que le chiffre veut dire, affichée au survol.
  var explanation = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 4) {
        Text(title).font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        if !explanation.isEmpty { InfoButton(text: explanation) }
      }
      Text(value).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
      if !detail.isEmpty { Text(detail).font(.system(size: 10)).foregroundStyle(BurnTheme.muted) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Pastille « ? » : un clic ouvre l'explication, une infobulle ne suffisait pas.
struct InfoButton: View {
  let text: String
  @State private var shows = false
  var body: some View {
    Button { shows = true } label: {
      Image(systemName: "questionmark.circle")
        .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
    }
    .buttonStyle(.plain)
    .help(text)
    .accessibilityLabel("Explication")
    .popover(isPresented: $shows, arrowEdge: .bottom) {
      Text(text)
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 260, alignment: .leading)
        .padding(14)
    }
  }
}

struct QuotaSummary: View {
  let forecast: Forecast
  let samples: [QuotaSample]
  let now: Date
  var stale = false
  var staleHelp: String?
  var compact = false
  var availableResets: Int? = nil
  var rates: QuotaBlendRates? = nil
  var style = QuotaMeterStyle.weekly
  private var muted: Color { compact ? BurnTheme.quotaMuted : BurnTheme.muted }
  private var reading: QuotaChartReading {
    quotaChartReading(at: forecast.observedAt, samples: samples, forecast: forecast, range: .rte)
  }
  private var paceText: String? { quotaChartDeltaText(reading.paceDelta) }
  private var paceColor: Color {
    reading.paceDelta.map { $0 < -0.05 ? BurnTheme.behind : BurnTheme.ahead } ?? muted
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 14 : 20) {
      if !compact { title }
      if compact { compactHero } else { hero }
      if !compact { facts }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var title: some View {
    HStack(spacing: 6) {
      Text(style.title).font(.headline).lineLimit(1)
      if stale { staleMark }
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 10) {
      remainingLabel
      if let paceText {
        StatusBadge(text: paceText, color: paceColor)
          .help("Écart entre ta consommation réelle et le rythme idéal, à la dernière mesure.")
      }
    }
  }

  private var compactHero: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        remainingLabel
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 6) {
          if let paceText {
            StatusBadge(text: paceText, color: paceColor)
              .help("Écart entre ta consommation réelle et le rythme idéal, à la dernière mesure.")
          }
          Text("\(style.resetTitle) \(quotaTimeLeft(forecast, now: now))")
            .font(.system(size: 12))
            .foregroundStyle(muted)
            .lineLimit(1)
          Text(quotaDateCompact(forecast.reset))
            .font(.system(size: 12))
            .foregroundStyle(muted)
            .monospacedDigit()
            .lineLimit(1)
            .help(style.resetHelp)
          if let availableResets {
            Text(
              availableResets == 1 ? "1 réinitialisation" : "\(availableResets) réinitialisations")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(BurnTheme.ink)
              .lineLimit(1)
              .help("Réinitialisations de limite Codex que tu peux utiliser maintenant.")
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(style.resetTitle)
        .accessibilityValue(
          "\(quotaTimeLeft(forecast, now: now)). \(quotaDateCompact(forecast.reset))")
      }
    }
  }

  private var remainingLabel: some View {
    VStack(alignment: .leading, spacing: 2) {
      if compact {
        HStack(spacing: 6) {
          Text(style.remainingCaption).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
          if stale { staleMark }
        }
      }
      Text(quotaChartPercentLabel(quotaUsedPercent(forecast)))
        .font(.system(size: compact ? 44 : 42, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(BurnTheme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      if !compact {
        Text("utilisés").font(.system(size: 13)).foregroundStyle(muted)
      }
    }
    .help(
      "Mis à jour le \(forecast.observedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second().locale(burnLocale)))"
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Quota restant")
    .accessibilityValue(quotaChartPercentLabel(quotaUsedPercent(forecast)) + " utilisés")
  }

  @ViewBuilder private var staleMark: some View {
    Image(systemName: "clock.badge.exclamationmark")
      .foregroundStyle(.orange)
      .help(staleHelp ?? "Dernière mesure connue affichée. Mise à jour en attente.")
      .accessibilityLabel("Dernier quota connu ; mise à jour en attente")
  }

  private var facts: some View {
    VStack(spacing: 11) {
      row(style.resetTitle, quotaTimeLeft(forecast, now: now), help: style.resetHelp)
      row(
        "Par jour",
        "\(forecast.dailyAllowance.formatted(.number.precision(.fractionLength(1)).locale(burnLocale)))%\u{00A0}/ jour",
        help: "Ce que tu peux consommer chaque jour pour tenir jusqu'à la réinitialisation.")
      if let available = availableResets {
        row(
          "Réinitialisations", "\(available)",
          help: "Réinitialisations de limite Codex que tu peux utiliser maintenant.")
      }
    }
  }

  private func row(_ title: String, _ value: String, detail: String? = nil, help: String)
    -> some View
  {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title).foregroundStyle(muted).lineLimit(1)
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 1) {
        Text(value)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
        if let detail {
          Text(detail)
            .foregroundStyle(muted)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
        }
      }
      .multilineTextAlignment(.trailing)
      .layoutPriority(1)
    }
    .font(.system(size: 12))
    .help(help)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(detail.map { "\(value). \($0)" } ?? value)
  }
}

struct DailySpendChart: View {
  let title: String
  let days: [DailyUsage]
  var color = BurnTheme.accent
  var scope: Binding<CursorModelScope>? = nil
  var domain: ClosedRange<Date>? = nil
  var showsGranularity = true
  @State private var selected: Date?
  @State private var granularityOverride: SpendGranularity?
  private var points: [(date: Date, usage: DailyUsage)] {
    days.compactMap { usage in
      guard let date = usageDayDate(usage.date) else { return nil }
      return (date, usage)
    }
  }
  private var scale: ClosedRange<Date> {
    if let domain { return domain }
    if let first = points.first?.date, let last = points.last?.date, first <= last {
      return first...last
    }
    let today = Calendar(identifier: .gregorian).startOfDay(for: .now)
    return today...today
  }
  private var spanDays: Int { spendSpanDays(lower: scale.lowerBound, upper: scale.upperBound) }
  private var effective: SpendGranularity {
    guard showsGranularity else { return .daily }
    return granularityOverride ?? spendGranularityAuto(spanDays: spanDays)
  }
  private var granularityBinding: Binding<SpendGranularity> {
    Binding(get: { effective }, set: { granularityOverride = $0 })
  }
  private var buckets: [(date: Date, end: Date, usage: DailyUsage)] {
    let calendar = spendCalendar()
    return bucketDailyUsage(days, granularity: effective, calendar: calendar).compactMap { usage in
      guard let start = usageDayDate(usage.date) else { return nil }
      return (
        start, spendBucketEnd(start: start, granularity: effective, calendar: calendar), usage
      )
    }
  }
  private var headerTitle: String { showsGranularity ? effective.spendTitle : title }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        SectionLabel(title: headerTitle, detail: "Équivalent API en \(currencySymbol)")
        Spacer()
        if showsGranularity {
          Picker("Granularité", selection: granularityBinding) {
            ForEach(SpendGranularity.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 220)
          .labelsHidden()
          .accessibilityLabel("Granularité de la dépense")
        }
        if let scope {
          Picker("Modèles", selection: scope) {
            ForEach(CursorModelScope.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 240)
          .labelsHidden()
          .accessibilityLabel("Modèles de la dépense quotidienne")
        }
      }
      Chart {
        ForEach(buckets, id: \.usage.id) { bucket in
          BarMark(
            x: .value("Jour", bucket.date, unit: effective.unit),
            y: .value("Utilisation", bucket.usage.cost * CurrentRate.shared.rate)
          )
          .foregroundStyle(color).cornerRadius(3)
          .accessibilityLabel(bucket.usage.date).accessibilityValue(currency(bucket.usage.cost))
        }
        if let selected {
          RuleMark(x: .value("Jour", selected)).foregroundStyle(.secondary.opacity(0.4))
        }
      }
      .chartXSelection(value: $selected)
      .chartXScale(domain: scale)
      .chartYAxis {
        AxisMarks(position: .leading) { _ in
          AxisGridLine().foregroundStyle(BurnTheme.line)
          AxisValueLabel().foregroundStyle(BurnTheme.muted)
        }
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
          if effective == .monthly {
            AxisValueLabel(format: .dateTime.month(.abbreviated).year()).foregroundStyle(
              BurnTheme.muted)
          } else {
            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(
              BurnTheme.muted)
          }
        }
      }
      .frame(height: 150)
      .id(
        "\(showsGranularity)-\(effective.rawValue)-\(scale.lowerBound.formatted())-\(scale.upperBound.formatted())"
      )
    }
  }
}

struct HarnessSpendDetails: View {
  let report: HarnessReport
  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      if !report.daily.isEmpty {
        DailySpendChart(
          title: "Utilisation par jour · cycle en cours", days: report.daily,
          color: BurnTheme.color(for: report.agent))
      }
      if let mix = report.spendMix, !mix.isEmpty {
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Dépense par type de token", detail: "30 derniers jours")
          ForEach(mix) { category in
            HStack {
              Text(category.label.capitalized).frame(maxWidth: .infinity, alignment: .leading)
              Text(tokens(category.tokens)).foregroundStyle(BurnTheme.muted).frame(
                width: 85, alignment: .trailing)
              Text(
                "\(category.costPercent.formatted(.number.precision(.fractionLength(1)).locale(burnLocale)))%"
              )
                .foregroundStyle(BurnTheme.muted).frame(width: 60, alignment: .trailing)
              Text(currency(category.costUSD)).frame(width: 90, alignment: .trailing)
            }.font(.system(size: 12)).monospacedDigit()
          }
        }
      }
      if let trend = report.weeklyTrend, !trend.isEmpty {
        DailySpendChart(
          title: "Tendance hebdomadaire", days: trend.map { DailyUsage(date: $0.weekStart, cost: $0.cost) },
          color: BurnTheme.color(for: report.agent), showsGranularity: false)
      }
      if let estimate = report.estimate {
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Valeur estimée du quota", detail: "D'après le cycle en cours")
          detail("Valeur du quota complet", currency(estimate.fullQuotaValue))
          if let dollars = quotaDollarsPerPercentLabel(estimate.fullQuotaValue / 100) {
            detail("Moyenne \(currencySymbol) / %", dollars)
          }
          detail("Valeur mensuelle du quota", currency(estimate.monthlyValue))
          detail(
            "Consommation de quota projetée",
            "\(estimate.projectedUsePercent.formatted(.number.precision(.fractionLength(0)).locale(burnLocale)))%")
          if let multiple = estimate.valueMultiple {
            detail(
              "Valeur du quota / prix de l'offre",
              "\(multiple.formatted(.number.precision(.fractionLength(1)).locale(burnLocale))) ×")
          }
        }
      }
      if let images = report.imageGenerations, report.agent == "codex" {
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Générations d'images", detail: "30 derniers jours")
          detail("Images générées", images.count.formatted(.number.locale(burnLocale)))
          detail("Coût estimé des images", currency(images.estimatedCost))
          Text(
            "Estimation de \(currency(images.pricePerImageEstimate)) par image. Compté à part de l'utilisation de tokens."
          )
          .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        }
      }
    }
  }

  private func detail(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(BurnTheme.muted)
      Spacer()
      Text(value)
    }
    .font(.system(size: 12)).monospacedDigit()
  }
}

struct SourceUsageView: View {
  @Environment(UsageStore.self) private var store
  let agent: String
  var compact = false
  @State private var cursorScope = CursorModelScope.allModels
  private var usage: AgentUsage? { store.summary?.agents.first { $0.agent == agent } }
  private var subscription: SubscriptionAgent? {
    store.summary?.subscription?.agents.first { $0.agent == agent }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      HStack(spacing: 10) {
        HarnessIcon(agent: agent)
        VStack(alignment: .leading, spacing: 4) {
          Text(harnessName(agent)).font(.system(size: 23, weight: .semibold))
          Text(subscription?.plan ?? "Utilisation du harness").font(.system(size: 12)).foregroundStyle(
            BurnTheme.muted)
        }
        Spacer()
        PeriodPicker()
      }
      if let error = store.errors["summary"] { ReportNotice(message: error) }
      if let usage {
        if agent == "cursor", cursorHasPromotionalCredits(store.summary?.cursorAccount),
          let forecast = store.forecast(for: "cursor")
        {
          QuotaSummary(
            forecast: forecast,
            samples: store.samples(
              for: "cursor", range: store.cursorQuotaChartRange, now: store.quotaCheckDate),
            now: store.quotaCheckDate,
            stale: !forecast.isFresh(at: store.quotaCheckDate)
              || store.quotaError(for: "cursor") != nil,
            staleHelp: store.quotaError(for: "cursor")
              ?? "Dernière mesure connue affichée. Mise à jour en attente.",
            compact: compact,
            rates: store.blendRates(for: "cursor"),
            style: .promotionalCredits)
          QuotaChart(
            forecast: forecast,
            samples: store.samples(
              for: "cursor", range: store.cursorQuotaChartRange, now: store.quotaCheckDate),
            color: compact
              ? BurnTheme.quotaColor(for: "cursor") : BurnTheme.color(for: "cursor"),
            compact: compact, range: store.cursorQuotaChartRange, now: store.quotaCheckDate,
            resetLabel: QuotaMeterStyle.promotionalCredits.chartResetLabel)
        } else if agent == "cursor" {
          CursorAccountView(account: store.summary?.cursorAccount, plan: subscription)
        } else if agent == "claude" {
          ClaudeAccountView(account: store.summary?.claudeAccount, plan: subscription)
        }
        HStack {
          SpendMetric(
            title: "Dépense totale", value: currency(usage.totalCost),
            detail: store.period.label + " · équivalent API",
            explanation:
              "Ce que ces tokens auraient coûté au tarif API public, hors taxes. Ce n'est pas ce que tu paies : ton abonnement est facturé à part."
          )
          SpendMetric(
            title: "Total de tokens", value: tokens(usage.totalTokens),
            explanation:
              "Tokens envoyés et reçus sur la période, cache compris. Md = milliard, M = million, k = millier."
          )
          if !compact, let price = subscription?.pricePerMonth {
            SpendMetric(
              title: "Offre mensuelle", value: planPrice(price),
              detail: [subscription?.plan, planPriceTaxNote].compactMap { $0 }.joined(
                separator: " · "),
              explanation: planPriceExplanation)
          }
        }
        if let daily = usage.daily, !daily.isEmpty,
          !(compact && cursorHasPromotionalCredits(store.summary?.cursorAccount))
        {
          DailySpendChart(
            title: "Utilisation par jour",
            days: agent == "cursor" && !cursorHasPromotionalCredits(store.summary?.cursorAccount)
              ? dailyUsage(daily, scope: cursorScope) : daily,
            color: BurnTheme.color(for: agent),
            scope: agent == "cursor" && !cursorHasPromotionalCredits(store.summary?.cursorAccount)
              ? $cursorScope : nil,
            domain: store.chartDomain)
        }
        if let models = usage.models, !models.isEmpty {
          let shown =
            agent == "cursor" && !cursorHasPromotionalCredits(store.summary?.cursorAccount)
            ? modelUsage(models, scope: cursorScope) : models
          VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Détail par modèle", detail: store.period.label)
            ForEach(Array(shown.prefix(compact ? 3 : shown.count))) { model in
              HStack {
                Text(model.model).lineLimit(1).help(model.model)
                Spacer()
                Text(tokens(model.totalTokens)).foregroundStyle(BurnTheme.muted)
                Text(currency(model.totalCost)).frame(width: 90, alignment: .trailing)
              }.font(.system(size: 12)).monospacedDigit()
            }
          }
        }
        if !compact, let breakdown = usage.tokenBreakdown {
          VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Détail des tokens", detail: store.period.label)
            ForEach(
              [
                ("input", "Entrée"), ("output", "Sortie"), ("cacheWrite", "Écriture cache"),
                ("cacheRead", "Lecture cache"),
              ], id: \.0
            ) { key, label in
              HStack {
                Text(label).foregroundStyle(BurnTheme.muted)
                Spacer()
                Text(tokens(breakdown[key] ?? 0))
              }
              .font(.system(size: 12)).monospacedDigit()
            }
          }
        }
      } else {
        ReportNotice(
          message: store.isLoading
            ? "Lecture de l'utilisation du harness…"
            : agent == "cursor" && store.offline
              ? "L'utilisation Cursor nécessite la connexion à son tableau de bord. Désactive le mode cache dans les Réglages pour la charger."
              : "Aucune utilisation trouvée sur cette période. Choisis une plage plus large et vérifie que le harness est connecté."
        )
      }
    }
  }
}

struct PeriodPicker: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    Picker("Période", selection: $store.period) {
      ForEach(UsagePeriod.allCases) { period in Text(period.label).tag(period) }
    }.labelsHidden().frame(width: 160)
  }
}

struct QuotaChartRangePicker: View {
  @Binding var range: QuotaChartRange
  var body: some View {
    Picker("Plage du graphique de quota", selection: $range) {
      ForEach(QuotaChartRange.allCases) { range in Text(range.label).tag(range) }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .frame(width: 160)
    .help("Ne change que le graphique de quota hebdomadaire. La période de dépense reste indépendante.")
    .accessibilityLabel("Plage du graphique de quota")
  }
}
