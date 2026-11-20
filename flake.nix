{
  description = "Claude Code, built from nixpkgs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flox-skills = {
      url = "github:flox/flox-skills";
      flake = false;
    };
    # Keeps its own nixpkgs pin.
    ghcli.url = "github:barstoolbluz/ghcli";
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

      # claude-code from nixpkgs, at the release in ./manifest.json (Anthropic's
      # manifest.zst.json; bootstrap.sh keeps it on ./channel) rather than
      # whichever release this nixpkgs pin ships.
      mkClaudeCode = pkgs: pkgs.claude-code.override { manifest = pkgs.lib.importJSON ./manifest.json; };

      # Language servers, each bundled as a plugin plus its server on PATH. The
      # rust-analyzer and pyright configs mirror claude-plugins-official's
      # marketplace entries (which hold the LSP config, so those plugins can't be
      # loaded via --plugin-dir); nixd and bash have no official plugin.
      mkLspServers = pkgs: [
        {
          plugin = "rust-analyzer-lsp";
          description = "Rust language server for code intelligence and analysis";
          package = pkgs.rust-analyzer;
          servers.rust-analyzer = {
            command = "rust-analyzer";
            extensionToLanguage.".rs" = "rust";
          };
        }
        {
          plugin = "nixd-lsp";
          description = "Nix language server (nixd) for code intelligence";
          package = pkgs.nixd;
          servers.nixd = {
            command = "nixd";
            extensionToLanguage.".nix" = "nix";
          };
        }
        {
          plugin = "pyright-lsp";
          description = "Python language server (Pyright) for type checking and code intelligence";
          package = pkgs.pyright;
          servers.pyright = {
            command = "pyright-langserver";
            args = [ "--stdio" ];
            extensionToLanguage = {
              ".py" = "python";
              ".pyi" = "python";
            };
          };
        }
        {
          plugin = "bash-lsp";
          description = "Bash language server for code intelligence, with shellcheck diagnostics";
          package = pkgs.bash-language-server;
          servers.bash = {
            command = "bash-language-server";
            args = [ "start" ];
            extensionToLanguage = {
              ".sh" = "shellscript";
              ".bash" = "shellscript";
            };
          };
        }
      ];

      mkLspPlugin =
        pkgs: lsp:
        pkgs.writeTextFile {
          name = "${lsp.plugin}-plugin";
          destination = "/.claude-plugin/plugin.json";
          text = builtins.toJSON {
            name = lsp.plugin;
            version = "1.0.0";
            inherit (lsp) description;
            lspServers = lsp.servers;
          };
        };

      # Plugin directories passed to claude via --plugin-dir.
      mkPlugins =
        pkgs: [ "${flox-skills}/flox-plugin" ] ++ map (lsp: "${mkLspPlugin pkgs lsp}") (mkLspServers pkgs);

      # `gh` for claude's shell commands, routed through the ghcli flake
      # (and its token management).
      mkGhShim =
        pkgs:
        pkgs.writeShellScriptBin "gh" ''
          exec ${ghcli.apps.${pkgs.stdenv.hostPlatform.system}.default.program} -c 'command gh "$@"' _ "$@"
        '';

      # Tools for claude's shell commands. Suffixed onto PATH so the user's own
      # copies (e.g. a rustup-managed rust-analyzer) win.
      mkTools =
        pkgs:
        [
          (mkGhShim pkgs)
          pkgs.nixfmt
          pkgs.shellcheck
        ]
        ++ map (lsp: lsp.package) (mkLspServers pkgs);

      mkClaudeCodeWithPlugins =
        pkgs:
        let
          claude-code = mkClaudeCode pkgs;
        in
        pkgs.symlinkJoin {
          name = "claude-code-with-plugins-${claude-code.version}";
          paths = [ claude-code ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/claude \
              --set-default NIX_CONFIG 'extra-experimental-features = nix-command flakes' \
              --suffix PATH : ${pkgs.lib.makeBinPath (mkTools pkgs)} \
              ${pkgs.lib.concatMapStringsSep " " (p: "--add-flags '--plugin-dir ${p}'") (mkPlugins pkgs)}
          '';
          inherit (claude-code) meta;
        };
    in
    {
      packages = forAllSystems (pkgs: rec {
        claude-code = mkClaudeCode pkgs;
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
