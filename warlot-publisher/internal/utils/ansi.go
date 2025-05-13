package utils

import "regexp"

// var ansiCleaner = regexp.MustCompile(` + "`\x1b\[[0-9;]*[mG]`" + `)
var ansiCleaner = regexp.MustCompile(`\x1b\[[0-9;]*[mG]`)
// RemoveANSI strips ANSI escape codes from the input string.
func RemoveANSI(input string) string {
	return ansiCleaner.ReplaceAllString(input, "")
}