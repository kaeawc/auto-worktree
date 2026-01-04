package terminal

import (
	"fmt"
	"os"
)

// SetTitle sets the terminal window title using an ANSI escape sequence.
func SetTitle(title string) {
	if title == "" {
		return
	}

	fmt.Fprintf(os.Stdout, "\033]0;%s\007", title)
}
