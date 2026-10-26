package check

import (
	"context"
	"fmt"
	"os/exec"
)

// how to read any check file
// When you see a new check file in this codebase, look for these four parts in order:

// Part
// Question to ask yourself
// 1. type xxxCheck struct { ... }	What config does this check remember?
// 2. func init() { Register("xxx", ...) }	What's the YAML type name? What fields are required vs optional?
// 3. The factory closure body	What validation happens before construction?
// 4. func (x *xxxCheck) Run(ctx) Result	What library call does the work? What statuses can it return? When is it Fixable?

type commandCheck struct {
	run string // the shell command to execute
}

func init() {
	Register("command", func(cfg map[string]any) (Check, error) {
		run, _ := cfg["run"].(string)
		if run == "" {
			return nil, fmt.Errorf("command: missing %q", "run")
		}
		return &commandCheck{run: run}, nil
	})
}

func (c *commandCheck) Run(ctx context.Context) Result {
	cmd := exec.CommandContext(ctx, "sh", "-c", c.run) // Run a shell. We don't try to parse the command string ourselves (quoting, redirects, pipes would be a nightmare). Instead we delegate to /bin/sh via the -c flag, which says "treat the next argument as a shell script"
	out, err := cmd.CombinedOutput()                   // Runs the command, waits for it to finish, returns the combined stdout + stderr output as []byte
	if err != nil {
		return Result{
			Name:    c.run,
			Status:  Fail,
			Message: fmt.Sprintf("exit: %s — %s", err, string(out)), // When the command fails, the message includes: The Go error (which usually contains the exit code), The command's combined stdout+stderr output
		}
	}
	return Result{Name: c.run, Status: Pass, Message: "ok"}
}
