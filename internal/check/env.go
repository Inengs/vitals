package check

import (
	"context"
	"fmt"
	"os"
)

type envCheck struct {
	name string // env var name, e.g. "DATABASE_URL"
	from string // optional: file to copy a default from, e.g. ".env.example"
}

func init() {
	Register("env_var", func(cfg map[string]any) (Check, error) {
		name, _ := cfg["name"].(string) // assert name is a string
		if name == "" {
			// if the user forgot to put name in their Yaml, return an error
			return nil, fmt.Errorf("env_var: missing %q", "name")
		}
		from, _ := cfg["from"].(string) // assert from as a string
		return &envCheck{name: name, from: from}, nil
	})
}

func (e *envCheck) Run(ctx context.Context) Result {
	if v, ok := os.LookupEnv(e.name); ok {
		// used to retrieve the value of an environment variable while also checking whether that variable actually exists
		return Result{Name: e.name, Status: Pass, Message: fmt.Sprintf("set (%d chars)", len(v))}
	}
	return Result{
		Name:    e.name,
		Status:  Warn, // ← Warn, not Fail because Because a missing env var usually means "the repo will run but misbehave" — the developer probably has it set in their shell, just not in the current terminal
		Message: "not set",
		Fixable: e.from != "",
		FixHint: fmt.Sprintf("copy %s from %s", e.name, e.from), // A templated hint instead of a raw command. The hint is shown to the user as guidance ("here's what you'd do"), not executed directly.
	}
}
