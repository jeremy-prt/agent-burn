use std::{fs, sync::OnceLock, time::Duration};

use serde_json::{Value, json};

use crate::{TimestampMs, home, parse_ts_timestamp, utc_now};

const USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";
const FETCH_TIMEOUT_SECONDS: u64 = 5;
const FETCH_MAX_BYTES: u64 = 1_000_000;

/// A live Claude rate-limit window from the OAuth usage endpoint.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct UsageWindow {
    pub(crate) utilization: f64,
    pub(crate) resets_at: Option<TimestampMs>,
}

/// A model-scoped weekly window (Fable, Opus, Sonnet) from the modern `limits` array.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct ScopedWindow {
    pub(crate) name: String,
    pub(crate) utilization: f64,
    pub(crate) resets_at: Option<TimestampMs>,
}

/// Extra-usage / spend credits reported beside the rate-limit windows.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct ExtraUsage {
    pub(crate) enabled: bool,
    pub(crate) used_usd: Option<f64>,
    pub(crate) limit_usd: Option<f64>,
    pub(crate) used_percent: Option<f64>,
}

/// Live Claude subscription meters from the OAuth usage endpoint.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct ClaudeUsageLimits {
    pub(crate) five_hour: Option<UsageWindow>,
    pub(crate) seven_day: Option<UsageWindow>,
    pub(crate) scoped: Vec<ScopedWindow>,
    pub(crate) extra_usage: Option<ExtraUsage>,
}

/// Why live Claude meters are missing, so callers can say something useful
/// instead of a single catch-all message.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum Unavailable {
    Offline,
    NoToken,
    TokenExpired,
    /// Anthropic throttles this endpoint; polling it too often earns a 429.
    RateLimited,
    Unreachable,
    Empty,
}

impl Unavailable {
    /// Stable key consumed by the macOS app, which owns the wording.
    pub(crate) fn code(self) -> &'static str {
        match self {
            Self::Offline => "offline",
            Self::NoToken => "no-token",
            Self::TokenExpired => "token-expired",
            Self::RateLimited => "rate-limited",
            Self::Unreachable => "unreachable",
            Self::Empty => "empty",
        }
    }

    pub(crate) fn message(self) -> &'static str {
        match self {
            Self::Offline => "no live limits available (cached mode)",
            Self::NoToken => "no live limits available (no signed-in token)",
            Self::TokenExpired => "no live limits available (token expired, sign in again)",
            Self::RateLimited => "no live limits available (rate limited by Anthropic, retry later)",
            Self::Unreachable => "no live limits available (request failed)",
            Self::Empty => "no live limits reported for this account",
        }
    }
}

/// Fetch the signed-in account's live usage limits from Anthropic, mirroring
/// the call Claude Code's status line makes. Never fatal: every failure maps to
/// an `Unavailable` reason.
/// One HTTP call per process. A single `summary --value` run asks for these
/// limits from several places, and Anthropic throttles this endpoint hard
/// enough that repeating the request inside one run earns a 429.
static CACHED: OnceLock<Result<ClaudeUsageLimits, Unavailable>> = OnceLock::new();

pub(crate) fn usage_limits_result(offline: bool) -> Result<ClaudeUsageLimits, Unavailable> {
    CACHED.get_or_init(|| fetch_limits(offline)).clone()
}

fn fetch_limits(offline: bool) -> Result<ClaudeUsageLimits, Unavailable> {
    if offline {
        return Err(Unavailable::Offline);
    }
    let credentials = read_credentials().ok_or(Unavailable::NoToken)?;
    let token = token_from_credentials(&credentials).ok_or(Unavailable::NoToken)?;
    if expired(&credentials) {
        return Err(Unavailable::TokenExpired);
    }
    fetch_usage_limits(&token)
}

pub(crate) fn usage_limits(offline: bool) -> Option<ClaudeUsageLimits> {
    usage_limits_result(offline).ok()
}

/// Current Claude meters for `summary --value --json`, or why they are missing.
pub(crate) fn load_account_result(offline: bool) -> Result<Value, Unavailable> {
    let limits = usage_limits_result(offline)?;
    if limits == ClaudeUsageLimits::default() {
        return Err(Unavailable::Empty);
    }
    Ok(account_json(&limits))
}

