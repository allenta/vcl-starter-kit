package helpers

import (
	"flag"
	"fmt"
)

const (
	LicensePath       = "/usr/share/varnish-plus/vtc-license.dat"
	JailModeParameter = "none"
)

// vclRootFlag is the path to the root directory of VCL files. The flag is
// registered by 'init()' and set via 'go test -args -vcl-root=<path>'.
var vclRootFlag = flag.String("vcl-root", "", "")

func VCLRoot() string {
	if *vclRootFlag == "" {
		panic("required flag '-vcl-root' not set")
	}

	return *vclRootFlag
}

func VCLPathParameter(vclRoot string) string {
	return fmt.Sprintf("vcl_path=%s:/usr/share/varnish-plus/vcl", vclRoot)
}
