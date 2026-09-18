import Foundation
import Security

/// Accès aux identifiants OAuth de Claude Code, et renouvellement du jeton.
///
/// Sans dépendance à SwiftUI : le collecteur en arrière-plan compile ce fichier
/// pour pouvoir renouveler la session quand l'app est fermée.
enum ClaudeCredentials {
  static let service = "Claude Code-credentials"
  static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  /// `console.anthropic.com` renvoie 404 : le renouvellement a migré ici.
  static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
  /// Cloudflare protège ce point d'accès et rejette en 429 tout agent inconnu.
  static let userAgent = "claude-code/20.0.20"

  enum Failure: Error {
    case noCredentials, noRefreshToken, refused(Int), malformed, notWritten
  }

  /// Fichier où Agent Burn range le jeton qu'il a renouvelé lui-même.
  ///
  /// On n'écrit délibérément pas dans le trousseau : toute réécriture de
  /// l'entrée efface sa liste de contrôle d'accès, et macOS se remet à demander
  /// le mot de passe à chaque lecture.
  static var sessionFile: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Agent Burn/claude-session.json")
  }

  static var expiresAt: Date? {
    guard let oauth = stored()?["claudeAiOauth"] as? [String: Any],
      let milliseconds = oauth["expiresAt"] as? Double
    else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
  }

  static var isExpired: Bool {
    guard let expiresAt else { return false }
    return expiresAt <= Date()
  }

  /// Identifiants à utiliser pour renouveler.
  ///
  /// Toujours le fichier en premier, même si son jeton court est périmé :
  /// Anthropic fait tourner le jeton de renouvellement, donc celui du trousseau
  /// est mort dès le premier échange. Retomber dessus condamnait le
  /// renouvellement à échouer exactement quand il devenait nécessaire.
  static func credentialsForRenewal() -> [String: Any]? {
    if let data = try? Data(contentsOf: sessionFile),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let oauth = json["claudeAiOauth"] as? [String: Any],
      let token = oauth["refreshToken"] as? String, !token.isEmpty
    {
      return json
    }
    return keychain()
  }

  /// Le fichier renouvelé s'il est encore valide, sinon le trousseau.
  static func stored() -> [String: Any]? {
    if let data = try? Data(contentsOf: sessionFile),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let oauth = json["claudeAiOauth"] as? [String: Any],
      let expires = oauth["expiresAt"] as? Double,
      Date(timeIntervalSince1970: expires / 1000) > Date()
    {
      return json
    }
    return keychain()
  }

  private static func keychain() -> [String: Any]? {
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

  private static func write(_ credentials: [String: Any]) throws {
    let directory = sessionFile.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let data = try JSONSerialization.data(withJSONObject: credentials)
    try data.write(to: sessionFile, options: .atomic)
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: sessionFile.path)
  }

  private struct Response: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
  }

  /// Échange le jeton de renouvellement contre un nouvel `accessToken`.
  @discardableResult static func renew() async throws -> Date {
    guard var credentials = credentialsForRenewal(),
      var oauth = credentials["claudeAiOauth"] as? [String: Any]
    else { throw Failure.noCredentials }
    guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
      throw Failure.noRefreshToken
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
    guard code == 200 else { throw Failure.refused(code) }
    guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
      throw Failure.malformed
    }

    let expiresAt = Date().addingTimeInterval(decoded.expires_in ?? 8 * 3600)
    oauth["accessToken"] = decoded.access_token
    oauth["expiresAt"] = expiresAt.timeIntervalSince1970 * 1000
    // Anthropic ne renvoie un jeton de renouvellement que s'il l'a fait tourner.
    // L'omettre ne veut pas dire « plus de jeton » : il faut garder l'ancien.
    if let rotated = decoded.refresh_token, !rotated.isEmpty { oauth["refreshToken"] = rotated }
    credentials["claudeAiOauth"] = oauth

    do { try write(credentials) } catch { throw Failure.notWritten }
    return expiresAt
  }

  /// Renouvelle seulement si le jeton est périmé. Silencieux en cas d'échec :
  /// l'app affiche déjà le motif, et le relevé suivant réessaiera.
  static func renewIfExpired() async {
    guard isExpired else { return }
    _ = try? await renew()
  }
}
