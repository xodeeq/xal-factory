package slug

import "strings"

// Slug is FX-FR-01: lowercase, each run of spaces one hyphen.
func Slug(name string) (string, error) {
	return strings.Join(strings.Fields(strings.ToLower(name)), "-"), nil
}
