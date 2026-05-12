package helpers

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

// vclRootFlag is registered by 'init()' and set via 'go test -args -vcl-root=<path>'.
var vclRootFlag = flag.String("vcl-root", "", "")

// vclRoot returns the absolute path to the VCL files. It uses the '-vcl-root'
// flag if provided, otherwise falls back to resolving relative to the current
// working directory (assuming cwd is 'tests/go/').
func vclRoot() string {
	if *vclRootFlag != "" {
		return *vclRootFlag
	}

	cwd, _ := os.Getwd()
	dir, err := filepath.Abs(filepath.Join(cwd, "..", ".."))
	if err != nil {
		panic(err)
	}
	return dir
}

func VCLPathParameter() string {
	return fmt.Sprintf("vcl_path=%s:/usr/share/varnish-plus/vcl", vclRoot())
}
