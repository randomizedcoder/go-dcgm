# go-dcgm Static Analysis Baseline Report

A baseline snapshot of every check the nix flake exposes, run against the
fresh `nix` branch with no prior cleanup. Security and critical
correctness findings first.

## Run metadata

| Field | Value |
|---|---|
| Date (UTC) | 2026-05-24 |
| Branch | `nix` |
| Repo | `randomizedcoder/go-dcgm` (fork of `NVIDIA/go-dcgm`) |
| Base of `nix` | tip of `main` (working tree clean before branch) |
| Working tree | dirty (this branch's flake files + this report) |
| Go toolchain | `go1.26.3 linux/amd64` (from `pkgs.go_1_26`) |
| `go.mod` declares | `go 1.23` |
| nixpkgs lock | `2991645341…` (nixos-unstable, 2026-05-23) |
| golangci-lint | 2.12.2 |
| staticcheck | 2026.1 (v0.7.0) |
| gosec | 2.26.1 |
| govulncheck | 1.3.0, DB `https://vuln.go.dev` |

Reproduction:

```sh
for c in nix-fmt statix deadnix go-vet staticcheck gosec \
         golangci-lint-quick golangci-lint golangci-lint-comprehensive; do
  nix build -L .#checks.x86_64-linux.$c
done
nix run .#govulncheck-go-dcgm
```

## Executive summary

| Check | Status | Issues | Wall-clock |
|---|---|---|---|
| `nix-fmt` | PASS | 0 | 2 s |
| `statix` | PASS | 0 | 1 s |
| `deadnix` | PASS | 0 | 1 s |
| `go-vet` | PASS | 0 | 8 s |
| `staticcheck` (standalone) | PASS | 0 | 12 s |
| `gosec` | FAIL | **20** (5 HIGH, 0 MED, 15 LOW) | 26 s |
| `govulncheck-go-dcgm` (source mode) | PASS | 0 | ~25 s |
| `golangci-lint-quick` (Tier 0) | FAIL | 54 | 12 s |
| `golangci-lint` (Tier 1) | FAIL | 30 | 12 s |
| `golangci-lint-comprehensive` (Tier 2) | FAIL | 137 | 13 s |

All Nix-side checks (`nix-fmt`, `statix`, `deadnix`), `go-vet`, standalone
`staticcheck`, and `govulncheck` pass. Findings concentrate around two
hot spots: the sample REST API (`samples/restApi/handlers/`) and the
build-time codegen tool (`cmd/gen-fields/main.go`). The library itself
(`pkg/dcgm/`) is mostly clean.

## Triage recommendation

1. **`gosec` G708 HIGH (2) — server-side template injection in
   `samples/restApi/handlers/utils.go:179,199`.** A Go `html/template` is
   parsed from a parameter passed by callers (`templ string`). If any
   caller ever passes user-controlled input, this is RCE. Today all callers
   pass package-level constants, so it is theoretically safe — but the
   *sample* is intended to be copy-pasted, and the next reader will not
   re-audit the chain. See
   [`findings-gosec-high.md`](./findings-gosec-high.md).

2. **`gosec` G703 HIGH (3) — path traversal in `cmd/gen-fields/main.go`.**
   `os.Open`/`os.Create` on caller-supplied paths inside the build-time
   codegen tool. Threat model is trusted developer environment, so the
   practical risk is low; annotate with `//nolint:gosec` and a rationale,
   or migrate to `os.Root`. See
   [`findings-gosec-high.md`](./findings-gosec-high.md).

3. **`gosec` G706 LOW (15) — log injection in `samples/restApi/handlers/`.**
   User-controlled fields (`req.Host`, `req.URL`) are concatenated into
   `log.Printf` format arguments. Lets an attacker forge log lines
   (newlines into log files), which can confuse aggregators. Sample code
   only; either sanitize before logging or annotate.

4. **`staticcheck` ST1003 (50 in Tier 0)** — all naming-convention
   violations on the public surface (`_v2` suffixes, `Id` vs `ID`).
   Breaking change to rename; defer.

5. **Mechanical tier-1 cleanup (29 non-gosec)** —
   `testifylint` (6), `revive` (5), `perfsprint` (5), `intrange` (3),
   `gocritic` (1), `unparam` (1), `gofmt` (1). Mostly in samples; safe
   to land as a small follow-up PR if you want a clean tier-1 baseline.

## Detailed findings

### gosec — 20 issues (5 HIGH, 15 LOW)

```
HIGH:
  samples/restApi/handlers/utils.go:199    G708 Template injection (Confidence: HIGH)
  samples/restApi/handlers/utils.go:179    G708 Template injection (Confidence: HIGH)
  cmd/gen-fields/main.go:392               G703 Path traversal      (Confidence: HIGH)
  cmd/gen-fields/main.go:320               G703 Path traversal      (Confidence: HIGH)
  cmd/gen-fields/main.go:109               G703 Path traversal      (Confidence: HIGH)

LOW:
  samples/restApi/handlers/utils.go:104,116,130,137,151,164,181,191,201  G706 (9 sites)
  samples/restApi/handlers/dcgm.go:18,50,86,118,137,149                  G706 (6 sites)
```

Excludes inherited from nebula's baseline: `-exclude=G101,G115,G204,G304,G306,G401,G501 -exclude-generated`.

The library package `pkg/dcgm/` is clean — every finding is in samples or
the codegen tool.

### golangci-lint tier 0 — quick (54 issues)

| Linter | Issues |
|---|---:|
| `staticcheck` | 50 (all `ST1003` naming) |
| `intrange` | 3 |
| `gofmt` | 1 |

The 50 `ST1003` findings are spread across `pkg/dcgm/{dcgm,device_info,fields,policy,structs,utils,…}.go` and reflect c-API mirroring: identifiers like `Type_v2`, `Id`, `numFbcSessions` were chosen for symmetry with the upstream DCGM C structs.

### golangci-lint tier 1 — standard (30 issues)

| Linter | Issues |
|---|---:|
| `gosec` | 8 (G703×3, G706×3, G708×2 — capped by `max-same-issues`) |
| `testifylint` | 6 |
| `perfsprint` | 5 |
| `revive` | 5 |
| `intrange` | 3 |
| `gocritic` | 1 |
| `unparam` | 1 |
| `gofmt` | 1 |

Note: golangci-lint's default `max-same-issues: 3` truncates the 15-site
G706 output to 3. Standalone `gosec` reports all 15.

### golangci-lint tier 2 — comprehensive (137 issues)

Adds tech-debt linters. New in tier 2:

| Linter | Issues |
|---|---:|
| `revive` (severity-warning rules) | 50 |
| `goconst` | 36 |
| `nakedret` | 15 |
| `noctx` | 6 |
| `exhaustive` | 6 |
| `errorlint` | 3 |
| `prealloc` | 1 |
| `gocyclo` | 1 |
| `funlen` | 1 |

### staticcheck (standalone) — 0 issues

Same observation as go-nvml: standalone `staticcheck` defaults to
SA/S rules and finds nothing. The 50 `ST1003` findings appear only via
golangci-lint's staticcheck integration, which enables the `ST*` style
rules.

### govulncheck source-mode — 0 vulnerabilities

go-dcgm's transitive dep graph is small (`gorilla/mux`,
`bits-and-blooms/bitset`, `stretchr/testify`, `davecgh/go-spew`,
`pmezard/go-difflib`, `yaml.v3`). No reachable CVEs.

