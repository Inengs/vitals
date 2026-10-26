// Package check defines the Check interface and the registry of check types.
//
// Each check type (binary, port_free, env_var, etc.) lives in its own file
// and calls Register in init(), so adding a check type means adding one file.
package check

import (
	"context"
	"fmt"
	"sort"
	"sync"
)

// Status of a check result
type Status int

const (
	Pass Status = iota
	Warn
	Fail
)

// String returns a human readable status name.
// this method allows the status to render The report "pass"/"warn"/"fail" in JSON output
func (s Status) String() string {
	switch s {
	case Pass:
		return "Pass"
	case Warn:
		return "Warn"
	case Fail:
		return "Fail"
	}
	return "Unknown"
}

// Result is the outcome of running a check.
type Result struct {
	Name    string
	Status  Status
	Message string
	FixHint string
	Fixable bool
}

// Check is the interface every check type must implement.
type Check interface {
	Run(ctx context.Context) Result
}

// Fixer is implemented by checks that can auto-fix their own failures.
type Fixer interface {
	Fix(ctx context.Context) error
}

// Factory builds a Check from a generic config map (parsed from vitals.yaml).
type Factory func(cfg map[string]any) (Check, error)

var (
	registryMu sync.RWMutex
	registry   = map[string]Factory{}
)

// Register a check type. Typically called from init() in each check file.
func Register(name string, f Factory) {
	registryMu.Lock()
	defer registryMu.Unlock()
	registry[name] = f
}

// Build constructs a check by type name.
func Build(name string, cfg map[string]any) (Check, error) {
	registryMu.RLock()
	f, ok := registry[name]
	registryMu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("unknown check type: %q (available: %s)", name, Names())
	}
	return f(cfg)
}

// Names returns all registered check type names, sorted and comma-separated.
func Names() string {
	registryMu.RLock()
	defer registryMu.RUnlock()
	names := make([]string, 0, len(registry))
	for n := range registry {
		names = append(names, n)
	}
	sort.Strings(names)
	out := ""
	for i, n := range names {
		if i > 0 {
			out += ", "
		}
		out += n
	}
	return out
}
