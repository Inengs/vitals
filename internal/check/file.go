package check

import (
	"context" // used for timeouts/cancellation
	"fmt"     // formatting errors
	"os"      // file existence check
)

// fileCheck verifies a file exists at the given path
// If a `fix` shell command is supplied, the result is marked Fixable
type fileCheck struct {
	path string // the file path to verify
	fix  string // optional shell command to create the file
} // When a file_exists check is built, we create one of these and fill it with the path and fix command from the YAML. The struct "remembers" what to check when Run() is called

// runs once at program startup; registers the factory
func init() {
	Register("file_exists", func(cfg map[string]any) (Check, error) {
		//Calling Register with two arguments:
		// The string name "file_exists" (this is what users type in vitals.yaml as type: file_exists)
		// A factory function — given a config map, build a Check. The factory is a closure; it captures nothing, it just receives cfg when called.

		path, _ := cfg["path"].(string) // assert path is a string
		if path == "" {
			// if the user forgot to put path in their Yaml, return an error
			return nil, fmt.Errorf("file_exists: missing %q", "path")
		}
		fix, _ := cfg["fix"].(string)                // assert fix as a string, fix is optional so no error, when it is empty
		return &fileCheck{path: path, fix: fix}, nil // Construct the struct with named fields, return a pointer to it, and nil error.
	})
}

// the actual check logic, returns a Result
// the fileCheck pointer satisfies the Check interface because it has a Run method (defined below).
func (f *fileCheck) Run(ctx context.Context) Result {
	// this is a method on *fileCheck, it takes a context (for cancellation/timeouts) and returns a Result.
	info, err := os.Stat(f.path) // returns file info or an error.
	if err == nil {

		if info.IsDir() {
			// file exists but is not a file, maybe it is a directory
			return Result{Name: f.path, Status: Fail, Message: "expected file, found directory"}
		}
		// file exists
		return Result{Name: f.path, Status: Pass, Message: "exists"}
	}

	// file is missing, and a fix command was supplied, mark the result as Fixable and put the fix command in FixHint
	if os.IsNotExist(err) {
		return Result{
			Name:    f.path,
			Status:  Fail,
			Message: "missing",
			Fixable: f.fix != "",
			FixHint: f.fix,
		}
	}
	return Result{Name: f.path, Status: Fail, Message: err.Error()}
}
