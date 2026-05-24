# findings: gosec HIGH — 5 sites across samples + codegen

Five gosec **HIGH severity** findings surfaced. Two are template-injection
sites in the sample REST API; three are path-traversal sites in the
build-time codegen tool. None are in the library package `pkg/dcgm/`
itself.

## G708 — Server-side template injection (2 sites)

`samples/restApi/handlers/utils.go`

```go
// line 178-179
func printer(resp http.ResponseWriter, req *http.Request, stats any, templ string) {
    t := template.Must(template.New("").Parse(templ))        // ← G708
    ...
}

// line 198-199
func processPrint(resp http.ResponseWriter, req *http.Request, pInfo []dcgm.ProcessInfo) {
    t := template.Must(template.New("Process").Parse(processInfo))  // ← G708
    ...
}
```

**Why gosec flagged it**: `html/template`/`text/template` execution with
attacker-controlled template strings is code execution (the template DSL
includes Go expressions). gosec performs taint analysis along the call
graph and flags any `template.Parse` whose argument originates from a
function parameter or external source.

**Actual risk in this codebase**:
- Line 199: `processInfo` is a package-level constant string. **Static, safe.**
- Line 179: `templ` is a function parameter. Every caller in
  `samples/restApi/handlers/` passes a package-level constant
  (`gpuInfoTemplate`, `groupInfoTemplate`, etc.) — none of them is reachable
  from HTTP input today. **Currently safe.**

**Why this still matters**: `samples/restApi/` is *labeled* as sample code.
Sample code is the most-copied code in any repo. A reader who reuses
`printer(... templ string)` in production, and ends up wiring an HTTP form
field into `templ`, gets remote code execution. The taint analyser is
warning about precisely that fragility.

**Recommended remediation**:

1. **Tighten `printer`'s signature** so it cannot accept arbitrary
   template text:

   ```go
   // Before
   func printer(resp http.ResponseWriter, req *http.Request, stats any, templ string) { ... }

   // After
   func printer(resp http.ResponseWriter, req *http.Request, stats any, templ *template.Template) { ... }
   ```

   Parse the template once at init time (or in a `var = template.Must(...)`
   block) so a misuse can't introduce a tainted source later. This is the
   structural fix and the one I would land.

2. **Annotate** with a justification comment:

   ```go
   //nolint:gosec // G708: templ is always a package-level constant; see
   //               callers in handlers/{cpu,gpu,...}.go. Tighten signature
   //               before production use.
   t := template.Must(template.New("").Parse(templ))
   ```

   Cheap; survives future taint-analysis upgrades only if reviewers
   maintain the invariant. Less safe than option 1.

## G703 — Path traversal in codegen tool (3 sites)

`cmd/gen-fields/main.go`

```go
// line 108-109
func parseHeader(path string) ([]Field, map[string]string, error) {
    file, err := os.Open(path)                       // ← G703
    ...
}

// line 319-320
func extractLegacyFields(path string) (map[string]int, error) {
    file, err := os.Open(path)                       // ← G703
    ...
}

// line 391-392
func generateOutput(data TemplateData, outputPath string) error {
    ...
    file, err := os.Create(outputPath)               // ← G703
    ...
}
```

**Threat model**: `cmd/gen-fields` is invoked from `make generate`
(`pkg/dcgm/fields.go:go:generate`) with hard-coded paths
(`../../cmd/gen-fields/template.go`, `dcgm_fields.h`, `const_fields.go`).
Whoever runs `make generate` already has full write access to the source
tree, so a TOCTOU attack here adds zero attack surface beyond what they
already have.

**Recommended remediation**:

Annotate with a justification, no behavior change needed:

```go
//nolint:gosec // G703: dev-time codegen tool; paths come from controlled
//               `go:generate` directive in pkg/dcgm/fields.go.
file, err := os.Open(path)
```

Alternative: lift the paths into compile-time constants inside `main.go`
and rewrite the signatures to take no arguments. Cleanest but more
intrusive. Recommended if you also want to eliminate the
`unparam`/argument-noise findings in the same file.

## Why we don't auto-fix in this baseline

The plan scoped this round to "produce baseline, document HIGH and
real-bug findings". Each of these is a small targeted change. The G708
restructure to `*template.Template` argument types is the most valuable
landing — it's a real defense-in-depth improvement and a 5-minute PR
against `samples/restApi/handlers/`. The G703 sites are policy/annotation
work and can land together.
