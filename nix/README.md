# go-dcgm — Nix Flake Development Environment

A modular Nix flake adapted from [nebula's nix/](https://github.com/randomizedcoder/nebula/tree/nix/nix)
flake. Adds a reproducible build and a pedantic Go static-analysis pipeline
for the go-dcgm library.

go-dcgm is a Go library (no `cmd/*` user binaries — `cmd/gen-fields` is a
codegen tool, and `samples/*` are demo apps) that binds to NVIDIA's
libdcgm.so. The cgo `LDFLAGS` use
`-Wl,--unresolved-symbols=ignore-in-object-files`, and the DCGM C headers
are vendored under `pkg/dcgm/dcgm_*.h`, so cgo compiles and lints in a
clean nix sandbox without libdcgm or NVIDIA system packages present.

## Quick Start

```sh
nix develop                                 # enter dev shell
nix build .#go-dcgm                         # build the library
nix flake check -L                          # run every check
nix run .#govulncheck-go-dcgm               # source-mode CVE scan (network)
```

## Static Analysis

Three tiers; the repo's existing `.golangci.yml` is left untouched.

| Tier | Attr | Runtime | Linters |
|---|---|---|---|
| 0 quick | `golangci-lint-quick` | ~30 s | gofmt, goimports, govet, errcheck, ineffassign, staticcheck, unused, copyloopvar, intrange |
| 1 standard | `golangci-lint` | ~2 min | tier 0 + gosec, gocritic, revive, contextcheck, sloglint, testifylint, unconvert, unparam, wastedassign, nilerr, perfsprint |
| 2 comprehensive | `golangci-lint-comprehensive` | ~10 min | tier 1 + exhaustive, prealloc, gocyclo, funlen, goconst, dupl, bodyclose, errorlint, misspell, nakedret, nestif, noctx, rowserrcheck, sqlclosecheck, whitespace |

Standalone checks:

- `go-vet` — `go vet -v ./...`
- `staticcheck` — Dominik Honnef's checker
- `gosec` — security scanner (`-exclude-generated`)
- `nix-fmt` / `statix` / `deadnix` — Nix-side hygiene
- `govulncheck-go-dcgm` (app, not check) — source-mode CVE scan against `./...`

## Generated code exclusions

`nix/golangci/*.yml` excludes the codegen output:

- `pkg/dcgm/const_fields.go` (139 KB, emitted by `cmd/gen-fields` from
  `pkg/dcgm/dcgm_fields.h`; no `Code generated` header so `lax`
  auto-detection misses it — explicit path exclusion required)

## File map

```
flake.nix                       # inputs + eachSystem wiring
nix/
  README.md                     # this file
  constants.nix                 # version, ldflags, go toolchain pin
  shell.nix                     # dev shell
  checks.nix                    # tiered static analysis + standalone checks
  golangci/
    golangci-quick.yml          # tier 0
    golangci.yml                # tier 1
    golangci-comprehensive.yml  # tier 2
  packages/
    default.nix
    library.nix                 # buildGoModule (only .goModules is consumed)
  apps/
    default.nix                 # govulncheck app
  static-analysis-report.md     # baseline run report
```
