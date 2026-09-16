import Foundation
import Observation
import SwiftUI

/// Dernier taux connu, lisible depuis n'importe quel contexte par `currency(_:)`.
///
/// `CurrencyRate` vit sur le main actor pour l'affichage, mais les helpers de
/// formatage sont des fonctions libres appelées depuis des contextes variés.
final class CurrentRate: @unchecked Sendable {
  static let shared = CurrentRate()
  private let lock = NSLock()
  private var value = CurrencyRate.fallback
  private var vat = 1 + CurrencyRate.defaultVatPercent / 100
  var rate: Double {
    get { lock.lock(); defer { lock.unlock() }; return value }
    set { lock.lock(); value = newValue; lock.unlock() }
  }
  /// Coefficient à appliquer au prix d'un abonnement : 1,2 pour une TVA à 20 %.
  var vatMultiplier: Double {
    get { lock.lock(); defer { lock.unlock() }; return vat }
    set { lock.lock(); vat = newValue; lock.unlock() }
  }
}

/// Taux de conversion du dollar vers la devise d'affichage.
///
/// Les montants renvoyés par le CLI sont toujours en dollars : le taux est
/// récupéré en ligne au lancement, mis en cache dans les préférences, et
/// remplacé par une valeur de repli quand le réseau est indisponible.
@Observable @MainActor final class CurrencyRate {
  static let shared = CurrencyRate()

  /// Devise d'affichage, et repli utilisé tant qu'aucun taux n'a été récupéré.
  nonisolated static let code = "EUR"
  nonisolated static let fallback = 0.92
  /// TVA française, appliquée par défaut au prix des abonnements.
  nonisolated static let defaultVatPercent = 20.0
  /// Au-delà, le taux en cache est considéré comme périmé.
  private static let maxAge: TimeInterval = 12 * 3600

  private let defaults: UserDefaults
  private let fetch: () async throws -> Double

  private(set) var rate: Double
  private(set) var updatedAt: Date?
  private(set) var isStale: Bool

  /// Ajoute la TVA aux prix d'abonnement : les tarifs du CLI sont hors taxes.
  var vatApplied: Bool {
    didSet {
      defaults.set(vatApplied, forKey: "vatApplied")
      publishVat()
    }
  }
  var vatPercent: Double {
    didSet {
      defaults.set(vatPercent, forKey: "vatPercent")
      publishVat()
    }
  }

  private func publishVat() {
    CurrentRate.shared.vatMultiplier = vatApplied ? 1 + max(0, vatPercent) / 100 : 1
  }

  init(
    defaults: UserDefaults = .standard,
    fetch: @escaping () async throws -> Double = CurrencyRate.fetchLive
  ) {
    self.defaults = defaults
    self.fetch = fetch
    let stored = defaults.double(forKey: "usdRate")
    rate = stored > 0 ? stored : Self.fallback
    let timestamp = defaults.double(forKey: "usdRateUpdatedAt")
    updatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    isStale = stored <= 0
    vatApplied = defaults.object(forKey: "vatApplied") as? Bool ?? true
    let storedVat = defaults.double(forKey: "vatPercent")
    vatPercent = storedVat > 0 ? storedVat : Self.defaultVatPercent
    CurrentRate.shared.rate = rate
    publishVat()
  }

  /// Convertit un montant en dollars vers la devise d'affichage.
  func convert(_ usd: Double) -> Double { usd * rate }

  /// Récupère un taux frais si celui en cache a dépassé sa durée de vie.
  func refreshIfNeeded() async {
    if let updatedAt, Date().timeIntervalSince(updatedAt) < Self.maxAge, !isStale { return }
    await refresh()
  }

  func refresh() async {
    do {
      let value = try await fetch()
      guard value.isFinite, value > 0 else { return }
      rate = value
      CurrentRate.shared.rate = value
      updatedAt = Date()
      isStale = false
      defaults.set(value, forKey: "usdRate")
      defaults.set(Date().timeIntervalSince1970, forKey: "usdRateUpdatedAt")
    } catch {
      // Le taux en cache (ou le repli) reste affiché, signalé comme périmé.
      isStale = true
    }
  }

  private struct Response: Decodable { let rates: [String: Double] }

  /// Taux de référence publié par la Banque centrale européenne, via Frankfurter.
  private static func fetchLive() async throws -> Double {
    let url = URL(string: "https://api.frankfurter.app/latest?from=USD&to=\(code)")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    guard let value = try JSONDecoder().decode(Response.self, from: data).rates[code] else {
      throw URLError(.cannotParseResponse)
    }
    return value
  }
}

struct CurrencySettings: View {
  @Bindable private var rate = CurrencyRate.shared
  @State private var isRefreshing = false

  var body: some View {
    Section("Devise") {
      LabeledContent("Taux dollar → euro") {
        Text(rate.rate.formatted(.number.precision(.fractionLength(4)).locale(burnLocale)))
          .monospacedDigit()
      }
      Button(isRefreshing ? "Récupération…" : "Actualiser le taux") {
        isRefreshing = true
        Task {
          await rate.refresh()
          isRefreshing = false
        }
      }
      .disabled(isRefreshing)
      Text(statusText).font(.caption).foregroundStyle(rate.isStale ? .orange : .secondary)
      Toggle("Ajouter la TVA au prix des abonnements", isOn: $rate.vatApplied)
      if rate.vatApplied {
        Picker("Taux de TVA", selection: $rate.vatPercent) {
          Text("20 % (France)").tag(20.0)
          Text("21 % (Belgique)").tag(21.0)
          Text("8,1 % (Suisse)").tag(8.1)
          Text("0 %").tag(0.0)
        }
      }
      Text(
        "Anthropic, OpenAI et Cursor affichent leurs tarifs en dollars hors taxes. Cette option ajoute la TVA aux prix d'abonnement pour retrouver ce que tu paies vraiment. Les valeurs équivalentes API restent hors taxes : ce sont des estimations, pas des factures."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var statusText: String {
    guard let updatedAt = rate.updatedAt else {
      return
        "Aucun taux récupéré pour l'instant : le taux de repli de \(CurrencyRate.fallback.formatted(.number.locale(burnLocale))) est appliqué. Les montants du CLI sont en dollars et convertis pour l'affichage."
    }
    let date = updatedAt.formatted(.dateTime.day().month().hour().minute().locale(burnLocale))
    if rate.isStale {
      return
        "Dernière récupération réussie le \(date). Le réseau n'a pas répondu depuis, ce taux reste appliqué."
    }
    return
      "Taux de référence de la Banque centrale européenne, récupéré le \(date). Les montants du CLI sont en dollars et convertis pour l'affichage."
  }
}
