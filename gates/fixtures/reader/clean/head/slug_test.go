package slug

import (
	"errors"
	"strings"
	"testing"
)

// FX-FR-01
func TestSlugLowercasesAndHyphenates(t *testing.T) {
	got, err := Slug("Acme  Corp")
	if err != nil || got != "acme-corp" {
		t.Fatalf(`Slug("Acme  Corp") = %q, %v; want "acme-corp", nil`, got, err)
	}
}

// FX-FR-02: 65 is refused with no slug, and 64 — the boundary — is accepted.
func TestSlugRefusesOver64(t *testing.T) {
	got, err := Slug(strings.Repeat("a", 65))
	if !errors.Is(err, ErrTooLong) || got != "" {
		t.Fatalf("65 chars: got %q, %v; want \"\", ErrTooLong", got, err)
	}
	if _, err := Slug(strings.Repeat("a", 64)); err != nil {
		t.Fatalf("64 chars: got %v; want accepted", err)
	}
}
