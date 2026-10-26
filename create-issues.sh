#!/usr/bin/env bash
# create-issues.sh — Populate GitHub issues for the vitals project.
#
# Usage:
#   ./create-issues.sh             # create all issues
#   ./create-issues.sh --dry-run   # preview without creating
#
# Requires:
#   - gh CLI installed and authenticated  (https://cli.github.com)
#   - Run from inside the vitals git repo (so `gh` can detect the remote)

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo ">>> DRY RUN — no issues will be created <<<"
  echo
fi

# ─── Pre-flight checks ────────────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not installed." >&2
  echo "  macOS:  brew install gh" >&2
  echo "  Other:  https://cli.github.com" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: not logged in to gh. Run: gh auth login" >&2
  exit 1
fi

# ─── Custom labels ────────────────────────────────────────────────────────
LABELS=(
  "phase:check|38BDF8"
  "phase:runner|A78BFA"
  "phase:report|F59E0B"
  "phase:subcommand|34D399"
  "phase:release|F472B6"
  "phase:test|94A3B8"
)

create_labels() {
  echo "Creating labels (if missing)..."
  for entry in "${LABELS[@]}"; do
    label="${entry%|*}"
    color="${entry#*|}"
    if gh label list --json name -q ".[].name" 2>/dev/null | grep -qx "$label"; then
      echo "  ✓ $label (exists)"
    elif [ "$DRY_RUN" = true ]; then
      echo "  ▸ would create: $label"
    else
      gh label create "$label" --color "$color" >/dev/null 2>&1 && echo "  + $label" || echo "  ! $label (failed)"
    fi
  done
  echo
}

