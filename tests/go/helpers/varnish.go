package helpers

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/varnish/varnish-go/vtest"
)

type VarnishOptions struct {
	// VTCSubs lists instrumentation subroutine names to uncomment in VCL files
	// (e.g., 'vtc_post_init_environment').
	VTCSubs []string

	// VCL is the full VCL content to use for the test. It usually contains an
	// 'include "main.vcl";' plus any additional test-specific VCL, such as
	// implementations of instrumentation subroutines.
	VCL string

	// TempDir is the temporary directory to use when preparing VCL files. If
	// empty, a new temporary directory is created. It can be useful when the
	// caller needs to prepare extra files required by the VCL logic (e.g.,
	// 'nodes.conf' files, etc.).
	TempDir string
}

// Varnish creates a Varnish instance configured for testing.
func Varnish(t *testing.T, opts VarnishOptions) *vtest.VarnishBuilder {
	t.Helper()

	vclDir := PrepareVCL(t, opts)

	builder := vtest.
		New().
		Parameter("-L", LicensePathParameter).
		Parameter("-j", JailModeParameter).
		Parameter("-p", VCLPathParameter(vclDir)).
		Vcl41().
		VclString(opts.VCL)

	return builder
}

// PrepareVCL copies the project VCL files into a temporary directory and
// applies some tweaks:
//   - Remove 'vcl 4.1;' line.
//   - Uncomment 'include "akamai.vcl"'.
//   - Force 'replication-disabled.vcl' as the replication strategy.
//   - Uncomment 'call <sub>;' lines for enabled instrumentation subroutines.
func PrepareVCL(t *testing.T, opts VarnishOptions) string {
	t.Helper()

	// Create a temporary directory for this test's VCL files.
	vclDir := opts.TempDir
	if vclDir == "" {
		vclDir = t.TempDir()
	}

	// Copy VCL tree.
	err := copyDir(VCLRoot(), vclDir)
	require.NoError(t, err, "copying VCL files")

	// Apply tweaks to 'main.vcl'.
	err = patchMainVCL(filepath.Join(vclDir, "main.vcl"))
	require.NoError(t, err, "patching 'main.vcl'")

	// Uncomment instrumentation subroutine calls in all VCL files.
	if len(opts.VTCSubs) > 0 {
		err := enableInstrumentationSubs(vclDir, opts.VTCSubs)
		require.NoError(t, err, "enabling instrumentation subroutines")
	}

	return vclDir
}

// patchMainVCL applies common tweaks to 'main.vcl'.
func patchMainVCL(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	content := string(data)

	// Remove 'vcl 4.1;' line.
	content = regexp.
		MustCompile(`(?m)^\s*vcl\s+4\.1;\s*$`).
		ReplaceAllString(content, "")

	// Uncomment 'include "akamai.vcl"'.
	content = regexp.
		MustCompile(`(?m)^# (include "akamai\.vcl";)`).
		ReplaceAllString(content, "$1")

	// Comment all replication includes.
	content = regexp.
		MustCompile(`(?m)^(include "replication-.*\.vcl");`).
		ReplaceAllString(content, "# $1;")

	// Uncomment 'include "replication-disabled.vcl"'.
	content = regexp.
		MustCompile(`(?m)^# (include "replication-disabled\.vcl";)`).
		ReplaceAllString(content, "$1")

	return os.WriteFile(path, []byte(content), 0o644)
}

// enableInstrumentationSubs uncomments 'call <sub>;' lines for enabled
// instrumentation subroutines across all VCL files.
func enableInstrumentationSubs(vclDir string, subs []string) error {
	regexes := make(map[string]*regexp.Regexp)
	for _, sub := range subs {
		regexes[sub] = regexp.MustCompile(`(?m)^(\s*)# (call ` + regexp.QuoteMeta(sub) + `;)$`)
	}

	return filepath.WalkDir(vclDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || filepath.Ext(path) != ".vcl" {
			return nil
		}

		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		text := string(data)

		changed := false
		for _, re := range regexes {
			replaced := re.ReplaceAllString(text, "$1$2")
			if replaced != text {
				text = replaced
				changed = true
			}
		}

		if changed {
			info, err := os.Stat(path)
			if err != nil {
				return err
			}
			return os.WriteFile(path, []byte(text), info.Mode())
		}

		return nil
	})
}

// copyDir recursively copies 'src' to 'dst'.
func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}

		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}

		target := filepath.Join(dst, rel)

		if d.IsDir() {
			info, err := d.Info()
			if err != nil {
				return err
			}
			return os.MkdirAll(target, info.Mode())
		}

		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}

		info, err := d.Info()
		if err != nil {
			return err
		}

		return os.WriteFile(target, data, info.Mode())
	})
}
