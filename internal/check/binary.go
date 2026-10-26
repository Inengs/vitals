package check

import (
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strings"

	"github.com/Masterminds/semver/v3"
)

// binaryCheck verifies a binary is on PATH and optionally meets a version constraint.
type binaryCheck struct {
	name    string
	version string // optional constraint, e.g. ">=1.22"
}

func init() {
	Register("binary", func(cfg map[string]any) (Check, error) {
		name, _ := cfg["name"].(string)
		if name == "" {
			return nil, fmt.Errorf("binary: missing %q", "name")
		}
		version, _ := cfg["version"].(string)
		return &binaryCheck{name: name, version: version}, nil
	})
}

func (b *binaryCheck) Run(ctx context.Context) Result {
	// 1. Find on PATH
	path, err := exec.LookPath(b.name)

	// 2. Not found → Fail (not fixable — we don't auto-install system tools)
	if err != nil {
		return Result{
			Name:    b.name,
			Status:  Fail,
			Message: "not installed (not on PATH)",
		}
	}

	// 3. Found, but no version constraint → Pass with the resolved path
	if b.version == "" {
		return Result{
			Name:    b.name,
			Status:  Pass,
			Message: fmt.Sprintf("installed at %s", path),
		}
	}

	// 4–6. Try --version, then -version, then version
	flags := []string{"--version", "-version", "version"}
	var out []byte
	for _, flag := range flags {
		cmd := exec.CommandContext(ctx, path, flag)
		out, err = cmd.CombinedOutput() // reuses outer `out` and `err`
		if err == nil {
			break
		}
	}

	// 7. All flags failed
	if err != nil {
		return Result{
			Name:    b.name,
			Status:  Fail,
			Message: "installed but could not determine version (tried --version, -version, version)",
		}
	}

	// 8. Parse version out of output
	re := regexp.MustCompile(`(\d+\.\d+(?:\.\d+)?)`)
	m := re.FindStringSubmatch(string(out))

	// 9. Parse failed
	if m == nil {
		return Result{
			Name:    b.name,
			Status:  Warn,
			Message: fmt.Sprintf("installed but could not parse version: %q", strings.TrimSpace(string(out))),
		}
	}
	parsedVersion := m[1]

	// 11. Compare against constraint
	constraint, err := semver.NewConstraint(b.version)
	if err != nil {
		return Result{
			Name:    b.name,
			Status:  Fail,
			Message: fmt.Sprintf("invalid version constraint %q: %v", b.version, err),
		}
	}
	ver, err := semver.NewVersion(parsedVersion)
	if err != nil {
		return Result{
			Name:    b.name,
			Status:  Warn,
			Message: fmt.Sprintf("could not parse semver from %q: %v", parsedVersion, err),
		}
	}

	// 12. Constraint satisfied
	if constraint.Check(ver) {
		return Result{
			Name:    b.name,
			Status:  Pass,
			Message: fmt.Sprintf("%s (satisfies %s)", parsedVersion, b.version),
		}
	}

	// 13. Constraint not satisfied
	return Result{
		Name:    b.name,
		Status:  Fail,
		Message: fmt.Sprintf("%s (wanted %s)", parsedVersion, b.version),
	}
}
