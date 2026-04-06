import prng;

# TODO: customize this for your needs.

sub vcl_recv {
    # Akamai SureRoute handling. Self-routed cluster requests need to skip this.
    unset req.http.X-Varnish-Akamai-Sureroute;
    if (!req.http.X-Cluster-Token) {
        if (req.url == "/akamai/testobject.html" || req.url == "/akamai/sureroute-test-object.html") {
            set req.http.X-Varnish-Akamai-Sureroute = "1";
            set req.http.X-Varnish-Vha-Forbid-Replication = "1";
            set req.http.X-Cluster-Skip = "true";
            unset req.http.Cookie;
            unset req.http.Authorization;
            return (hash);
        }
    }
}

sub vcl_deliver {
    # Self-routed cluster requests need to skip this.
    if (!req.http.X-Cluster-Token) {
        # Check if the request came through Akamai.
        if (req.http.Via ~ "akamai.net\(ghost\) \(AkamaiGHost\)") {
            # Prepare to modify response headers for Akamai.
            headerplus.init(resp);

            # Remove 'Age' and 'Expires' headers, and update 'Edge-Control' &
            # 'Cache-Control'. The objective is to ensure Akamai's cache TTL
            # does not exceed the maximum remaining lifetime of the object in
            # the origin shield, regardless of forced cache times, object
            # reviving, etc.
            headerplus.delete("Age");
            headerplus.delete("Expires");
            if (obj.uncacheable) {
                headerplus.attr_set("Edge-Control", "no-store");
                headerplus.attr_delete("Edge-Control", "max-age");
                headerplus.attr_delete("Edge-Control", "s-maxage");

                headerplus.attr_set("Cache-Control", "no-store");
                headerplus.attr_delete("Cache-Control", "max-age");
                headerplus.attr_delete("Cache-Control", "s-maxage");
            } else {
                headerplus.attr_set(
                    "Edge-Control",
                    "max-age=" + std.real2integer(std.real(obj.ttl + obj.grace, 0), 0));
                headerplus.attr_delete("Edge-Control", "s-maxage");

                headerplus.attr_set(
                    "Cache-Control",
                    "max-age=" + std.real2integer(std.real(obj.ttl + obj.grace, 0), 0));
                headerplus.attr_delete("Cache-Control", "s-maxage");
            }

            # Disable ESI processing and adjust 'Edge-Control' if the response
            # contains ESI fragments.
            set resp.do_esi = false;
            if (obj.can_esi) {
                headerplus.attr_set("Edge-Control", "dca=esi");
            }

            # Adjust 'Vary' header;  drop it, or keep it but only with
            # 'Accept-Encoding', which is a special case that Akamai understands.
            if (!resp.http.Vary || resp.http.Vary ~ "(?i)^Accept-Encoding$") {
                # Do nothing.
            } else if (resp.http.Vary ~ "(?i)Accept-Encoding") {
                headerplus.set("X-Varnish-Vary", resp.http.Vary);
                headerplus.set("Vary", "Accept-Encoding");
            } else {
                headerplus.set("X-Varnish-Vary", resp.http.Vary);
                headerplus.delete("Vary");
            }

            # Apply enqueued header modifications.
            headerplus.write();
        }
    }
}

sub vcl_backend_fetch {
    # Akamai SureRoute handling.
    if (bereq.http.X-Varnish-Akamai-Sureroute) {
        set bereq.backend = prng.zeros_backend(20480);
        return (fetch);
    }
}

sub vcl_backend_response {
    # Akamai SureRoute handling.
    if (bereq.http.X-Varnish-Akamai-Sureroute) {
        set beresp.ttl = 5m;
        set beresp.grace = 0s;
        set beresp.keep = 0s;
        return (deliver);
    }
}
