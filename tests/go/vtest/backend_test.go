package vtest

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/allenta/vcl-starter-kit/tests/go/helpers"
	"github.com/stretchr/testify/assert"
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
	varnish := vtest.
		New().
		SetLicensePath(helpers.LicensePath).
		Parameter("-j", helpers.JailModeParameter).
		Parameter("-p", helpers.VCLPathParameter(helpers.VCLRoot())).
		Backend("default", backend.URL).
		Vcl41().
		VclString(vcl).
		AssertStart(t)
	defer varnish.Stop()

	// Submit first request: miss.
	resp := helpers.MustRequest(t, http.MethodGet, varnish.URL+"/foo", nil, nil)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, expectedBody, helpers.MustReadResponseBody(t, resp))
	assert.Equal(t, expectedHeaderValue, resp.Header.Get(expectedHeaderName))
	assert.Equal(t, "0", resp.Header.Get("X-Hits"))

	// Submit second request: hit.
	resp = helpers.MustRequest(t, http.MethodGet, varnish.URL+"/foo", nil, nil)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, expectedBody, helpers.MustReadResponseBody(t, resp))
	assert.Equal(t, expectedHeaderValue, resp.Header.Get(expectedHeaderName))
	assert.Equal(t, "1", resp.Header.Get("X-Hits"))

	// Check counters.
	varnish.Counter("MAIN.client_req").AssertEquals(t, 2)
	varnish.Counter("MGT.child_panic").AssertEquals(t, 0)
	varnish.Counter("MAIN.cache_hit").AssertEquals(t, 1)
}
