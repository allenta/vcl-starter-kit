package helpers

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/varnish/varnish-go/vtest"
)

func AssertVarnishCounterValue(t *testing.T, varnish vtest.Varnish, name string, expectedValue uint64) {
	t.Helper()

	checker := varnish.Counter(name).TryFor(1 * time.Second)
	err := checker.Equals(expectedValue)
	assert.NoError(t, err, "counter '%s'", name)
}
