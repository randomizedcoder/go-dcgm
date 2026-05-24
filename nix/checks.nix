{
  pkgs,
  src,
  goDcgmPkg,
}:

let
  goPkg = pkgs.go_1_26 or pkgs.go;

  goEnv = ''
    export HOME=$TMPDIR
    export CGO_ENABLED=1
    export GOCACHE=$TMPDIR/go-cache
    export GOLANGCI_LINT_CACHE=$TMPDIR/golangci-cache
    mkdir -p "$GOCACHE" "$GOLANGCI_LINT_CACHE"
  '';

  withVendor = ''
    cp -r $src go-dcgm-src
    chmod -R u+w go-dcgm-src
    cd go-dcgm-src
    cp -r --no-preserve=mode,ownership ${goDcgmPkg.goModules}/ vendor
  '';

  mkGolangciCheck =
    { name, config }:
    pkgs.runCommand "go-dcgm-${name}"
      {
        nativeBuildInputs = [
          goPkg
          pkgs.golangci-lint
          pkgs.cacert
          pkgs.gcc
        ];
        inherit src;
      }
      ''
        ${withVendor}
        ${goEnv}
        export GOFLAGS="-mod=vendor"
        golangci-lint run --config ${config} --timeout 30m ./...
        touch $out
      '';

  go-vet =
    pkgs.runCommand "go-dcgm-go-vet"
      {
        nativeBuildInputs = [
          goPkg
          pkgs.cacert
          pkgs.gcc
        ];
        inherit src;
      }
      ''
        ${withVendor}
        ${goEnv}
        export GOFLAGS="-mod=vendor"
        go vet -v ./...
        touch $out
      '';

  staticcheck =
    pkgs.runCommand "go-dcgm-staticcheck"
      {
        nativeBuildInputs = [
          goPkg
          pkgs.go-tools
          pkgs.cacert
          pkgs.gcc
        ];
        inherit src;
      }
      ''
        ${withVendor}
        ${goEnv}
        export GOFLAGS="-mod=vendor"
        staticcheck ./...
        touch $out
      '';

  # govulncheck needs network access (vuln.go.dev). Ship as an app, not a
  # check. Source mode (./...) — go-dcgm is a library, no binary to scan.
  # Run with: nix run .#govulncheck-go-dcgm
  govulncheck-app = pkgs.writeShellApplication {
    name = "govulncheck-go-dcgm";
    runtimeInputs = [
      goPkg
      pkgs.govulncheck
      pkgs.cacert
      pkgs.gcc
    ];
    text = ''
      set -e
      tmp=$(mktemp -d)
      cp -r ${src}/. "$tmp/"
      chmod -R u+w "$tmp"
      cp -r --no-preserve=mode,ownership ${goDcgmPkg.goModules}/ "$tmp/vendor"
      cd "$tmp"
      export CGO_ENABLED=1
      export GOFLAGS="-mod=vendor"
      echo "=== govulncheck (source mode) against go-dcgm ==="
      exec govulncheck ./...
    '';
  };

  gosec =
    pkgs.runCommand "go-dcgm-gosec"
      {
        nativeBuildInputs = [
          goPkg
          pkgs.gosec
          pkgs.cacert
          pkgs.gcc
        ];
        inherit src;
      }
      ''
        ${withVendor}
        ${goEnv}
        export GOFLAGS="-mod=vendor"
        gosec -exclude=G101,G115,G204,G304,G306,G401,G501 -quiet \
          -exclude-generated ./...
        touch $out
      '';

  nix-fmt =
    pkgs.runCommand "go-dcgm-nix-fmt"
      {
        nativeBuildInputs = [
          pkgs.nixfmt
          pkgs.findutils
        ];
        inherit src;
      }
      ''
        cp -r $src go-dcgm-src
        cd go-dcgm-src
        find . -type f -name '*.nix' | xargs nixfmt --check
        touch $out
      '';

  statix =
    pkgs.runCommand "go-dcgm-statix"
      {
        nativeBuildInputs = [ pkgs.statix ];
        inherit src;
      }
      ''
        cp -r $src go-dcgm-src
        cd go-dcgm-src
        statix check .
        touch $out
      '';

  deadnix =
    pkgs.runCommand "go-dcgm-deadnix"
      {
        nativeBuildInputs = [ pkgs.deadnix ];
        inherit src;
      }
      ''
        cp -r $src go-dcgm-src
        cd go-dcgm-src
        deadnix --fail nix/ flake.nix
        touch $out
      '';

in
{
  golangci-lint-quick = mkGolangciCheck {
    name = "golangci-lint-quick";
    config = ./golangci/golangci-quick.yml;
  };

  golangci-lint = mkGolangciCheck {
    name = "golangci-lint";
    config = ./golangci/golangci.yml;
  };

  golangci-lint-comprehensive = mkGolangciCheck {
    name = "golangci-lint-comprehensive";
    config = ./golangci/golangci-comprehensive.yml;
  };

  inherit
    go-vet
    staticcheck
    gosec
    ;
  inherit
    nix-fmt
    statix
    deadnix
    ;
}
// {
  # not exported under `checks` (network-impure); see flake.nix.
  inherit govulncheck-app;
}
