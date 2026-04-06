##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

# This is a collection of helper subroutines useful across multiple routes in
# the configuration. Do not include any 'vcl_*' subroutines here. Use custom
# subroutines instead with proper namespacing and documented inputs and outputs
# to simplify maintenance.

#
# This subroutine must be called just before completing execution of
# 'vcl_deliver' or 'vcl_synth' phases in order to execute some common tasks.
# Multiple exit points are possible, so we encapsulate the common logic here.
#
sub deliver_client_response {
    # Avoid delivering useless headers to the client. These are headers present
    # both in 'vcl_deliver' and 'vcl_synth' responses.
    unset resp.http.X-Varnish;
    unset resp.http.Via;
    unset resp.http.X-Powered-By;
    unset resp.http.Server;

    # Update ad-hoc 'resp-*' counters. VHA request cannot reach this point, but
    # self-routed cluster requests can and we're intentionally counting them.
    if (resp.status >= 200 && resp.status < 300) {
        counters.counter("resp-2xx", 1, varnishstat=true);
    } elseif (resp.status >= 300 && resp.status < 400) {
        counters.counter("resp-3xx", 1, varnishstat=true);
    } elseif (resp.status >= 400 && resp.status < 500) {
        counters.counter("resp-4xx", 1, varnishstat=true);
    } elseif (resp.status >= 500 && resp.status < 600) {
        counters.counter("resp-5xx", 1, varnishstat=true);
    }

    # Done!
    return (deliver);
}

#
# This subroutine attempts to save a broken backend request by retrying it or
# reviving a stale object if possible.
#
# Input:
#   - request.get("X-Varnish-Route")
#   - request.get("X-Varnish-Bodyaccess-Method") (optional)
#
sub save_backend_request {
    # We got a broken response from the backend (i.e., 'vcl_backend_response'), or
    # it was generated through a backend failure (i.e., 'vcl_backend_error'), or
    # the backend was tagged as sick (i.e., 'vcl_backend_fetch').

    # Try to retry the backend request. If possible (i.e., retries are available,
    # etc.) this will jump to 'vcl_backend_fetch' and won't return.
    if (request.contains("X-Varnish-Bodyaccess-Method") ||
        (bereq.method != "PUT" && bereq.method != "POST")) {
        if (std.healthy(bereq.backend) &&
            bereq.retries < std.integer(config.get(request.get("X-Varnish-Route") + ":max-retries"), param.max_retries)) {
            std.log("Varnish: Trying to save backend request by retrying it");
            return (retry);
        }
    }
    std.log("Varnish: Saving backend request by retrying it is not possible");

    # If this is not a passed request, try to rearm the object using a stale
    # version. On success this subroutine won't return. Beware 'stale.exists()'
    # will return True only for 304 candidates (i.e., not for dying objects, for
    # HFMs, for HFPs, etc.).
    if (!bereq.uncacheable && stale.exists()) {
        # Update ad-hoc 'beresp-*' counters using status code of the stale
        # object to be revived. This needs to be done here because the
        # post-route logic won't be reached by revived objects.
        if (stale.get_status() >= 200 && stale.get_status() < 300) {
            counters.counter("beresp-2xx", 1, varnishstat=true);
        } elseif (stale.get_status() >= 300 && stale.get_status() < 400) {
            counters.counter("beresp-3xx", 1, varnishstat=true);
        } elseif (stale.get_status() >= 400 && stale.get_status() < 500) {
            counters.counter("beresp-4xx", 1, varnishstat=true);
        } elseif (stale.get_status() >= 500 && stale.get_status() < 600) {
            counters.counter("beresp-5xx", 1, varnishstat=true);
        }

        # We want to revive the stale object so that it can be served a bit
        # longer. Beware:
        #
        #   - In 'vcl_backend_response' we use 'beresp.keep' to denote the time
        #     after grace which it is acceptable to deliver an object at all.
        #
        #   - 'stale.get_header()' could be used here to let the backend side
        #     customize how long the stale object should be extended. A couple
        #     of static configuration values are probably good enough.
        #
        #   - 'stale.get_status()' could be used here to use a shorter TTL when
        #     reviving 5xx objects.
        #
        #   - Since we use 'revive()' and not 'rearm()', the total life time is
        #     limited to the TTL + grace + keep which was set when the object
        #     was originally inserted during 'vcl_backend_response'.
        stale.revive(
            std.duration(
                config.get(request.get("X-Varnish-Route") + ":stale-revive-ttl"),
                10s),
            std.duration(
                config.get(request.get("X-Varnish-Route") + ":stale-revive-grace"),
                1m));

        # We need to explicitly deliver the stale object to the waiting client.
        # If we are in a bgfetch, this is a 'no op'.
        stale.deliver();

        # XXX: it's not possible to add debug headers to the revived object here
        # (useful to easily identify revived responses). Only the TTL, grace and
        # keep can be changed; the object is otherwise immutable after
        # insertion.

        # Done!
        std.log("Varnish: Saved backend request by reviving a stale object");
        return (abandon);
    }
    std.log("Varnish: Saving backend request by reviving a stale object is not possible");
}
