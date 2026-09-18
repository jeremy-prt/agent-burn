import Foundation
import Observation
import SwiftUI

/// État de la session Claude Code pour l'interface, au-dessus de
/// `ClaudeCredentials` qui porte toute la logique.
@Observable @MainActor final class ClaudeSession {
  static let shared = ClaudeSession()

  private(set) var isRefreshing = false
  private(set) var message: String?
  private(set) var failed = false

  var expiresAt: Date? { ClaudeCredentials.expiresAt }
  var isExpired: Bool { ClaudeCredentials.isExpired }

  func refresh() async {
    isRefreshing = true
    failed = false
    defer { isRefreshing = false }
    do {
      let renewed = try await ClaudeCredentials.renew()
      message =
        "Session renouvelée jusqu'au "
        + renewed.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(burnLocale))
    } catch let failure as ClaudeCredentials.Failure {
      failed = true
      message = Self.text(for: failure)
    } catch {
      failed = true
      message = "Le renouvellement a échoué : \(error.localizedDescription)"
    }
  }

  private static func text(for failure: ClaudeCredentials.Failure) -> String {
    switch failure {
    case .noCredentials: "Aucune session Claude Code trouvée. Lance `claude /login`."
    case .noRefreshToken:
      "La session enregistrée n'a pas de jeton de renouvellement. Lance `claude /login`."
    case .refused(let code):
      switch code {
      case 400, 401:
        // invalid_grant : le jeton de renouvellement a expiré ou a déjà servi.
        "Anthropic a refusé le jeton de renouvellement : il a expiré ou a déjà servi. Lance `claude /login`."
      case 429:
        // La requête est rejetée avant traitement : le jeton reste intact.
        "Anthropic limite temporairement les appels. Ton jeton n'a pas été consommé, réessaie dans une heure."
      default:
        "Anthropic a répondu \(code). Réessaie dans un moment."
      }
    case .malformed: "Réponse inattendue d'Anthropic."
    case .notWritten: "Le nouveau jeton n'a pas pu être écrit sur le disque."
    }
  }
}

/// Bouton « Renouveler la session », affiché quand le jeton court est périmé.
struct ClaudeSessionButton: View {
  @Bindable private var session = ClaudeSession.shared
  @Environment(UsageStore.self) private var store

  var body: some View {
    HStack(spacing: 10) {
      Button(session.isRefreshing ? "Renouvellement…" : "Renouveler la session") {
        Task {
          await session.refresh()
          if !session.failed { await store.refreshAll() }
        }
      }
      .disabled(session.isRefreshing)
      if let message = session.message {
        Text(message)
          .font(.caption).foregroundStyle(session.failed ? .orange : .secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// Section des réglages : état de la session et renouvellement à la demande.
struct ClaudeSessionSettings: View {
  private var session = ClaudeSession.shared

  var body: some View {
    Section("Session Claude Code") {
      LabeledContent("Jeton valide jusqu'à") {
        Text(
          session.expiresAt.map {
            $0.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(burnLocale))
          } ?? "aucune session trouvée"
        )
        .foregroundStyle(session.isExpired ? .orange : .secondary)
      }
      ClaudeSessionButton()
      Text(
        "Le jeton de Claude Code ne vit que huit heures, alors que le jeton de renouvellement vaut un mois. L'app échange le second contre un neuf dès qu'elle voit le premier périmé, sans repasser par `claude /login`. Ce bouton force l'échange immédiatement."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}