# ─── Issue creator ────────────────────────────────────────────────────────
# Usage: create_issue "Title" "label1,label2" <<'BODY'
#        markdown body
#        BODY
create_issue() {
  local title="$1"
  local labels="$2"
  local body
  body=$(cat)

  # Skip if an open issue with the same title already exists
  local count
  count=$(gh issue list --state open --json title -q ".[] | select(.title==\"$title\") | .number" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    echo "⊘ Skipped (exists): $title"
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "▸ Would create: $title"
    echo "  labels: $labels"
    return
  fi

  local url
  url=$(gh issue create --title "$title" --body "$body" --label "$labels" 2>&1)
  if [[ "$url" == https://github.com/* ]]; then
    echo "✓ Created: $title"
    echo "  $url"
  else
    echo "✗ Failed: $title"
    echo "  $url" >&2
  fi
}

create_labels

# ─── Phase 1: complete vitals check path ──────────────────────────────────

create_issue "Implement tcp_reachable check" "phase:check" <<'BODY'
## Goal
Add the `tcp_reachable` check type to verify a TCP address is reachable within a timeout.

## Spec
```yaml
- type: tcp_reachable
  addr: localhost:5432
  severity: warn  # optional, defaults to fail
```

## Implementation
- File: `internal/check/tcp.go`
- Use: `net.Dialer.DialContext(ctx, "tcp", addr)`
- Per-check timeout comes from the runner's context (default 5s)
- If `severity: warn` is set, unreachable → Warn instead of Fail

## Acceptance criteria
- [ ] `tcp_reachable` registered in `init()`
- [ ] Validates `addr` field is non-empty
- [ ] Respects `severity` field (warn/fail)
- [ ] Unit tests: pass on reachable, fail/warn on unreachable
- [ ] `go test ./internal/check/` green
BODY

create_issue "Implement port_free check (gopsutil)" "phase:check" <<'BODY'
## Goal
Add the `port_free` check type to verify a TCP port is not already bound by another process.

## Spec
```yaml
- type: port_free
  port: 5432
```

## Implementation
- File: `internal/check/port.go`
- Library: `github.com/shirou/gopsutil/v3/process` (cross-platform)
- Returns: Pass if no process is listening; Fail with PID + process name if occupied
- FixHint: `stop the process or change the port in docker-compose.yml`

## Acceptance criteria
- [ ] `port_free` registered in `init()`
- [ ] Uses gopsutil for cross-platform port lookup
- [ ] On Fail, message includes PID + process name (e.g. `in use by postgres (pid 812)`)
- [ ] Unit tests for both pass and fail cases
- [ ] `go get github.com/shirou/gopsutil/v3` added to go.mod
BODY

create_issue "Implement docker_running check" "phase:check" <<'BODY'
## Goal
Add the `docker_running` check type to verify the Docker daemon is responsive.

## Implementation
- File: `internal/check/docker.go`
- Approach: shell out to `docker info --format '{{.ServerVersion}}'`
- Use `exec.CommandContext` with the runner's 5s timeout
- Pass on exit 0, Fail otherwise
- Hint on Fail: `is Docker Desktop running?`

## Acceptance criteria
- [ ] `docker_running` registered in `init()`
- [ ] Pass when daemon responds
- [ ] Fail with actionable hint when daemon unreachable
- [ ] Unit tests (skip if docker not installed in CI)
BODY

create_issue "Implement runner: concurrent check execution" "phase:runner" <<'BODY'
## Goal
Build `internal/runner/runner.go` — the conductor that runs all checks concurrently with safety rails.

## Spec
- Signature: `func Run(ctx context.Context, cfg *config.Config, only []string) []check.Result`
- Worker pool using `sync.WaitGroup` or `golang.org/x/sync/errgroup`
- Per-check timeout: `context.WithTimeout(ctx, 5*time.Second)`
- Recover panics per check → report as Fail with panic message
- Results re-sorted into `vitals.yaml` declaration order for deterministic output

## Acceptance criteria
- [ ] All checks run concurrently (verify with timing test)
- [ ] Panic in one check does not kill the run
- [ ] Timeout cancels hanging checks
- [ ] `--only a,b` filter respected
- [ ] Results in declaration order regardless of completion order
- [ ] Unit tests for: panic recovery, timeout, --only filter, ordering
BODY

create_issue "Implement report: text + JSON renderers" "phase:report" <<'BODY'
## Goal
Build `internal/report/report.go` to render results in both human and machine formats.

## Text format (default)
```
✔ go 1.23.1 (>=1.22)
✔ docker running
✖ port 5432 in use by postgres (pid 812)
  → stop the process or change the port in docker-compose.yml
⚠ DATABASE_URL missing in .env [fixable]

3 passed · 1 warning · 1 failed
```

## JSON format (--json flag)
```json
[{"name":"go","status":"pass","message":"1.23.1 (satisfies >=1.22)","fixable":false}]
```

## Acceptance criteria
- [ ] `func Render(w io.Writer, results []check.Result, jsonOut bool)`
- [ ] Text renderer uses ✔/⚠/✖ symbols
- [ ] Text renderer prints FixHint with `  → ` prefix when set
- [ ] Text renderer prints summary line at the bottom
- [ ] JSON renderer produces valid JSON array
- [ ] Unit tests with golden file comparison
BODY

create_issue "Wire up vitals check subcommand + exit codes" "phase:subcommand" <<'BODY'
## Goal
Build `cmd/vitals/main.go` to dispatch the `check` subcommand and apply exit codes.

## Spec
- Subcommand: `vitals check [--json] [--only a,b]`
- Loads `vitals.yaml` from current dir
- Calls `runner.Run` → `report.Render`
- Exit codes:
  - 0 = all pass
  - 1 = any failure
  - 2 = warnings only (no failures), or config error
- Errors → stderr; report → stdout (so pipes work cleanly)

## Acceptance criteria
- [ ] `vitals check` runs end-to-end
- [ ] `--json` produces valid JSON to stdout
- [ ] `--only ports,env` filters checks
- [ ] Exit codes correct for all three states
- [ ] Unknown flags → exit 2 with usage message
BODY

create_issue "Create sample vitals.yaml + end-to-end test" "phase:test" <<'BODY'
## Goal
Ship a sample `vitals.yaml` at repo root and prove `vitals check` works on a real repo.

## Sample vitals.yaml
```yaml
checks:
  - type: binary
    name: go
    version: ">=1.22"
  - type: docker_running
  - type: port_free
    port: 5432
  - type: env_var
    name: DATABASE_URL
    from: .env.example
  - type: tcp_reachable
    addr: localhost:5432
    severity: warn
  - type: file_exists
    path: .env
    fix: "cp .env.example .env"
  - type: command
    run: "make --version"
```

## Acceptance criteria
- [ ] Sample file committed at repo root
- [ ] `./vitals check` produces expected ✔/⚠/✖ output
- [ ] `./vitals check --json` produces valid JSON
- [ ] Exit code matches the failure state
BODY

# ─── Phase 2: vitals fix ──────────────────────────────────────────────────

create_issue "Implement vitals fix subcommand" "phase:subcommand" <<'BODY'
## Goal
Apply safe auto-fixes for failing checks that are marked `Fixable`.

## Spec
- Subcommand: `vitals fix [--yes]`
- For each `Fixable` result, prompt: `Apply fix: <hint>? (y/N)`
- If `--yes`, skip prompts and apply all
- If check implements `Fixer` interface, call its `Fix(ctx)` method
- Otherwise, run the `FixHint` as a shell command via `sh -c`
- After all fixes applied, re-run checks and report
- Exit codes match `vitals check` semantics

## Acceptance criteria
- [ ] Prompt per fix unless `--yes`
- [ ] `Fixer` interface checked for self-fixing checks
- [ ] Shell fix commands run via `sh -c`
- [ ] Re-run checks after fixes; report what's still failing
- [ ] Unit tests for the prompt logic (mock stdin)
BODY

# ─── Phase 3: vitals init + list ──────────────────────────────────────────

create_issue "Implement vitals init subcommand" "phase:subcommand" <<'BODY'
## Goal
Scan the current repo and generate a starter `vitals.yaml`.

## Behavior
Detect common project markers and emit checks:
- `go.mod` → `binary: go`
- `package.json` → `binary: node`
- `Cargo.toml` → `binary: cargo`
- `docker-compose.yml` → `docker_running`
- `.env.example` → `file_exists: .env` + `env_var` checks
- `Makefile` → `command: make --version`

Write to `./vitals.yaml`. Prompt before overwrite if file exists.

## Acceptance criteria
- [ ] Detects ≥3 project types (go, node, docker)
- [ ] Writes a syntactically valid `vitals.yaml`
- [ ] Prompts on overwrite
- [ ] `vitals check` succeeds on the generated file
BODY

create_issue "Implement vitals list subcommand" "phase:subcommand" <<'BODY'
## Goal
List all registered check types with a one-line description of each.

## Behavior
- Reads the check registry
- Prints one line per type, column-aligned:
  ```
  binary                Verify a binary is on PATH and meets a version constraint
  command               Run a shell command; pass on exit 0
  docker_running        Verify the Docker daemon is responsive
  ...
  ```
- Exit 0 always (informational)

## Implementation notes
- Add a `Description()` method on the Check interface, or
- Hardcode descriptions in `cmd/vitals/main.go` (simpler, less elegant)

## Acceptance criteria
- [ ] `vitals list` prints all 7 check types
- [ ] Output is column-aligned
- [ ] Exit 0
BODY

# ─── Phase 4: distribution / polish ───────────────────────────────────────

create_issue "Add GoReleaser config" "phase:release" <<'BODY'
## Goal
Ship pre-built binaries for Linux, macOS, Windows (amd64 + arm64) on every tag.

## Spec
- File: `.goreleaser.yml` at repo root
- Build `./cmd/vitals` → binary named `vitals`
- Targets: `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64`, `windows/amd64`
- GitHub release with archives + checksums
- Homebrew tap (optional, later)

## Acceptance criteria
- [ ] `.goreleaser.yml` committed
- [ ] `goreleaser release --snapshot --clean` works locally
- [ ] First release published on tag push
BODY

create_issue "Create GitHub Action for CI" "phase:release" <<'BODY'
## Goal
Run `vitals check` on every PR + push to main, plus unit tests.

## Spec
- File: `.github/workflows/ci.yml`
- Matrix: `ubuntu-latest`, `macos-latest`, `windows-latest`
- Steps:
  1. checkout
  2. setup go
  3. `go test ./...`
  4. `go build ./cmd/vitals`
  5. `./vitals check` (against repo's own `vitals.yaml`)
- Fail the build if exit != 0

## Acceptance criteria
- [ ] CI runs on every PR
- [ ] All three platforms tested
- [ ] Test failures fail the build
- [ ] `vitals check` exit code gates the build
BODY

create_issue "Write README with demo GIF" "phase:release" <<'BODY'
## Goal
Ship a polished README that explains what `vitals` is, why it exists, and how to use it.

## Sections
1. Title + tagline ("Repo readiness checks, declaratively")
2. Demo GIF (record with `vhs` or `asciinema`)
3. Install (brew / `curl | sh` / `go install`)
4. Quick start (`vitals init` → `vitals check`)
5. Configuration reference (vitals.yaml fields)
6. Check types reference (all 7)
7. `vitals fix` usage
8. Exit codes
9. Comparison to `brew doctor` / `npm doctor`
10. Contributing (how to add a check type)

## Acceptance criteria
- [ ] README.md committed
- [ ] Demo GIF embedded
- [ ] Install instructions tested
- [ ] All 7 check types documented with examples
BODY

create_issue "Cross-platform testing" "phase:test" <<'BODY'
## Goal
Verify `vitals` works on Linux, macOS, and Windows.

## Known cross-platform concerns
- `port_free` uses gopsutil — verify PID + process name lookup on all 3 OSes
- `command` check uses `sh -c` — needs `cmd /c` on Windows
- `docker_running` — Docker Desktop vs. dockerd paths differ
- `file_exists` — path separators
- `binary` — version flag conventions vary (`--version` vs `-version` vs `version`)

## Acceptance criteria
- [ ] CI matrix runs on all 3 OSes
- [ ] Windows-specific code path in `command` check (`cmd /c` instead of `sh -c`)
- [ ] Manual smoke test on each OS
- [ ] Platform-specific gotchas documented in README
BODY

create_issue "Add per-check timeout override" "phase:runner" <<'BODY'
## Goal
Allow `vitals.yaml` to override the default 5s timeout per check.

## Spec
```yaml
- type: tcp_reachable
  addr: slow-service.internal:5432
  timeout: 30s  # override default
```

## Implementation
- Runner reads `timeout` field from check config
- Falls back to 5s if not set
- Validates duration syntax (`time.ParseDuration`)

## Acceptance criteria
- [ ] `timeout` field respected by runner
- [ ] Default 5s when missing
- [ ] Invalid duration → config error
- [ ] Unit tests
BODY

create_issue "Add severity flag support across all checks" "phase:check" <<'BODY'
## Goal
Standardize severity handling across all checks (currently only `tcp_reachable` supports it).

## Spec
- Every check accepts an optional `severity: warn|fail` field
- Default is Fail (except `env_var` which defaults to Warn by design)
- Documented per check in README

## Acceptance criteria
- [ ] `severity` field parsed by every check factory
- [ ] Applied consistently across all 7 check types
- [ ] Tests cover both severity values
BODY

# ─── Done ──────────────────────────────────────────────────────────────────
echo
echo "Done."