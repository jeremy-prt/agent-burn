import Foundation

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

  static var expiresAt: Date? {
    guard let oauth = keychain()?["claudeAiOauth"] as? [String: Any],
      let milliseconds = oauth["expiresAt"] as? Double
    else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
  }

  static var isExpired: Bool {
    guard let expiresAt else { return false }
    return expiresAt <= Date()
  }

  /// Passe par `/usr/bin/security` plutôt que `SecItemCopyMatching` : l'entrée
  /// n'accepte que la partition `apple-tool:`, qu'une app signée ad-hoc ne peut
  /// pas rejoindre, d'où un mot de passe demandé à chaque lecture.
  private static func keychain() -> [String: Any]? {
    guard let data = security(["find-generic-password", "-s", service, "-w"]) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  /// Réécrit l'entrée de Claude Code, qui garde ainsi le jeton tourné : un
  /// fichier à part laissait au trousseau un jeton de renouvellement mort.
  /// Pas de `security -i` : il coupe les lignes vers 4 Ko et a déjà tronqué
  /// l'entrée. La relecture vérifie que Claude Code retrouvera un JSON entier.
  private static func write(_ credentials: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: credentials)
    let hex = data.map { String(format: "%02x", $0) }.joined()
    let arguments = ["add-generic-password", "-U", "-a", NSUserName(), "-s", service, "-X", hex]
    guard security(arguments) != nil,
      let written = keychain()?["claudeAiOauth"] as? [String: Any],
      let expected = credentials["claudeAiOauth"] as? [String: Any],
      written["accessToken"] as? String == expected["accessToken"] as? String
    else { throw Failure.notWritten }
  }

  private static func security(_ arguments: [String]) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? data : nil
  }

  private struct Response: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
  }

  /// Échange le jeton de renouvellement contre un nouvel `accessToken`.
  @discardableResult static func renew() async throws -> Date {
    guard var credentials = keychain(),
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

    try write(credentials)
    return expiresAt
  }

  /// Renouvelle seulement si le jeton est périmé. Silencieux en cas d'échec :
  /// l'app affiche déjà le motif, et le relevé suivant réessaiera.
  static func renewIfExpired() async {
    guard isExpired else { return }
    _ = try? await renew()
  }
}
