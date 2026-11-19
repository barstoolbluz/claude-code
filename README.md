# claude-code

Claude Code from nixpkgs, wrapped with bundled plugins and the tools it reaches
for from its shell.

## What the wrapper adds

- **Plugins** (loaded via `--plugin-dir`, no `~/.claude` install needed):
  - `flox` — the flox, floxify and flox-debug skills, pinned from
    [flox/flox-skills](https://github.com/flox/flox-skills)
  - Language servers, each with its server bundled: `rust-analyzer-lsp`
    (Rust), `nixd-lsp` (Nix), `pyright-lsp` (Python), and `bash-lsp` (shell,
    with shellcheck diagnostics)
- **Tools**, appended to `PATH` so your own copies win:
  - `gh` — routed through the sibling [`ghcli`](../ghcli) flake, so it gets
    ghcli's token management
  - `nixfmt`, `shellcheck`, and the language servers above
- **Flakes** — sets `NIX_CONFIG` to enable `nix-command flakes`, unless
  `NIX_CONFIG` is already set

## Usage

```bash
alias kklaude='~/dev/nix/claude-code/bootstrap.sh --dangerously-skip-permissions'
```

`bootstrap.sh` keeps Claude Code on Anthropic's release channel. On each
launch it checks the channel (~0.1s); when there's a new release it fetches
that release's manifest into `manifest.json`, commits it locally, and rebuilds
into `~/.local/state/claude-code-nix` (which also keeps the build from being
garbage-collected). Offline, it launches the existing build.

Or run it straight from GitHub, at whatever `manifest.json` is committed (the
repo is private, so fetch over SSH rather than `github:`):

```bash
nix run 'git+ssh://git@github.com/barstoolbluz/nix-desktop-userland?dir=claude-code'
```

The unwrapped package is available as `.#claude-code`.

## Versions

The Claude Code version comes from `manifest.json`, not from the nixpkgs pin,
so it isn't held back by nixpkgs' release cycle. `channel` decides what
`bootstrap.sh` tracks:

| `channel` | Tracks |
|-----------|--------|
| `latest` (default) | Anthropic's newest release |
| `stable` | Anthropic's stable channel |
| a version, e.g. `2.1.326` | that release, pinned (also how to roll back) |

The rest still comes from flake inputs; update them occasionally:

```bash
nix flake update            # nixpkgs (package recipe, bundled tools), flox-skills, ghcli
```

## Platforms

`x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.
