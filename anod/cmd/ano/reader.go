package main

import (
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strings"

	"ano/anod/internal/ipc"
)

// readerCmd shows a reader panel (through the shell) or prints anod's reader status.
func readerCmd(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: ano reader anime|manga|novel [open|close|toggle] | ano reader status [--json]")
		return 2
	}
	if args[0] == "status" {
		res, err := ipc.Call(ipc.DefaultSocketPath(), "reader.status", nil)
		if err != nil {
			fmt.Fprintln(os.Stderr, "ano:", err)
			return 1
		}
		if slices.Contains(args[1:], "--json") {
			fmt.Println(string(res))
			return 0
		}
		var st struct {
			Running  bool              `json:"running"`
			Open     []string          `json:"open"`
			Playing  bool              `json:"playing"`
			Backends map[string]string `json:"backends"`
			Error    string            `json:"error"`
		}
		json.Unmarshal(res, &st)
		state := "stopped"
		if st.Running {
			state = "running"
		}
		fmt.Printf("reader backend: %s\nopen panels:    %s\nplaying:        %v\n", state, strings.Join(st.Open, ", "), st.Playing)
		for _, k := range []string{"anime", "manga", "novel"} {
			if b := st.Backends[k]; b != "" {
				fmt.Printf("%-15s %s\n", k+":", b)
			}
		}
		if st.Error != "" {
			fmt.Println("last error:    ", st.Error)
		}
		return 0
	}
	kind := args[0]
	if !slices.Contains([]string{"anime", "manga", "novel"}, kind) {
		fmt.Fprintf(os.Stderr, "ano: unknown reader %q (want anime, manga or novel)\n", kind)
		return 2
	}
	action := "toggle"
	if len(args) > 1 {
		action = args[1]
	}
	if !slices.Contains([]string{"open", "close", "toggle"}, action) {
		fmt.Fprintf(os.Stderr, "ano: unknown action %q (want open, close or toggle)\n", action)
		return 2
	}
	return shellIPC("call", "reader", action, kind)
}
