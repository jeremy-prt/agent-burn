import Charts
import SwiftUI

struct NativeUsageView: View {
  @Environment(UsageStore.self) private var store
  let agent: String?
  @State private var modelSearch = ""
  @State private var showsEconomics = false
  @State private var cursorScope = CursorModelScope.allModels
  private var own: AgentUsage? { store.summary?.agents.first { $0.agent == agent } }
  private var hasCursorCredits: Bool { cursorHasPromotionalCredits(store.summary?.cursorAccount) }
  private var models: [ModelUsage] {
    let all = agent == nil ? store.summary?.models ?? [] : own?.models ?? []
    return agent == "cursor" && !hasCursorCredits ? modelUsage(all, scope: cursorScope) : all
  }
  private var days: [DailyUsage] {
    let all = agent == nil ? store.summary?.daily ?? [] : own?.daily ?? []
    return agent == "cursor" && !hasCursorCredits ? dailyUsage(all, scope: cursorScope) : all
  }
  private var cost: Double {
    agent == nil ? store.summary?.totals.totalCost ?? 0 : own?.totalCost ?? 0
  }
  private var tokenCount: UInt64 {
    agent == nil ? store.summary?.totals.totalTokens ?? 0 : own?.totalTokens ?? 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .center, spacing: 12) {
        if let agent {
          HarnessIcon(agent: agent, size: 40)
        } else {
          Image(systemName: "chart.bar.xaxis").font(.system(size: 26)).foregroundStyle(.tint)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(agent.map(harnessName) ?? "Tous les harnesses").font(.title2.weight(.semibold))
          Text("\(store.period.label) · utilisation issue de tes logs et des fournisseurs connectés")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
        PeriodPicker()
      }
      if store.summary == nil, let error = store.errors["summary"] {
        ReportNotice(message: error)
      }
      if store.summary != nil {
        meters

        GroupBox {
          HStack(spacing: 24) {
            SpendMetric(
              title: "Dépense totale", value: currency(cost), detail: "Valeur équivalente API",
              explanation:
                "Ce que ces tokens auraient coûté au tarif API public, hors taxes. Ce n'est pas ce que tu paies : ton abonnement est facturé à part."
            )
            Divider()
            SpendMetric(
              title: "Tokens", value: tokens(tokenCount), detail: "Entrée, sortie et cache",
              explanation:
                "Tokens envoyés et reçus sur la période, cache compris. Md = milliard, M = million, k = millier."
            )
            Divider()
            SpendMetric(
              title: "Tokens par \(currencySymbol)",
              value: quotaTokensPerCurrencyLabel(
                quotaTokensPerDollar(tokens: tokenCount, cost: cost)) ?? "—",
              detail: store.period.label,
              explanation:
                "Combien de tokens tu obtiens pour 1 \(currencySymbol) de valeur équivalente API. Plus le chiffre est haut, plus tes tokens sont bon marché : tu utilises surtout du cache ou des modèles économiques."
            )
            Divider()
            SpendMetric(
              title: "Modèles", value: store.hasPeriodDetails ? models.count.formatted() : "—",
              detail: agent.map(harnessName) ?? "Tous harnesses confondus",
              explanation: "Nombre de modèles distincts que tu as utilisés sur la période."
            )
          }.padding(12).frame(height: 85)
        }
        HStack(alignment: .top, spacing: 18) {
          GroupBox {
            ActivityChart(
              days: days, color: agent.map(BurnTheme.color) ?? .accentColor,
              domain: store.chartDomain,
              scope: agent == "cursor" && !hasCursorCredits ? $cursorScope : nil
            )
            .padding(12)
          }.frame(maxWidth: .infinity)
          if agent == nil {
            GroupBox {
              VStack(alignment: .leading, spacing: 16) {
                Text("Par harness").font(.headline)
                ScrollView {
                  VStack(spacing: 16) {
                    ForEach(store.summary?.agents ?? []) { usage in
                      Button {
                        store.selection = usage.agent
                      } label: {
                        HStack(spacing: 10) {
                          HarnessIcon(agent: usage.agent, size: 26)
                          VStack(alignment: .leading, spacing: 3) {
                            Text(harnessName(usage.agent)).font(.subheadline.weight(.medium))
                            Text(tokens(usage.totalTokens) + " tokens").font(.caption)
                              .foregroundStyle(
                                .secondary)
                          }
                          Spacer()
                          Text(currency(usage.totalCost)).font(.subheadline).monospacedDigit()
                        }.contentShape(Rectangle())
                      }.buttonStyle(.plain)
                    }
                  }
                }.frame(height: 185)
                Spacer(minLength: 0)
              }.padding(12).frame(height: 218, alignment: .top)
            }.frame(width: 285)
          }
        }
        if store.hasPeriodDetails { modelSection }
        if agent == "cursor", store.period == .all, let recovered = store.recoveredCursor,
          let models = recovered.models
        {
          GroupBox {
            DisclosureGroup(
              "Historique de modèles récupéré · \(models.count) modèle\(models.count > 1 ? "s" : "")") {
              VStack(alignment: .leading, spacing: 10) {
                Text(
                  "Instantané : \(recovered.daily?.first?.date ?? "") – \(recovered.daily?.last?.date ?? ""). Les modèles du cycle en cours sont affichés au-dessus."
                )
                .font(.caption).foregroundStyle(.secondary)
                ModelUsageTable(models: models, total: recovered.totalCost).frame(height: 280)
              }.padding(.top, 12)
            }.padding(10)
          }
        }
        if let agent, let report = store.reports[agent] {
          GroupBox {
            DisclosureGroup(
              "Économie de l'abonnement, coût des tokens et tendances hebdomadaires",
              isExpanded: $showsEconomics
            ) {
              VStack(alignment: .leading, spacing: 20) {
                HStack {
                  SpendMetric(
                    title: "30 derniers jours", value: currency(report.apiEquivalentPerMonth),
                    explanation:
                      "Valeur équivalente API de ton utilisation sur 30 jours, hors taxes."
                  )
                  SpendMetric(
                    title: "Offre mensuelle",
                    value: report.pricePerMonth.map(planPrice) ?? "Indisponible",
                    detail: report.pricePerMonth == nil ? "" : planPriceTaxNote,
                    explanation: planPriceExplanation)
                  SpendMetric(
                    title: "Valeur de l'abonnement",
                    value: report.economics.map {
                      $0.valueMultiple.formatted(
                        .number.precision(.fractionLength(2)).locale(burnLocale)) + " ×"
                    } ?? "Indisponible",
                    explanation:
                      "Valeur équivalente API divisée par le prix hors taxes de ton offre. À 9 ×, ton utilisation vaut neuf fois ce que tu paies."
                  )
                }
                HarnessSpendDetails(report: report)
              }.padding(.top, 18)
            }.font(.headline).padding(10)
          }
        }
      } else {
        if let agent, ["codex", "claude"].contains(agent) { quotaSection(agent) }
        ContentUnavailableView {
          Label(
            store.isLoading ? "Chargement de l'historique" : "Aucun rapport disponible",
            systemImage: "chart.bar.xaxis")
        } description: {
          Text(
            "Ton utilisation apparaîtra ici dès qu'elle sera prête."
          )
        }
        .frame(maxWidth: .infinity, minHeight: 380)
      }
    }
  }

  @ViewBuilder private var meters: some View {
    if agent == "cursor" {
      CursorAccountView(
        account: store.summary?.cursorAccount,
        plan: store.summary?.subscription?.agents.first { $0.agent == "cursor" })
    } else if agent == "claude" {
      ClaudeAccountView(
        account: store.summary?.claudeAccount,
        plan: store.summary?.subscription?.agents.first { $0.agent == "claude" },
        unavailableReason: store.summary?.claudeAccountUnavailable)
      // La courbe de rythme n'était branchée que sur Codex : Claude en a autant besoin.
      quotaSection("claude")
    } else if agent == "codex" {
      quotaSection("codex")
    }
  }

  private var modelSection: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Modèles · données disponibles").font(.headline)
          Text("\(models.count)").font(.caption).foregroundStyle(.secondary)
          Spacer()
          TextField("Filtrer les modèles", text: $modelSearch).textFieldStyle(.roundedBorder).frame(
            width: 220)
        }.padding(.horizontal, 6)
        ModelUsageTable(
          models: models.filter {
            modelSearch.isEmpty || $0.model.localizedCaseInsensitiveContains(modelSearch)
          },
          total: agent == "cursor" && !hasCursorCredits && cursorScope == .cursorModels
            ? models.reduce(0) { $0 + $1.totalCost } : cost
        )
        .frame(height: CGFloat(min(9, max(3, models.count))) * 27 + 28)
      }.padding(8)
    }
  }

  @ViewBuilder private func quotaSection(
    _ agent: String, style: QuotaMeterStyle = .weekly
  ) -> some View {
    @Bindable var store = store
    let range = store.chartRange(for: agent)
    if let error = store.errors[agent] { ReportNotice(message: error) }
    if let error = store.errors["quotaService"] { ReportNotice(message: error) }
    if let forecast = store.forecast(for: agent) {
      GroupBox {
        HStack(alignment: .top, spacing: 28) {
          QuotaSummary(
            forecast: forecast,
            samples: store.samples(
              for: agent, range: range, now: store.quotaCheckDate),
            now: store.quotaCheckDate,
            stale: !forecast.isFresh(at: store.quotaCheckDate)
              || store.quotaError(for: agent) != nil,
            staleHelp: store.quotaError(for: agent)
              ?? "Dernière mesure connue affichée. Mise à jour en attente.",
            availableResets: style == .weekly
              ? store.reports[agent]?.resetCreditsAvailable : nil,
            rates: store.blendRates(for: agent),
            style: style
          )
          .frame(width: 236, alignment: .leading)
          VStack(alignment: .trailing, spacing: 8) {
            QuotaChartRangePicker(
              range: agent == "cursor"
                ? $store.cursorQuotaChartRange : $store.quotaChartRange)
            QuotaChart(
              forecast: forecast,
              samples: store.samples(
                for: agent, range: range, now: store.quotaCheckDate),
              color: BurnTheme.color(for: agent),
              range: range, now: store.quotaCheckDate,
              resetLabel: style.chartResetLabel
            )
            .id(range)
          }
        }.padding(12)
      }
      if style == .promotionalCredits,
        (store.summary?.cursorAccount?.includedPercentUsed ?? 0) == 0
      {
        Text("L'enveloppe incluse n'est pas entamée tant qu'il reste des crédits promotionnels.")
          .font(.caption).foregroundStyle(.secondary)
      }
    } else {
      Label(
        "Quota indisponible. L'historique de dépense et de tokens reste affiché au-dessus.",
        systemImage: "info.circle"
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}

private struct ModelUsageTable: View {
  let models: [ModelUsage]
  let total: Double
  @State private var order = [KeyPathComparator(\ModelUsage.totalCost, order: .reverse)]
  var body: some View {
    Table(models.sorted(using: order), sortOrder: $order) {
      TableColumn("Modèle", value: \.model) { model in Text(model.model).help(model.model) }
      TableColumn("Tokens", value: \.totalTokens) { model in
        Text(tokens(model.totalTokens)).monospacedDigit().foregroundStyle(.secondary)
      }.width(100)
      TableColumn("Dépense", value: \.totalCost) { model in
        Text(currency(model.totalCost)).monospacedDigit()
      }.width(100)
      TableColumn("Part") { model in
        Text(
          total > 0
            ? (model.totalCost / total).formatted(
              .percent.precision(.fractionLength(1)).locale(burnLocale)) : "—"
        )
        .monospacedDigit().foregroundStyle(.secondary)
      }.width(75)
    }.tableStyle(.inset(alternatesRowBackgrounds: true))
  }
}

private struct ActivityChart: View {
  let days: [DailyUsage]
  let color: Color
  var domain: ClosedRange<Date>? = nil
  var scope: Binding<CursorModelScope>? = nil
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
    granularityOverride ?? spendGranularityAuto(spanDays: spanDays)
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
  private var selectedBucket: (date: Date, end: Date, usage: DailyUsage)? {
    guard let selected else { return nil }
    return buckets.first { selected >= $0.date && selected <= $0.end }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(effective.spendTitle).font(.headline)
Picker("Granularité", selection: granularityBinding) {
          ForEach(SpendGranularity.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .labelsHidden()
        .accessibilityLabel("Granularité de la dépense")
        if let scope {
          Picker("Modèles", selection: scope) {
            ForEach(CursorModelScope.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 260)
          .labelsHidden()
          .accessibilityLabel("Modèles de la dépense quotidienne")
        }
        Spacer()
        if let bucket = selectedBucket {
          Text(
            spendBucketTooltip(start: bucket.date, granularity: effective, cost: bucket.usage.cost)
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else {
          Text(currencySymbol).font(.caption).foregroundStyle(.secondary)
        }
      }
      Chart {
        ForEach(buckets, id: \.usage.id) { bucket in
          BarMark(
            x: .value("Jour", bucket.date, unit: effective.unit),
            y: .value("Dépense", bucket.usage.cost * CurrentRate.shared.rate)
          )
          .foregroundStyle(color.gradient).cornerRadius(2)
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
          AxisGridLine()
          AxisValueLabel()
        }
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
          if effective == .monthly {
            AxisValueLabel(format: .dateTime.month(.abbreviated).year())
          } else {
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
          }
        }
      }
      .frame(height: 182)
      .id(effective.rawValue + scale.lowerBound.formatted() + scale.upperBound.formatted())
    }
  }
}
