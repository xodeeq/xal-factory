package slug

import (
	"errors"
	"strings"
)

// ErrTooLong is FX-FR-02's refusal.
var ErrTooLong = errors.New("slug: name longer than 64 characters")

// Slug is FX-FR-01: lowercase, each run of spaces one hyphen. FX-FR-02: over 64 is refused.
func Slug(name string) (string, error) {
	if len(name) > 64 {
		return "", ErrTooLong
	}
	return strings.Join(strings.Fields(strings.ToLower(name)), "-"), nil
}
