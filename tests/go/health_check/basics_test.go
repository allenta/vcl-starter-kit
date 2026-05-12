package health_check

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/allenta/vcl-starter-kit/tests/go/helpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestBasics verifies the health-check URL returns a synthetic 200 response.
// This is the Go equivalent of 'tests/vtc/health-check.vtc'.
func TestBasics(t *testing.T) {
	t.Parallel()

	// Start backend server.
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/foo", r.URL.Path)
		w.Header().Set("Cache-Control", "max-age=60")
	}))
	defer backend.Close()

	// Start Varnish instance.
	varnish := helpers.StartVarnish(t, helpers.StartVarnishOptions{
		VTCSubs: []string{
			"vtc_post_init_environment",
		},
		VCL: fmt.Sprintf(`
			include "main.vcl";

			# VTC instrumentation subroutines.
			sub vtc_post_init_environment {
				environment.set("default-be", "%s");
			}
		`, backend.URL),
	})
	defer varnish.Stop()

	// Request '/foo': should be a cache miss.
	resp, err := http.Get(varnish.URL + "/foo")
	require.NoError(t, err)
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, 200, resp.StatusCode)
	assert.Empty(t, body)
	assert.Equal(t, "miss cached", resp.Header.Get("X-Varnish-Cache"))

	// Request '/health-check/': should be a synthetic response.
	resp, err = http.Get(varnish.URL + "/health-check/")
	require.NoError(t, err)
	body, err = io.ReadAll(resp.Body)
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, 200, resp.StatusCode)
	assert.Empty(t, body)
	assert.Equal(t, "synth synth", resp.Header.Get("X-Varnish-Cache"))

	// Check counters.
	time.Sleep(100 * time.Millisecond) // XXX: better alternative?
	helpers.AssertVarnishCounterValue(t, varnish, "MAIN.client_req", 2)
	helpers.AssertVarnishCounterValue(t, varnish, "MGT.child_panic", 0)
}