/// The raw credentials blob.
///
/// The macOS app's own renewed session comes first: reading the keychain makes
/// macOS prompt for a password whenever the item's access list has been reset,
/// and the renewed file avoids that round trip entirely.
fn read_credentials() -> Option<String> {
    if let Some(json) = renewed_credentials() {
        return Some(json);
    }
    #[cfg(target_os = "macos")]
    if let Some(json) = keychain_credentials() {
        return Some(json);
    }
    file_credentials()
}

/// Session renewed by the macOS app, ignored once its access token has expired.
fn renewed_credentials() -> Option<String> {
    let path = home::home_dir()?
        .join("Library/Application Support/Agent Burn")
        .join("claude-session.json");
    let json = fs::read_to_string(path).ok()?;
    let expires_at = expiry_from_credentials(&json)?;
    (expires_at > utc_now().as_millis()).then_some(json)
}

/// An access token past its expiry is refused with a 401, so name that case.
fn expired(credentials: &str) -> bool {
    let Some(expires_at) = expiry_from_credentials(credentials) else {
        return false;
    };
    expires_at <= utc_now().as_millis()
}

fn expiry_from_credentials(json: &str) -> Option<i64> {
    // Claude Code écrit un flottant (« 1789609419934.927 ») : `as_i64` échoue
    // dessus et laissait passer des jetons déjà expirés.
    let expires_at = serde_json::from_str::<Value>(json.trim())
        .ok()?
        .get("claudeAiOauth")?
        .get("expiresAt")?
        .as_f64()?;
    expires_at.is_finite().then(|| expires_at as i64)
}

#[cfg(target_os = "macos")]
fn keychain_credentials() -> Option<String> {
    let output = std::process::Command::new("security")
        .args([
            "find-generic-password",
            "-s",
            "Claude Code-credentials",
            "-w",
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    String::from_utf8(output.stdout).ok()
}

fn file_credentials() -> Option<String> {
    let path = home::home_dir()?.join(".claude").join(".credentials.json");
    fs::read_to_string(path).ok()
}

fn token_from_credentials(json: &str) -> Option<String> {
    let value = serde_json::from_str::<Value>(json.trim()).ok()?;
    value
        .get("claudeAiOauth")?
        .get("accessToken")?
        .as_str()
        .map(str::to_string)
}

fn fetch_usage_limits(token: &str) -> Result<ClaudeUsageLimits, Unavailable> {
    let agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(FETCH_TIMEOUT_SECONDS)))
        // Sans cela, ureq renvoie une erreur dès qu'un statut dépasse 400 et
        // l'on ne peut plus distinguer un 429 d'une panne réseau.
        .http_status_as_error(false)
        .build()
        .new_agent();
    let mut response = agent
        .get(USAGE_URL)
        .header("Authorization", &format!("Bearer {token}"))
        .header("anthropic-beta", "oauth-2025-04-20")
        .header("Accept", "application/json")
        .header(
            "User-Agent",
            concat!("claude-code/", env!("CARGO_PKG_VERSION")),
        )
        .call()
        .map_err(|_| Unavailable::Unreachable)?;
    match response.status().as_u16() {
        200 => {}
        429 => return Err(Unavailable::RateLimited),
        401 | 403 => return Err(Unavailable::TokenExpired),
        _ => return Err(Unavailable::Unreachable),
    }
    let body = response
        .body_mut()
        .with_config()
        .limit(FETCH_MAX_BYTES)
        .read_to_string()
        .map_err(|_| Unavailable::Unreachable)?;
    parse_usage_limits(&body).ok_or(Unavailable::Empty)
}

fn parse_usage_limits(body: &str) -> Option<ClaudeUsageLimits> {
    let value = serde_json::from_str::<Value>(body).ok()?;
    let mut limits = ClaudeUsageLimits {
        five_hour: parse_window(value.get("five_hour")),
        seven_day: parse_window(value.get("seven_day")),
        scoped: Vec::new(),
        extra_usage: parse_extra_usage(&value),
    };
    apply_limits_array(&mut limits, value.get("limits"));
    Some(limits)
}

