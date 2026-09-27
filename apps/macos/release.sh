#!/bin/bash
# Publie un DMG universel sur le dépôt `origin`. Sans AGENT_BURN_SIGN_IDENTITY,
# l'app est signée ad-hoc : macOS demandera « Ouvrir quand même » au premier lancement.
set -euo pipefail
cd "$(dirname "$0")"
version="$(tr -d '\n' < Config/version)"
tag="macos-v$version"
repo="$(git remote get-url origin | sed -E 's#^git@github\.com(-[a-z]+)?:##; s#^https://github\.com/##; s#\.git$##')"
commit="$(git rev-parse HEAD)"
branch="$(git branch --show-current)"
if [[ "$(git ls-remote origin "refs/heads/$branch" | cut -f1)" != "$commit" ]]; then
  echo "Push the release commit before publishing." >&2; exit 1
fi
if ! git diff --quiet HEAD -- . ../../rust; then echo "Commit app and CLI changes first." >&2; exit 1; fi
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then echo "$tag already exists" >&2; exit 1; fi
command -v create-dmg >/dev/null || { echo "brew install create-dmg" >&2; exit 1; }
rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null

./build.sh --release
dmg="dist/Agent-Burn-$version.dmg"
rm -f "$dmg"
create-dmg --volname "Agent Burn" --window-size 600 400 --icon-size 128 \
  --icon "Agent Burn.app" 150 200 --app-drop-link 450 200 --hide-extension "Agent Burn.app" \
  --no-internet-enable "$dmg" "dist/Agent Burn.app"
hdiutil verify "$dmg"

gh release create "$tag" "$dmg" --repo "$repo" --target "$commit" --title "Agent Burn $version" --notes "$(cat <<NOTES
Ouvrir le DMG et glisser **Agent Burn** dans Applications.

L'app n'est pas notarisée : au premier lancement, Réglages Système → Confidentialité et sécurité → **Ouvrir quand même**. Puis \`claude /login\` une fois dans un terminal.

Universel (Apple Silicon et Intel), macOS 14 ou plus.
NOTES
)"
echo "Published https://github.com/$repo/releases/tag/$tag"
