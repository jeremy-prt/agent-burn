import SwiftUI

/// Un compteur de la rangée d'en-tête : soit un pourcentage consommé, soit un
/// montant quand le fournisseur raisonne en argent et pas en quota.
struct MeterItem: Identifiable {
  let id: String
  var title: String
  var usedPercent: Double? = nil
  var amount: String? = nil
  var caption: String = ""
  var help: String = ""
  /// Teinte imposée, pour un compteur qui n'est pas un quota à épuiser.
  var accent: Color? = nil
}

/// La rangée compacte de l'en-tête, commune à Claude, Codex et Cursor.
///
/// Même lecture que Claude Code : le chiffre et la barre montent avec la
/// consommation, et la couleur passe du vert au rouge à mesure qu'il reste
/// moins de marge.
struct MeterRow: View {
  let items: [MeterItem]

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        if index > 0 { Divider().frame(height: 62) }
        meter(item)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func meter(_ item: MeterItem) -> some View {
    let remaining = item.usedPercent.map { max(0, min(100, 100 - $0)) }
    return VStack(alignment: .leading, spacing: 5) {
      Text(item.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
      Text(item.amount ?? usedLabel(item.usedPercent))
        .font(.system(size: 22, weight: .semibold, design: .rounded))
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
      ProgressView(value: item.usedPercent ?? 0, total: 100)
        .tint(item.accent ?? meterTint(remaining))
      Text(item.caption.isEmpty ? " " : item.caption)
        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .help(item.help)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(item.title)
    .accessibilityValue(item.amount ?? usedLabel(item.usedPercent))
    .accessibilityHint(item.help)
  }
}

/// Encadré d'en-tête d'un harness : nom de l'offre, prix, puis le contenu.
struct HarnessAccountBox<Content: View>: View {
  let title: String
  let systemImage: String
  let plan: SubscriptionAgent?
  @ViewBuilder let content: () -> Content

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(title, systemImage: systemImage)
            .font(.headline).lineLimit(1).truncationMode(.tail)
          Spacer(minLength: 12)
          if let price = plan?.pricePerMonth {
            // Le prix ne doit jamais être rogné par un titre trop long.
            Text(planPrice(price) + " / mois " + planPriceTaxNote)
              .foregroundStyle(.secondary).help(planPriceExplanation)
              .lineLimit(1).fixedSize()
          }
        }
        content()
      }.padding(12)
    }
  }
}

/// Vert : de la marge. Orange : à surveiller. Rouge : bientôt bloqué.
func meterTint(_ remaining: Double?) -> Color {
  guard let remaining else { return .secondary }
  if remaining < 15 { return .red }
  if remaining < 40 { return .orange }
  return BurnTheme.green
}

/// Pourcentage consommé, la convention qu'affiche Claude Code.
func usedLabel(_ used: Double?) -> String {
  guard let used else { return "—" }
  return max(0, min(100, used)).formatted(
    .number.precision(.fractionLength(1)).locale(burnLocale)) + "%"
}

/// « 88 % restants · réinit. 20 sept. à 22:00 », sous le pourcentage consommé.
func meterCaption(used: Double?, reset: Date?, showsTime: Bool = false, resetWord: String = "réinit.")
  -> String
{
  var parts: [String] = []
  if let used {
    let remaining = max(0, min(100, 100 - used))
    parts.append(
      remaining.formatted(.number.precision(.fractionLength(0)).locale(burnLocale))
        + " % restants")
  }
  if let reset { parts.append(resetWord + " " + meterDate(reset, showsTime: showsTime)) }
  return parts.joined(separator: " · ")
}

/// Date courte, sans année : « 20 sept. » ou « 20 sept. à 22:00 ».
func meterDate(_ date: Date, showsTime: Bool = false) -> String {
  showsTime
    ? date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(burnLocale))
    : date.formatted(.dateTime.day().month(.abbreviated).locale(burnLocale))
}

/// Convertit un horodatage en millisecondes venu du CLI.
func meterDate(milliseconds: Double?) -> Date? {
  guard let milliseconds, milliseconds.isFinite, milliseconds > 0 else { return nil }
  return Date(timeIntervalSince1970: milliseconds / 1000)
}