fn account_json(limits: &ClaudeUsageLimits) -> Value {
    json!({
        "sessionUsedPercent": limits.five_hour.map(|window| window.utilization),
        "sessionResetsAtMs": limits
            .five_hour
            .and_then(|window| window.resets_at)
            .map(TimestampMs::as_millis),
        "weeklyUsedPercent": limits.seven_day.map(|window| window.utilization),
        "weeklyResetsAtMs": limits
            .seven_day
            .and_then(|window| window.resets_at)
            .map(TimestampMs::as_millis),
        "scoped": limits
            .scoped
            .iter()
            .map(|window| {
                json!({
                    "name": window.name,
                    "usedPercent": window.utilization,
                    "resetsAtMs": window.resets_at.map(TimestampMs::as_millis),
                })
            })
            .collect::<Vec<_>>(),
        "extraEnabled": limits.extra_usage.as_ref().map(|extra| extra.enabled),
        "extraUsedUSD": limits.extra_usage.and_then(|extra| extra.used_usd),
        "extraLimitUSD": limits.extra_usage.and_then(|extra| extra.limit_usd),
        "extraUsedPercent": limits.extra_usage.and_then(|extra| extra.used_percent),
    })
}

fn apply_limits_array(limits: &mut ClaudeUsageLimits, value: Option<&Value>) {
    let Some(entries) = value.and_then(Value::as_array) else {
        return;
    };
    for entry in entries {
        let Some(kind) = entry.get("kind").and_then(Value::as_str) else {
            continue;
        };
        let Some(window) = parse_limit_entry(entry) else {
            continue;
        };
        match kind {
            "session" if limits.five_hour.is_none() => limits.five_hour = Some(window),
            "weekly_all" if limits.seven_day.is_none() => limits.seven_day = Some(window),
            "weekly_scoped" => {
                if let Some(name) = scoped_name(entry) {
                    limits.scoped.push(ScopedWindow {
                        name,
                        utilization: window.utilization,
                        resets_at: window.resets_at,
                    });
                }
            }
            _ => {}
        }
    }
}

fn parse_limit_entry(entry: &Value) -> Option<UsageWindow> {
    let utilization = entry
        .get("percent")
        .and_then(json_percent)
        .or_else(|| entry.get("utilization").and_then(json_percent))?;
    Some(UsageWindow {
        utilization,
        resets_at: entry
            .get("resets_at")
            .and_then(Value::as_str)
            .and_then(parse_reset_time),
    })
}

fn scoped_name(entry: &Value) -> Option<String> {
    let scope = entry.get("scope")?;
    scope
        .get("model")
        .and_then(|model| model.get("display_name").or_else(|| model.get("id")))
        .and_then(Value::as_str)
        .filter(|name| !name.is_empty())
        .map(str::to_string)
        .or_else(|| {
            scope
                .as_str()
                .filter(|name| !name.is_empty())
                .map(str::to_string)
        })
}

fn parse_window(value: Option<&Value>) -> Option<UsageWindow> {
    let window = value.filter(|window| !window.is_null())?;
    Some(UsageWindow {
        utilization: json_percent(window.get("utilization")?)?,
        resets_at: window
            .get("resets_at")
            .and_then(Value::as_str)
            .and_then(parse_reset_time),
    })
}

fn parse_extra_usage(value: &Value) -> Option<ExtraUsage> {
    if let Some(extra) = value.get("extra_usage").filter(|extra| !extra.is_null()) {
        let enabled = extra
            .get("is_enabled")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let used_usd = extra
            .get("used_credits")
            .and_then(Value::as_f64)
            .filter(|amount| amount.is_finite())
            .map(|amount| amount / 100.0);
        let limit_usd = extra
            .get("monthly_limit")
            .and_then(Value::as_f64)
            .filter(|amount| amount.is_finite() && *amount > 0.0)
            .map(|amount| amount / 100.0);
        let used_percent = extra.get("utilization").and_then(json_percent);
        if enabled || used_usd.is_some() || limit_usd.is_some() {
            return Some(ExtraUsage {
                enabled,
                used_usd,
                limit_usd,
                used_percent,
            });
        }
    }
    parse_spend(value.get("spend")?)
}

