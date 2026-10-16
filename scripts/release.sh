#!/bin/bash
# Gera uma release: grava a versão no pubspec.yaml (build +1), commita e envia o main e a tag
# v<versão>. O .github/workflows/release.yml builda e publica o DMG e o instalador a partir da tag.
# Uso: scripts/release.sh 0.2.0   (com hífen, ex. 0.2.0-beta, sai como pré-release)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?Uso: scripts/release.sh <versão, ex. 0.2.0>}
fail() { echo "$1" >&2; exit 1; }
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || fail "Versão inválida: $VERSION"
[[ $(git branch --show-current) == main ]] || fail "Rode no main."
[[ -z $(git status --porcelain) ]] || fail "Há alterações não commitadas. Commite antes."
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "A tag v$VERSION já existe."

git pull --ff-only origin main
BUILD=$(($(sed -n 's/^version: .*+\([0-9]*\)$/\1/p' pubspec.yaml) + 1))
sed -i.bak "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml && rm pubspec.yaml.bak

git commit -qam "chore: release v$VERSION"
git tag "v$VERSION"
git push origin main "v$VERSION"
echo "Release v$VERSION enviada. Build: https://github.com/CristenSoftwareDevelopment/redmine-adapter/actions"
