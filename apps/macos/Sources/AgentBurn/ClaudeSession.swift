import Foundation
import Observation
import Security
import SwiftUI

/// Renouvellement de la session Claude Code sans repasser par `claude /login`.
///
/// Claude Code stocke deux jetons dans le trousseau : un `accessToken` qui ne
/// vit que huit heures, et un `refreshToken` valable un mois. Agent Burn se
/// contentait de lire le premier ; on utilise ici le second pour en obtenir un
/// neuf, exactement comme le fait Claude Code lui-même.
@Observable @MainActor final class ClaudeSession {
  static let shared = ClaudeSession()

  nonisolated static let service = "Claude Code-credentials"
  nonisolated static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  /// `console.anthropic.com` renvoie 404 : le renouvellement a migré ici.
  nonisolated static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
  /// Cloudflare protège ce point d'accès et rejette en 429 tout agent inconnu.
  nonisolated static let userAgent = "claude-code/20.0.20"

  private(set) var isRefreshing = false
  private(set) var message: String?
  private(set) var failed = false

  /// Date d'expiration du jeton court, lue à chaque appel : Claude Code peut
  /// l'avoir renouvelé de son côté entre-temps.
  var expiresAt: Date? {
    guard let oauth = Self.storedOAuth() else { return nil }
    return (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
  }

  var isExpired: Bool {
    guard let expiresAt else { return false }
    return expiresAt <= Date()
  }

  func refresh() async {
    isRefreshing = true
    failed = false
    defer { isRefreshing = false }
    do {
      let renewed = try await Self.renew()
      message =
        "Session renouvelée jusqu'au "
        + renewed.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(burnLocale))
    } catch let error as SessionError {
      failed = true
      message = error.text
    } catch {
      failed = true
      message = "Le renouvellement a échoué : \(error.localizedDescription)"
    }
  }

  enum SessionError: Error {
    case noCredentials, noRefreshToken, refused(Int), malformed, notWritten

    var text: String {
      switch self {
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

  // MARK: - Trousseau

  /// Le blob JSON brut de l'entrée « Claude Code-credentials ».
  nonisolated private static func storedCredentials() -> [String: Any]? {
    if let data = try? Data(contentsOf: sessionFile),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let oauth = json["claudeAiOauth"] as? [String: Any],
      let expires = oauth["expiresAt"] as? Double,
      Date(timeIntervalSince1970: expires / 1000) > Date()
    {
      return json
    }
    return keychainCredentials()
  }

  nonisolated private static func keychainCredentials() -> [String: Any]? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return json
  }

  nonisolated private static func storedOAuth() -> [String: Any]? {
    storedCredentials()?["claudeAiOauth"] as? [String: Any]
  }

  /// Fichier où Agent Burn range le jeton qu'il a renouvelé lui-même.
  ///
  /// On n'écrit délibérément pas dans le trousseau : toute réécriture de
  /// l'entrée efface sa liste de contrôle d'accès, et macOS se remet à demander
  /// le mot de passe à chaque lecture. Le CLI lit ce fichier en priorité.
  nonisolated static var sessionFile: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Agent Burn/claude-session.json")
  }

  nonisolated private static func write(_ credentials: [String: Any]) throws {
    let directory = sessionFile.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let data = try JSONSerialization.data(withJSONObject: credentials)
    try data.write(to: sessionFile, options: .atomic)
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: sessionFile.path)
  }

  // MARK: - Renouvellement

  private struct Response: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
  }

  /// Échange le jeton de renouvellement contre un nouvel `accessToken`.
  /// Renvoie la nouvelle date d'expiration.
  nonisolated private static func renew() async throws -> Date {
    guard var credentials = storedCredentials(),
      var oauth = credentials["claudeAiOauth"] as? [String: Any]
    else { throw SessionError.noCredentials }
    guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
      throw SessionError.noRefreshToken
    }

    var request = URLRequest(url: tokenURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "grant_type": "refresh_token",
      "refresh_token": refreshToken,
      "client_id": clientID,
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard code == 200 else { throw SessionError.refused(code) }
    guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
      throw SessionError.malformed
    }

    let expiresAt = Date().addingTimeInterval(decoded.expires_in ?? 8 * 3600)
    oauth["accessToken"] = decoded.access_token
    oauth["expiresAt"] = expiresAt.timeIntervalSince1970 * 1000
    // Anthropic ne renvoie un jeton de renouvellement que s'il l'a fait tourner.
    // L'omettre ne veut pas dire « plus de jeton » : il faut garder l'ancien.
    if let rotated = decoded.refresh_token, !rotated.isEmpty { oauth["refreshToken"] = rotated }
    credentials["claudeAiOauth"] = oauth

    try write(credentials)
    return expiresAt
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
        "Le jeton de Claude Code ne vit que huit heures, alors que le jeton de renouvellement vaut un mois. Ce bouton échange le second contre un neuf, sans repasser par `claude /login`. À utiliser de préférence quand aucune session Claude Code ne tourne."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}
