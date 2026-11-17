# claude-code

Claude Code from nixpkgs, wrapped with bundled plugins and the tools it reaches
for from its shell.

## What the wrapper adds

- **Plugins** (loaded via `--plugin-dir`, no `~/.claude` install needed):
  - `flox` — the flox, floxify and flox-debug skills, pinned from
    [flox/flox-skills](https://github.com/flox/flox-skills)
  - `rust-analyzer-lsp` — Rust code intelligence
- **Tools**, appended to `PATH` so your own copies win:
  - `gh` — routed through the sibling [`ghcli`](../ghcli) flake, so it gets
    ghcli's token management
  - `nixfmt`, `shellcheck`, `rust-analyzer`
- **Flakes** — sets `NIX_CONFIG` to enable `nix-command flakes`, unless
  `NIX_CONFIG` is already set

## Usage

Run it directly (the repo is private, so fetch over SSH rather than `github:`):

```bash
nix run 'git+ssh://git@github.com/barstoolbluz/nix-desktop-userland?dir=claude-code'
```

Or build once and alias the result, which skips flake evaluation on launch and
keeps the build from being garbage-collected:

```bash
nix build ~/dev/nix/claude-code -o ~/.local/state/claude-code-nix
alias kklaude='~/.local/state/claude-code-nix/bin/claude --dangerously-skip-permissions'
```

The unwrapped package is available as `.#claude-code`.

## Updating

```bash
nix flake update            # claude-code, flox-skills, and ghcli
nix flake update nixpkgs    # just claude-code
```

Re-run `nix build` afterwards if you use the alias.

## Platforms

`x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.
