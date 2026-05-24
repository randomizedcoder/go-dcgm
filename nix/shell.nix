{ pkgs }:

let
  goPkg = pkgs.go_1_26 or pkgs.go;
in
pkgs.mkShell {
  name = "go-dcgm-dev";

  packages = [
    goPkg
    pkgs.gopls
    pkgs.gotools
    pkgs.delve
    pkgs.golangci-lint
    pkgs.gosec
    pkgs.govulncheck
    pkgs.go-tools

    pkgs.nixfmt
    pkgs.statix
    pkgs.deadnix

    pkgs.gnumake
    pkgs.jq
    pkgs.git
  ];

  env = {
    CGO_ENABLED = "1";
    GOTOOLCHAIN = "local";
  };

  shellHook = ''
    echo "go-dcgm dev shell"
    echo "  go:            $(go version)"
    echo "  golangci-lint: $(golangci-lint version --short 2>/dev/null || golangci-lint --version)"
    echo ""
    echo "Common commands:"
    echo "  nix flake check                    run all checks (linters)"
    echo "  nix run .#govulncheck-go-dcgm      run govulncheck (network)"
  '';
}
