#!/usr/bin/env bash
# Launch Claude Code via Nix, tracking Anthropic's release channel.
# On each launch, checks the channel named in ./channel ("latest", "stable",
# or a pinned version like "2.1.326"); if it differs from ./manifest.json,
# fetches the new manifest, commits it locally, and rebuilds. Offline or on
# failure, launches the existing build.
# Prerequisites: Nix with flakes enabled, curl, git.
set -uo pipefail

dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
state="${CLAUDE_CODE_NIX_STATE:-$HOME/.local/state/claude-code-nix}"
releases="https://downloads.claude.ai/claude-code-releases"

log() { printf 'claude-code: %s\n' "$*" >&2; }
manifest_version() { sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$1" | head -n1; }
# Drop Nix noise: dirty-tree warnings, and the multi-line warning (indented
# continuation lines follow it) for an unreachable cachix substituter.
filter_nix_noise() {
  awk '
    /^warning: Git tree .* is dirty/ { next }
    /^warning: unable to download .https:\/\/[^ ]*\.cachix\.org\/nix-cache-info/ { skip = 1; next }
    skip && (/^$/ || /^[ \t]/) { next }
    { skip = 0; print; fflush() }
  '
}

channel="$(tr -d '[:space:]' < "$dir/channel" 2>/dev/null)"
channel="${channel:-latest}"
case "$channel" in
  latest | stable) target="$(curl -fsS -m 3 "$releases/$channel" 2>/dev/null)" ;;
  *) target="$channel" ;;
esac

current="$(manifest_version "$dir/manifest.json")"
if [[ "$target" =~ ^[0-9]+(\.[0-9]+)+$ && "$target" != "$current" ]]; then
  log "updating $current -> $target"
  tmp="$(mktemp)"
  if curl -fsS -m 30 "$releases/$target/manifest.zst.json" -o "$tmp" &&
    [[ "$(manifest_version "$tmp")" == "$target" ]]; then
    mv "$tmp" "$dir/manifest.json"
    git -C "$dir" commit -q -m "claude-code: $current -> $target" -- manifest.json \
      >/dev/null 2>&1 || log "note: manifest.json updated but not committed"
  else
    rm -f "$tmp"
    log "could not fetch manifest for $target; keeping $current"
  fi
fi

wanted="$(manifest_version "$dir/manifest.json")"
built="$(readlink -f "$state" 2>/dev/null)"
built="${built##*-}"
if [[ "$built" != "$wanted" ]]; then
  log "building $wanted"
  if ! nix --extra-experimental-features "nix-command flakes" \
    build "$dir" -o "$state" 2> >(filter_nix_noise >&2); then
    [[ -x "$state/bin/claude" ]] || exit 1
    log "build failed; launching existing build"
  fi
fi

exec "$state/bin/claude" "$@"
