// Package config parses and validates vitals.yaml
package config

import (
	"fmt"
	"os"

	"github.com/goccy/go-yaml"
)

// Config is the top-level vitals.yaml structure
type Config struct {
	// Config is just a list of checks
	Checks []map[string]any `yaml:"checks"` // every check is a generic map
}

func Load(path string) (*Config, error) {
	// tThe real-world entry point: read file → parse → validate → return
	data, err := os.ReadFile(path) // read the file

	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err) // Wraps errors with context
	}

	var c Config
	if err := yaml.Unmarshal(data, &c); err != nil {
		// parse the file
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if err := c.validate(); err != nil {
		// validate the file
		return nil, err
	}
	return &c, nil // return the config file
}

// ParseBytes parses config from bytes (useful for tests).
func ParseBytes(b []byte) (*Config, error) {
	var c Config
	if err := yaml.Unmarshal(b, &c); err != nil {
		return nil, err
	}
	if err := c.validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

func (c *Config) validate() error {
	// Walks each check, ensures it has a type field
	for i, ck := range c.Checks {
		t, _ := ck["type"].(string)
		if t == "" {
			return fmt.Errorf("check #%d: missing required field %q", i+1, "type")
		}
	}
	return nil
}
