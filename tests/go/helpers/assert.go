package helpers

import (
	"io"
	"net/http"
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"
)

func MustRequest(
	t *testing.T, method, url string, headers http.Header,
	body io.Reader) *http.Response {
	t.Helper()

	req, err := http.NewRequest(method, url, body)
	require.NoError(t, err, "failed to create %s request", method)
	req.Header = headers

	resp, err := http.DefaultClient.Do(req)
	require.NoError(t, err, "failed to perform %s request", method)
	return resp
}

func MustReadResponseBody(t *testing.T, resp *http.Response) string {
	t.Helper()

	bodyBytes, err := io.ReadAll(resp.Body)
	require.NoError(t, err, "failed to read response body")
	err = resp.Body.Close()
	require.NoError(t, err, "failed to close response body")
	return string(bodyBytes)
}

func MustParseFloat(t *testing.T, value string) float64 {
	t.Helper()

	parsedValue, err := strconv.ParseFloat(value, 64)
	require.NoError(t, err, "failed to parse string value as float")
	return parsedValue
}
