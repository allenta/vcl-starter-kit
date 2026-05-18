package helpers

import (
	"io"
	"net/http"
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"
)

func MustReadResponseBody(t *testing.T, resp *http.Response) string {
	t.Helper()
	bodyBytes, err := io.ReadAll(resp.Body)
	assert.NoError(t, err, "failed to read response body")
	err = resp.Body.Close()
	assert.NoError(t, err, "failed to close response body")
	return string(bodyBytes)
}

func MustParseFloat(t *testing.T, value string) float64 {
	t.Helper()
	parsedValue, err := strconv.ParseFloat(value, 64)
	assert.NoError(t, err, "failed to parse string value as float")
	return parsedValue
}