### go-vet — clean

All packages including `pkg/dcgm`, `cmd/gen-fields`, `tests`, and all 9
`samples/`.

### nix-fmt / statix / deadnix — clean

The flake's own `.nix` files pass all three nix-side linters.

## Generated-code exclusions

The flake's `nix/golangci/*.yml` configs explicitly exclude:

- `pkg/dcgm/const_fields.go` (2,043 lines emitted by `cmd/gen-fields` from
  `pkg/dcgm/dcgm_fields.h`; no `Code generated` header, so the `lax`
  auto-detector misses it without an explicit path entry)

The repo's existing `.golangci.yml` is left untouched.

## Upstream submission status (as of 2026-05-24)

The triage above has begun landing as upstream PRs. Counts in the executive summary remain pinned to the 2026-05-24 baseline; this section tracks what has moved against that snapshot.

### Open

| PR | Title | Findings closed |
|---|---|---|
| [NVIDIA/go-dcgm#124](https://github.com/NVIDIA/go-dcgm/pull/124) | samples/restApi: pre-parse templates (gosec G708 hardening) | 2 × `gosec` G708 HIGH (`samples/restApi/handlers/utils.go:179, 199`) |
| [NVIDIA/go-dcgm#125](https://github.com/NVIDIA/go-dcgm/pull/125) | samples/restApi: sanitize caller-controlled log fields (G706) | 15 × `gosec` G706 LOW (9 in `samples/restApi/handlers/utils.go`, 6 in `samples/restApi/handlers/dcgm.go`) |
| [NVIDIA/go-dcgm#126](https://github.com/NVIDIA/go-dcgm/pull/126) | samples/restApi: buffer template render before flushing to response | partial-write wart documented in #124's test file (`printer()` silently committed HTTP 200 before template-render failures could set 500); depends on #124 |

### Cumulative coverage against the 2026-05-24 baseline

- **`gosec` HIGH (G708)**: 2 of 5 covered by #124 (open). Remaining 3 (G703 in `cmd/gen-fields/main.go`) untouched.
- **`gosec` LOW (G706)**: 15 of 15 covered by #125 (open).
- **partial-write wart** (out-of-scope of #124, documented in its tests): closed by #126 (open, depends on #124).
- **`gosec` G703 HIGH (3)**, **ST1003 (50)**, **tier-2 tech debt (revive 50, goconst 36, nakedret 15, …)** — untouched.

## Repro one-liner

```sh
# All checks in parallel (mostly cached after first run)
nix flake check -L

# Or one at a time
nix build -L .#checks.x86_64-linux.golangci-lint-quick           # 54 issues
nix build -L .#checks.x86_64-linux.golangci-lint                 # 30 issues
nix build -L .#checks.x86_64-linux.golangci-lint-comprehensive   # 137 issues
nix build -L .#checks.x86_64-linux.staticcheck                   # 0
nix build -L .#checks.x86_64-linux.gosec                         # 20 issues
nix run .#govulncheck-go-dcgm                                    # 0 CVEs
```
