package helpers

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/varnish/varnish-go/vtest"
)

func AssertVarnishCounterValue(t *testing.T, varnish vtest.Varnish, name string, expectedValue uint64) {
	actualValue, err := varnish.CounterValue(name)
	require.NoError(t, err, "reading '%s' counter", name)
	assert.Equal(t, expectedValue, actualValue, "counter '%s'", name)
}
