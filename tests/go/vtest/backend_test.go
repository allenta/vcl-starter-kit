package vtest

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
	"github.com/varnish/varnish-go/vtest"
)

// TestBackend verifies 'vtest' works with a mocked backend server.
func TestBackend(t *testing.T) {
	t.Parallel()

	// Initializations.
	const expectedBody = "Hello, Varnish!"
	const expectedHeaderName = "X-Foo"
	const expectedHeaderValue = "42"
	const vcl = `
		sub vcl_deliver {
			set resp.http.X-Hits = obj.hits;
		}
	`

	// Start backend server.
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/foo", r.URL.Path)

		w.Header().Set("Cache-Control", "max-age=60")
		w.Header().Set(expectedHeaderName, expectedHeaderValue)
		fmt.Fprint(w, expectedBody)
	}))
	defer backend.Close()

	// Start Varnish instance.
	varnish, err := vtest.
		New().
		Parameter("-L", helpers.LicensePathParameter).
		Parameter("-j", helpers.JailModeParameter).
		Parameter("-p", helpers.VCLPathParameter(helpers.VCLRoot())).
		Backend("default", backend.URL).
		Vcl41().
		VclString(vcl).
		Start()
	require.NoError(t, err)
	defer varnish.Stop()

	// Submit first request: miss.
	resp, err := http.Get(varnish.URL + "/foo")
	require.NoError(t, err)
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, expectedBody, string(body))
	assert.Equal(t, expectedHeaderValue, resp.Header.Get(expectedHeaderName))
	assert.Equal(t, "0", resp.Header.Get("X-Hits"))

	// Submit second request: hit.
	resp, err = http.Get(varnish.URL + "/foo")
	require.NoError(t, err)
	body, err = io.ReadAll(resp.Body)
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, expectedBody, string(body))
	assert.Equal(t, expectedHeaderValue, resp.Header.Get(expectedHeaderName))
	assert.Equal(t, "1", resp.Header.Get("X-Hits"))

	// Check counters.
	time.Sleep(100 * time.Millisecond) // XXX: better alternative?
	helpers.AssertVarnishCounterValue(t, varnish, "MAIN.client_req", 2)
	helpers.AssertVarnishCounterValue(t, varnish, "MGT.child_panic", 0)
	helpers.AssertVarnishCounterValue(t, varnish, "MAIN.cache_hit", 1)
}
