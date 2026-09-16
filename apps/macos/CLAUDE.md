# App macOS — fork perso

Ce fork n'est pas destiné à remonter chez l'upstream : l'interface est adaptée
à un usage personnel et diverge volontairement.

## Interface en français, montants en euros

Toute chaîne visible par l'utilisateur s'écrit en français, commentaires de code
compris. Les montants renvoyés par le CLI sont en dollars hors taxes : ils
passent par `currency()` (conversion + locale) ou `planPrice()` (prix
d'abonnement, TVA incluse) dans `Sources/AgentBurn/Usage.swift`. Ne jamais
formater un montant à la main.

Deux fichiers de `Tests/` comparent encore des libellés anglais et échoueront
tant qu'ils ne sont pas traduits.

## L'endpoint de quotas Anthropic plafonne vite

`https://api.anthropic.com/api/oauth/usage` renvoie `429` après quelques appels
rapprochés, et la pénalité dure environ une heure. Trois garde-fous en place, à
ne pas défaire :

- un seul appel par processus CLI (`OnceLock` dans
  `rust/crates/agent-burn/src/adapter/claude/limits.rs`) — plusieurs endroits du
  code demandent ces limites pendant un même `summary --value`
- relevé de fond toutes les 10 min (`StartInterval` dans
  `Config/dev.melvynx.agent-burn.quota.plist`)
- rafraîchissement de l'app à 15 min par défaut

En cas de `429`, rien n'est perdu : l'historique déjà relevé reste affiché.

## Rebuild et service de relevé

`./build.sh` re-signe l'app en ad-hoc. Si le service launchd pointe sur une
copie à l'ancienne signature, macOS le tue avec
`SIGKILL (Code Signature Invalid)` et l'historique des quotas cesse de se
remplir en silence. Travailler sur la copie installée dans `/Applications`
évite ce cycle.

## Ne jamais écrire dans le trousseau

L'`accessToken` de Claude Code ne vit que 8 h, le `refreshToken` un mois. Le
bouton « Renouveler la session » échange le second contre un neuf via
`https://platform.claude.com/v1/oauth/token`, avec un `User-Agent`
`claude-code/…` : Cloudflare renvoie 429 à tout agent inconnu, et
`console.anthropic.com` renvoie 404 depuis la migration.

Le jeton renouvelé est écrit dans
`~/Library/Application Support/Agent Burn/claude-session.json`, jamais dans le
trousseau : réécrire l'entrée `Claude Code-credentials` efface sa liste de
contrôle d'accès et macOS redemande le mot de passe à chaque lecture. Ordre de
lecture côté CLI : ce fichier s'il est valide, puis le trousseau, puis
`~/.claude/.credentials.json`.

Anthropic n'inclut un `refresh_token` dans sa réponse que s'il l'a fait
tourner : son absence ne veut pas dire « plus de jeton », il faut conserver
l'ancien.
