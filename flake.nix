{
  description = "Claude Code, built from nixpkgs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flox-skills = {
      url = "github:flox/flox-skills";
      flake = false;
    };
    # Sibling flake in this repo; keeps its own nixpkgs pin.
    ghcli.url = "path:../ghcli";
  };

  outputs =
    {
      self,
      nixpkgs,
      flox-skills,
      ghcli,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              # claude-code is licensed unfree; allow just it and our wrapper.
              config.allowUnfreePredicate =
                pkg:
                builtins.elem (nixpkgs.lib.getName pkg) [
                  "claude-code"
                  "claude-code-with-plugins"
                ];
            }
          )
        );

      # Equivalent of rust-analyzer-lsp@claude-plugins-official, whose LSP config
      # lives in its marketplace entry rather than its plugin directory.
      mkRustAnalyzerPlugin =
        pkgs:
        pkgs.writeTextFile {
          name = "rust-analyzer-lsp-plugin";
          destination = "/.claude-plugin/plugin.json";
          text = builtins.toJSON {
            name = "rust-analyzer-lsp";
            version = "1.0.0";
            description = "Rust language server for code intelligence and analysis";
            lspServers.rust-analyzer = {
              command = "rust-analyzer";
              extensionToLanguage.".rs" = "rust";
            };
          };
        };

      # Plugin directories passed to claude via --plugin-dir.
      mkPlugins = pkgs: [
        "${flox-skills}/flox-plugin"
        "${mkRustAnalyzerPlugin pkgs}"
      ];

      # `gh` for claude's shell commands, routed through the sibling ghcli flake
      # (and its token management).
      mkGhShim =
        pkgs:
        pkgs.writeShellScriptBin "gh" ''
          exec ${ghcli.apps.${pkgs.stdenv.hostPlatform.system}.default.program} -c 'command gh "$@"' _ "$@"
        '';

      # Tools for claude's shell commands. Suffixed onto PATH so the user's own
      # copies (e.g. a rustup-managed rust-analyzer) win.
      mkTools = pkgs: [
        (mkGhShim pkgs)
        pkgs.nixfmt
        pkgs.shellcheck
        pkgs.rust-analyzer
      ];

      mkClaudeCodeWithPlugins =
        pkgs:
        pkgs.symlinkJoin {
          name = "claude-code-with-plugins-${pkgs.claude-code.version}";
          paths = [ pkgs.claude-code ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/claude \
              --set-default NIX_CONFIG 'extra-experimental-features = nix-command flakes' \
              --suffix PATH : ${pkgs.lib.makeBinPath (mkTools pkgs)} \
              ${pkgs.lib.concatMapStringsSep " " (p: "--add-flags '--plugin-dir ${p}'") (mkPlugins pkgs)}
          '';
          inherit (pkgs.claude-code) meta;
        };
    in
    {
      packages = forAllSystems (pkgs: rec {
        claude-code = pkgs.claude-code;
        claude-code-with-plugins = mkClaudeCodeWithPlugins pkgs;
        default = claude-code-with-plugins;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/claude";
          meta.description = "Run Claude Code with bundled plugins";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ]; };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
