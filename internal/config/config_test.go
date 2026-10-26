package config

import "testing"

func TestParseBytes(t *testing.T) {
	in := []byte(`
checks:
  - type: binary
    name: go
    version: ">=1.22"
  - type: port_free
    port: 5432
`)
	c, err := ParseBytes(in)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(c.Checks) != 2 {
		t.Fatalf("want 2 checks, got %d", len(c.Checks))
	}
	if c.Checks[0]["type"] != "binary" {
		t.Errorf("first type = %v, want binary", c.Checks[0]["type"])
	}
	if port, ok := c.Checks[1]["port"].(int); !ok || port != 5432 {
		t.Errorf("port = %v (%T), want int 5432", c.Checks[1]["port"], c.Checks[1]["port"])
	}
}

func TestValidateRejectsMissingType(t *testing.T) {
	in := []byte(`
checks:
  - name: go
`)
	if _, err := ParseBytes(in); err == nil {
		t.Fatal("expected error for missing type field, got nil")
	}
}
