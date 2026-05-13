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
	varnish, err := vtest.
		New().
		SetLicensePath(helpers.LicensePath).
		Parameter("-j", helpers.JailModeParameter).
		Parameter("-p", helpers.VCLPathParameter(helpers.VCLRoot())).
		VCLVersion("").
		VclString(vcl).
		Start()
	require.NoError(t, err)
	defer varnish.Stop()

	// Submit request.
	resp, err := http.Get(varnish.URL + "/foo")
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, 200, resp.StatusCode)

	// Check counters.
	helpers.AssertVarnishCounterValue(t, varnish, "MAIN.client_req", 1)
	helpers.AssertVarnishCounterValue(t, varnish, "MGT.child_panic", 0)
}
