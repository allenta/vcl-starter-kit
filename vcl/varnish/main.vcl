##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

###############################################################################
## PREAMBLE
###############################################################################

include "varnish/acls.vcl";
include "varnish/config.vcl";

###############################################################################
## vcl_recv
###############################################################################

sub vcl_recv {
    if (req.http.X-Varnish-Route == "varnish") {
        # Stats URLs.
        if (req.url ~ "^/varnish/stats/(?:json|prometheus)/(?:\?.*)?$") {
            # Check ACL.
            if (std.ip(req.http.X-Client-Ip, "0.0.0.0") !~ varnish_stats_acl) {
                return (synth(403, "Not allowed"));
            }

            # Check method.
            if (req.method != "GET") {
                return (synth(405, "Method not allowed"));
            }

            # Don't cache statistics.
            set req.http.X-Varnish-Uncacheable = "1";

            # Ensure these requests are never self-routed (already guaranteed if
            # uncacheable; see above), but it's better to be explicit.
            set req.http.X-Cluster-Skip = "true";

        # Flush URL.
        } elsif (req.url == "/varnish/flush/") {
            # Check ACL.
            if (std.ip(req.http.X-Client-Ip, "0.0.0.0") !~ varnish_flush_acl) {
                return (synth(403, "Not allowed"));
            }

            # Check method.
            if (req.method != "POST") {
                return (synth(405, "Method not allowed"));
            }

            # Completely flush the cache using a Ykey assigned to all objects.
            # Using a wildcard ban such as 'ban("obj.status != 0")' for lazy
            # flushing is another option, but it is less robust due to the
            # special VHA handling of bans (i.e., use 'vha.skip_ban()' to skip
            # their evaluation during replication).
            set req.http.X-Varnish-Npurged = ykey.purge_keys("varnish:everything");
            return (synth(200, "Cache flushed (" + req.http.X-Varnish-Npurged + ")"));

        # Unknown URLs.
        } else {
            return (synth(404, "Not found"));
        }
    }
}

###############################################################################
## vcl_backend_fetch
###############################################################################

sub vcl_backend_fetch {
    if (request.get("X-Varnish-Route") == "varnish") {
        if (bereq.url ~ "^/varnish/stats/") {
            # Parse filter (comma separated list of expressions; e.g. 'MAIN.*,VBE.*').
            set bereq.http.X-Varnish-Route-Stats-Filter = urlplus.query_get("filter", def="");

            # Set backend.
            if (bereq.url ~ "^/varnish/stats/prometheus/") {
                set bereq.backend = stat.backend_prometheus(
                    bereq.http.X-Varnish-Route-Stats-Filter,
                    hostnames=false,
                    resolution=50);
                stat.add_filter(vcl);
            } else {
                set bereq.backend = stat.backend_json(
                    bereq.http.X-Varnish-Route-Stats-Filter);
            }

            # Clean up internal headers.
            unset bereq.http.X-Varnish-Route-Stats-Filter;
        }
    }
}
