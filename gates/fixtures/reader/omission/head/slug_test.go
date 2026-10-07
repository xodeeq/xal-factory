package slug

import "testing"

// FX-FR-01
func TestSlugLowercasesAndHyphenates(t *testing.T) {
	got, err := Slug("Acme  Corp")
	if err != nil || got != "acme-corp" {
		t.Fatalf(`Slug("Acme  Corp") = %q, %v; want "acme-corp", nil`, got, err)
	}
}
