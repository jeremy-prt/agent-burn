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
remplir en silence. Après remplacement de l'app, il faut en général
`launchctl kickstart` du service, puis quitter l'app, `launchctl bootout`, et
la relancer pour que macOS accepte la nouvelle signature.

## Trousseau : toujours via `/usr/bin/security`

L'`accessToken` de Claude Code ne vit que 8 h, le `refreshToken` un mois. Le
renouvellement passe par `https://platform.claude.com/v1/oauth/token`, avec un
`User-Agent` `claude-code/…` : Cloudflare renvoie 429 à tout agent inconnu, et
`console.anthropic.com` renvoie 404 depuis la migration.

Lire et écrire l'entrée `Claude Code-credentials` uniquement via
`/usr/bin/security`, jamais via `SecItem*` : l'entrée n'accepte que la
partition `apple-tool:`, et une app signée ad-hoc déclenche une demande de mot
de passe à chaque accès. Pas de `security -i` non plus : il coupe les lignes
vers 4 Ko et a déjà tronqué l'entrée.

Anthropic fait tourner le `refreshToken` à chaque échange : le jeton renouvelé
doit revenir dans le trousseau, sinon Claude Code garde un jeton mort et exige
`claude /login`. Une réponse sans `refresh_token` veut dire « garder l'ancien ».
