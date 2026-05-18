package save_backend_request

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/allenta/vcl-starter-kit/tests/go/helpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestBasics verifies the save backend request feature (retries + revive).
// This is the Go equivalent of 'tests/vtc/save-backend-request.vtc'.
func TestBasics(t *testing.T) {
	t.Parallel()

	// Start backend server s1: always fails with 500.
	var s1RequestCount int
	s1 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/foo", r.URL.Path)
		s1RequestCount++
		w.WriteHeader(500)
	}))
	defer s1.Close()

	// Start backend server s2: returns 200 first, then 500 forever.
	var s2RequestCount int
	s2 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/foo", r.URL.Path)
		s2RequestCount++
		if s2RequestCount == 1 {
			w.Header().Set("Cache-Control", "max-age=60, stale-while-revalidate=0, stale-if-error=120")
			w.WriteHeader(200)
		} else {
			w.WriteHeader(500)
		}
	}))
	defer s2.Close()

	// Start Varnish instance.
	varnish := helpers.Varnish(t, helpers.VarnishOptions{
		VTCSubs: []string{
			"vtc_post_init_environment",
			"vtc_post_init",
		},
		VCL: fmt.Sprintf(`
			include "main.vcl";

			# VCL patching.

			sub vcl_init {
				new vtc_dir = udo.director(fallback);
				vtc_dir.add_backend(s1);
				vtc_dir.add_backend(s2);
			}

			sub vcl_backend_fetch {
				# Override the backend selection.
				if (bereq.retries == 0) {
					set bereq.backend = vtc_dir.backend();
				}
			}

			# VTC instrumentation subroutines.

			sub vtc_post_init_environment {
				environment.set("default-be", "%s");
			}

			sub vtc_post_init {
				# Max number of retries is configurable.
				config.set(
					"foo:max-retries",
					"1");

				# TTL and grace for revived objects is configurable.
				config.set(
					"foo:stale-revive-ttl",
					"30s");
				config.set(
					"foo:stale-revive-grace",
					"1m");
			}
		`, s1.URL),
	}).Backend("s1", s1.URL).Backend("s2", s2.URL).AssertStart(t)
	defer varnish.Stop()

	// Initial request for a cacheable object (fetch s1#1 and fetch s2#1). Server
	// s1 fails but the VCL retries with s2 and successfully gets a response.
	resp, err := http.Get(varnish.URL + "/foo")
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Empty(t, helpers.MustReadResponseBody(t, resp))
	assert.Equal(t, "miss cached", resp.Header.Get("X-Varnish-Cache"))
	assert.Equal(t, "0", resp.Header.Get("X-Varnish-Hits"))
	assert.Equal(t, "60.000", resp.Header.Get("X-Varnish-Debug-Initial-Ttl"))
	assert.Equal(t, "0.000", resp.Header.Get("X-Varnish-Debug-Initial-Grace"))
	assert.Equal(t, "120.000", resp.Header.Get("X-Varnish-Debug-Initial-Keep"))

	// Subsequent request should be a cache hit.
	resp, err = http.Get(varnish.URL + "/foo")
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Empty(t, helpers.MustReadResponseBody(t, resp))
	assert.Equal(t, "hit cached", resp.Header.Get("X-Varnish-Cache"))
	assert.Equal(t, "1", resp.Header.Get("X-Varnish-Hits"))
	assert.Equal(t, "60.000", resp.Header.Get("X-Varnish-Debug-Initial-Ttl"))
	assert.Equal(t, "0.000", resp.Header.Get("X-Varnish-Debug-Initial-Grace"))
	assert.Equal(t, "120.000", resp.Header.Get("X-Varnish-Debug-Initial-Keep"))

	// Soft purge the content. The content's TTL goes to 0 but it is still kept
	// in the cache because it has a keep time defined.
	req, err := http.NewRequest(http.MethodGet, varnish.URL+"/foo", nil)
	require.NoError(t, err)
	req.Header.Set("X-Soft-Purge", "1")
	resp, err = http.DefaultClient.Do(req)
	require.NoError(t, err)
	assert.Equal(t, "200 Soft purged (1)", resp.Status)
	assert.Empty(t, helpers.MustReadResponseBody(t, resp))

	// Next request is a miss. A synchronous fetch is done and both the backends
	// respond with an error (fetch s1#2 and fetch s2#2), so the VCL revives the
	// object and returns it with the configured TTL and grace for revived
	// objects.
	resp, err = http.Get(varnish.URL + "/foo")
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Empty(t, helpers.MustReadResponseBody(t, resp))
	assert.Equal(t, "miss cached", resp.Header.Get("X-Varnish-Cache"))
	assert.Equal(t, "0", resp.Header.Get("X-Varnish-Hits"))
	assert.Equal(t, "60.000", resp.Header.Get("X-Varnish-Debug-Initial-Ttl"))
	assert.Equal(t, "0.000", resp.Header.Get("X-Varnish-Debug-Initial-Grace"))
	assert.Equal(t, "120.000", resp.Header.Get("X-Varnish-Debug-Initial-Keep"))
	assert.LessOrEqual(
		t,
		helpers.MustParseFloat(t, resp.Header.Get("X-Varnish-Debug-Ttl")),
		30.0)
	assert.LessOrEqual(
		t,
		helpers.MustParseFloat(t, resp.Header.Get("X-Varnish-Debug-Grace")),
		60.0)

	// Check counters.
	varnish.Counter("MAIN.client_req").AssertEquals(t, 4)
	varnish.Counter("MGT.child_panic").AssertEquals(t, 0)
}
