#!/bin/bash
# Phantasmoon local pet installer. Compatible with macOS Bash 3.2.
set -euo pipefail

APP=auto
TARGET_HOME=
REPOSITORY=
REF=v1.0.0
ASSET_ROOT=
DRY_RUN=0
PET_SHA=431b65abdadc656c0950487ea5107cc86c2b6a079bc686242ae9bc990f2ee8d1
SPRITE_SHA=b95e8cc0fee6649747ba0a7f69bc83cbf5f4691442c4844a5bc7ae93cc747b6a

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'HELP'
Usage: bash install.sh [options]
  --app pro|codex|auto   Target app (auto uses CODEX_HOME, then existing homes)
  --codex-home PATH     Explicit existing app state directory; highest priority
  --repository USER/REPO  GitHub source for online installation
  --ref TAG            Git tag or branch (default: v1.0.0)
  --asset-root PATH    Local folder containing pet.json and spritesheet.png
  --dry-run            Print plan without writing or downloading anything
  --help               Show this help
HELP
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app|--codex-home|--repository|--ref|--asset-root)
            [ "$#" -ge 2 ] && [ -n "$2" ] || die "Missing value for $1"
            case "$1" in
                --app) APP=$2 ;;
                --codex-home) TARGET_HOME=$2 ;;
                --repository) REPOSITORY=$2 ;;
                --ref) REF=$2 ;;
                --asset-root) ASSET_ROOT=$2 ;;
            esac
            shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
done
case "$APP" in pro|codex|auto) ;; *) die '--app must be pro, codex, or auto' ;; esac
[[ "$REF" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 'Invalid --ref'
if [ -n "$REPOSITORY" ]; then
    [[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 'Use --repository USER/REPO'
    [ "$REPOSITORY" != OWNER/REPO ] || die 'Replace OWNER/REPO with the published GitHub repository'
fi
if [ -z "$TARGET_HOME" ]; then
    case "$APP" in
        pro) TARGET_HOME=$HOME/.codex-pro ;;
        codex) TARGET_HOME=$HOME/.codex ;;
        auto)
            if [ -n "${CODEX_HOME:-}" ]; then TARGET_HOME=$CODEX_HOME
            elif [ -d "$HOME/.codex-pro" ]; then TARGET_HOME=$HOME/.codex-pro
            elif [ -d "$HOME/.codex" ]; then TARGET_HOME=$HOME/.codex
            else die 'No app state directory found. Run the desktop app first, or use --codex-home.'
            fi ;;
    esac
fi
[ -d "$TARGET_HOME" ] || die "App state directory does not exist: $TARGET_HOME"
TARGET_HOME=$(cd "$TARGET_HOME" && pwd -P)
TARGET=$TARGET_HOME/pets/phantasmoon
if [ -z "$ASSET_ROOT" ] && [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
    if [ -d "$SCRIPT_DIR/pet/phantasmoon" ]; then ASSET_ROOT=$SCRIPT_DIR/pet/phantasmoon; fi
fi
if [ -n "$ASSET_ROOT" ]; then
    [ -f "$ASSET_ROOT/pet.json" ] && [ -f "$ASSET_ROOT/spritesheet.png" ] || die 'Incomplete local payload'
    SOURCE="local: $ASSET_ROOT"
else
    [ -n "$REPOSITORY" ] || die 'No local payload. Supply --repository USER/REPO for online installation.'
    SOURCE="https://raw.githubusercontent.com/$REPOSITORY/$REF/pet/phantasmoon"
fi
printf 'Phantasmoon 1.0.0 (R17)\nSource: %s\nTarget: %s\n' "$SOURCE" "$TARGET"
[ "$DRY_RUN" -eq 0 ] || { printf 'Dry run: no files changed or downloaded.\n'; exit 0; }

STAGE=
BACKUP=
LOCK=$TARGET_HOME/.phantasmoon-install.lock
LOCK_OWNED=0
cleanup() {
    result=$?
    trap - EXIT
    if [ -n "$BACKUP" ] && [ -d "$BACKUP" ] && [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
        if ! mv "$BACKUP" "$TARGET"; then
            printf 'Recovery needed: previous pet remains at %s\n' "$BACKUP" >&2
            result=1
        fi
    fi
    if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then rm -rf "$STAGE"; fi
    if [ "$LOCK_OWNED" -eq 1 ]; then rmdir "$LOCK" || true; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$LOCK" 2>/dev/null || die "Another installation may be running. Check: $LOCK"
LOCK_OWNED=1
for path in "$TARGET_HOME/pets" "$TARGET" "$TARGET_HOME/pet-backups" "$TARGET_HOME/pet-backups/phantasmoon"; do
    [ ! -L "$path" ] || die "Refusing symbolic link: $path"
    if [ -e "$path" ] && [ ! -d "$path" ]; then die "Expected a directory: $path"; fi
done
STAGE=$(mktemp -d "$TARGET_HOME/.phantasmoon-stage.XXXXXX")
mkdir "$STAGE/payload"
for name in pet.json spritesheet.png; do
    if [ -n "$ASSET_ROOT" ]; then
        cp "$ASSET_ROOT/$name" "$STAGE/payload/$name"
    else
        curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
            --connect-timeout 15 --max-time 180 "$SOURCE/$name" --output "$STAGE/payload/$name"
    fi
done
hash_file() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'; fi
}
[ "$(hash_file "$STAGE/payload/pet.json")" = "$PET_SHA" ] || die 'pet.json checksum mismatch; installation cancelled'
[ "$(hash_file "$STAGE/payload/spritesheet.png")" = "$SPRITE_SHA" ] || die 'spritesheet.png checksum mismatch; installation cancelled'
HEADER=$(od -An -tx1 -N24 "$STAGE/payload/spritesheet.png" | tr -d ' \n')
[ "$HEADER" = 89504e470d0a1a0a0000000d4948445200000600000008f0 ] || die 'Unexpected PNG dimensions or header'
if [ -d "$TARGET" ] && cmp -s "$STAGE/payload/pet.json" "$TARGET/pet.json" && cmp -s "$STAGE/payload/spritesheet.png" "$TARGET/spritesheet.png"; then
    printf 'This version is already installed. No replacement needed.\n'
    exit 0
fi
mkdir -p "$TARGET_HOME/pets"
if [ -d "$TARGET" ]; then
    mkdir -p "$TARGET_HOME/pet-backups/phantasmoon"
    BACKUP=$(mktemp -d "$TARGET_HOME/pet-backups/phantasmoon/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
    rmdir "$BACKUP"
    mv "$TARGET" "$BACKUP"
fi
mv "$STAGE/payload" "$TARGET"
printf 'Installed. Open desktop app Settings > Pets, refresh, and select Phantasmoon.\n'
if [ -n "$BACKUP" ]; then printf 'Previous version backup: %s\n' "$BACKUP"; fi
