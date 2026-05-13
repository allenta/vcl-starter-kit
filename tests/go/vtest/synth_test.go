package vtest

import (
	"net/http"
	"testing"

	"github.com/allenta/vcl-starter-kit/tests/go/helpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/varnish/varnish-go/vtest"
)

// TestSynth verifies 'vtest' works with a simple synthetic response.
func TestSynth(t *testing.T) {
	t.Parallel()

	// Initializations.
	const vcl = `
		vcl 4.1;

		backend default none;

		sub vcl_recv {
			return (synth(200, "OK"));
		}
	`

	// Start Varnish instance.
	varnish := vtest.
		New().
		SetLicensePath(helpers.LicensePath).
		Parameter("-j", helpers.JailModeParameter).
		Parameter("-p", helpers.VCLPathParameter(helpers.VCLRoot())).
		VCLVersion("").
		VclString(vcl).
		AssertStart(t)
	defer varnish.Stop()

	// Submit request.
	resp, err := http.Get(varnish.URL + "/foo")
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, 200, resp.StatusCode)

	// Check counters.
	varnish.Counter("MAIN.client_req").AssertEquals(t, 1)
	varnish.Counter("MGT.child_panic").AssertEquals(t, 0)
}