fn parse_spend(spend: &Value) -> Option<ExtraUsage> {
    if spend.is_null() {
        return None;
    }
    let enabled = spend
        .get("enabled")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let used_usd = money(spend.get("used"));
    let limit_usd = money(spend.get("limit"));
    let used_percent = spend.get("percent").and_then(json_percent);
    (enabled || used_usd.is_some() || limit_usd.is_some()).then_some(ExtraUsage {
        enabled,
        used_usd,
        limit_usd,
        used_percent,
    })
}

fn money(value: Option<&Value>) -> Option<f64> {
    let value = value.filter(|value| !value.is_null())?;
    if let Some(amount) = value.as_f64().filter(|amount| amount.is_finite()) {
        return Some(amount);
    }
    let amount = value
        .get("amount_minor")
        .and_then(Value::as_f64)
        .filter(|amount| amount.is_finite())?;
    let exponent = value.get("exponent").and_then(Value::as_i64).unwrap_or(2);
    Some(amount / 10f64.powi(i32::try_from(exponent).ok()?))
}

fn json_percent(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .filter(|percent| percent.is_finite())
        .map(|percent| percent.clamp(0.0, 100.0))
}

/// Parse an RFC 3339 reset time, tolerating the sub-millisecond precision the
/// usage endpoint emits (e.g. `…:59.434813+00:00`) which the strict shared
/// parser rejects. Sub-second digits are truncated to milliseconds.
fn parse_reset_time(value: &str) -> Option<TimestampMs> {
    if let Some(timestamp) = parse_ts_timestamp(value) {
        return Some(timestamp);
    }
    let dot = value.find('.')?;
    let after = &value[dot + 1..];
    let fractional_len = after.bytes().take_while(u8::is_ascii_digit).count();
    let millis: String = after[..fractional_len]
        .chars()
        .chain(std::iter::repeat('0'))
        .take(3)
        .collect();
    let normalized = format!("{}.{millis}{}", &value[..dot], &after[fractional_len..]);
    parse_ts_timestamp(&normalized)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format_rfc3339_millis;

    #[test]
    fn parses_usage_windows_from_response_body() {
        let body = r#"{"five_hour":{"utilization":23,"resets_at":"2026-06-13T15:39:59.434793+00:00"},"seven_day":{"utilization":12,"resets_at":"2026-06-14T08:59:59.434813+00:00"}}"#;

        let limits = parse_usage_limits(body).unwrap();

        let seven_day = limits.seven_day.unwrap();
        assert_eq!(seven_day.utilization, 12.0);
        assert_eq!(
            format_rfc3339_millis(seven_day.resets_at.unwrap()),
            "2026-06-14T08:59:59.434Z"
        );
        assert_eq!(limits.five_hour.unwrap().utilization, 23.0);
    }

    #[test]
    fn treats_null_windows_as_absent() {
        let limits = parse_usage_limits(r#"{"five_hour":null,"seven_day":null}"#).unwrap();
        assert_eq!(limits, ClaudeUsageLimits::default());
    }

    #[test]
    fn reads_session_and_weekly_from_modern_limits_array() {
        let limits = parse_usage_limits(
            r#"{
              "five_hour": null,
              "seven_day": null,
              "limits": [
                {"kind":"session","percent":18,"resets_at":"2026-09-12T12:00:00Z"},
                {"kind":"weekly_all","percent":9,"resets_at":"2026-09-14T08:59:59.434813+00:00"},
                {"kind":"weekly_scoped","percent":15,"resets_at":"2026-09-14T08:59:59Z","scope":{"model":{"display_name":"Fable"}}}
              ]
            }"#,
        )
        .unwrap();

        let session = limits.five_hour.unwrap();
        assert_eq!(session.utilization, 18.0);
        assert_eq!(
            format_rfc3339_millis(session.resets_at.unwrap()),
            "2026-09-12T12:00:00.000Z"
        );

        let weekly = limits.seven_day.unwrap();
        assert_eq!(weekly.utilization, 9.0);
        assert_eq!(
            format_rfc3339_millis(weekly.resets_at.unwrap()),
            "2026-09-14T08:59:59.434Z"
        );
        assert_eq!(limits.scoped.len(), 1);
        assert_eq!(limits.scoped[0].name, "Fable");
        assert_eq!(limits.scoped[0].utilization, 15.0);
    }

    #[test]
    fn prefers_legacy_windows_when_both_shapes_are_present() {
        let limits = parse_usage_limits(
            r#"{
              "five_hour":{"utilization":23,"resets_at":"2026-06-13T15:39:59Z"},
              "seven_day":{"utilization":12,"resets_at":"2026-06-14T08:59:59Z"},
              "limits":[{"kind":"session","percent":99},{"kind":"weekly_all","percent":88}]
            }"#,
        )
        .unwrap();
        assert_eq!(limits.five_hour.unwrap().utilization, 23.0);
        assert_eq!(limits.seven_day.unwrap().utilization, 12.0);
    }

    #[test]
    fn reads_extra_usage_credits_in_cents() {
        let limits = parse_usage_limits(
            r#"{
              "five_hour":null,
              "seven_day":null,
              "extra_usage":{
                "is_enabled":true,
                "monthly_limit":1700,
                "used_credits":190.0,
                "utilization":11.18
              }
            }"#,
        )
        .unwrap();
        let extra = limits.extra_usage.unwrap();
        assert!(extra.enabled);
        assert_eq!(extra.used_usd, Some(1.9));
        assert_eq!(extra.limit_usd, Some(17.0));
        assert_eq!(extra.used_percent, Some(11.18));
    }

    #[test]
    fn reads_spend_object_as_extra_usage() {
        let limits = parse_usage_limits(
            r#"{
              "spend":{
                "enabled":true,
                "percent":4,
                "used":{"amount_minor":6123,"currency":"USD","exponent":2},
                "limit":{"amount_minor":150000,"currency":"USD","exponent":2}
              }
            }"#,
        )
        .unwrap();
        let extra = limits.extra_usage.unwrap();
        assert!(extra.enabled);
        assert_eq!(extra.used_usd, Some(61.23));
        assert_eq!(extra.limit_usd, Some(1500.0));
        assert_eq!(extra.used_percent, Some(4.0));
    }

    #[test]
    fn account_json_exposes_session_weekly_scoped_and_credits() {
        let limits = parse_usage_limits(
            r#"{
              "limits":[
                {"kind":"session","percent":18,"resets_at":"2026-09-12T12:00:00Z"},
                {"kind":"weekly_all","percent":9,"resets_at":"2026-09-14T08:59:59Z"},
                {"kind":"weekly_scoped","percent":15,"resets_at":"2026-09-14T08:59:59Z","scope":{"model":{"display_name":"Fable"}}}
              ],
              "extra_usage":{"is_enabled":true,"monthly_limit":100000,"used_credits":2500,"utilization":2.5}
            }"#,
        )
        .unwrap();
        let account = account_json(&limits);
        assert_eq!(account["sessionUsedPercent"], 18.0);
        assert_eq!(account["weeklyUsedPercent"], 9.0);
        assert_eq!(account["scoped"][0]["name"], "Fable");
        assert_eq!(account["scoped"][0]["usedPercent"], 15.0);
        assert_eq!(account["extraEnabled"], true);
        assert_eq!(account["extraUsedUSD"], 25.0);
        assert_eq!(account["extraLimitUSD"], 1000.0);
        assert_eq!(account["extraUsedPercent"], 2.5);
    }

    #[test]
    fn reads_access_token_from_credentials_json() {
        let json = r#"{"claudeAiOauth":{"accessToken":"sk-ant-oat-abc","refreshToken":"r","expiresAt":1}}"#;
        assert_eq!(
            token_from_credentials(json).as_deref(),
            Some("sk-ant-oat-abc")
        );
    }
}
