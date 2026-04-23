##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

sub vcl_init {
    # Internal settings.
    call init_global_config;

    # Default director, potentially useful across multiple routes.
    # TODO: adjust to your needs, or remove it a global director is not needed.
    new default_dns_group = activedns.dns_group(environment.get("default-be"));
    default_dns_group.set_ttl(10s);
    default_dns_group.set_ttl_rule(abide);
    default_dns_group.set_update_rule(ignore_empty);
    if (environment.get("id") != "local") {
        default_dns_group.set_probe_template(default_template_probe);
    }
    default_dns_group.set_backend_template(default_template_be);

    new default_dir = udo.director(random);
    default_dir.subscribe(default_dns_group.get_tag());

    # Request scoped kvstore to use for task-specific data. Mostly useful to
    # track state in backend tasks.
    new request = kvstore.init(scope=REQUEST);

    # Ad-hoc counters:
    #   - Beware object name is important.
    #   - Explicit declaration of counters is not needed, but it's nice so they
    #     show up in 'varnishstat' from the beginning.
    #   - The accounting VMOD (already integrated in this VCL) is a much more
    #     powerful alternative to these ad-hoc 'resp-*' and 'beresp-*' counters,
    #     which are here mostly for demonstration purposes.
    new counters = kvstore.init();
    counters.counter("resp-2xx", 0, varnishstat=true);
    counters.counter("resp-3xx", 0, varnishstat=true);
    counters.counter("resp-4xx", 0, varnishstat=true);
    counters.counter("resp-5xx", 0, varnishstat=true);
    counters.counter("beresp-2xx", 0, varnishstat=true);
    counters.counter("beresp-3xx", 0, varnishstat=true);
    counters.counter("beresp-4xx", 0, varnishstat=true);
    counters.counter("beresp-5xx", 0, varnishstat=true);
}

#
# All global internal settings are documented and initialized here.
#
sub init_global_config {
    # Initialize the internal configuration store.
    new config = kvstore.init();

    # Global settings would go here. For now all settings are route-specific
    # for extra flexibility.
}

#
# This helper should be called from 'vcl_init' by each route in order to set
# default values for all its route-specific settings. Those are stored in the
# internal configuration store defined in 'init_global_config', namespaced using
# the name of the route. After calling this helper, each route might override
# any of these options, as well as define additional ones.
#
# Input:
#   - config.get("route")
#
sub init_route_config {
    # Fail if no route name has been provided.
    if (config.get("route") == "") {
        std.syslog(3, "Trying to initialize route configuration without a route name!");
        return (fail);
    }

    # Create an accounting namespace for the route.
    accounting.create_namespace(config.get("route"));

    # TODO: adjust the default values of these settings to your needs, as well
    # as add any additional settings you might need.

    # Passthrough mode toggle (boolean). When enabled, all requests will be
    # handled as uncacheable by the top-level VCL logic (i.e.,
    # 'req.http.X-Varnish-Uncacheable' will be implicitly enabled). Additionally,
    # this flag can be used in route-specific VCL logic to conditionally bypass
    # manipulations such as query string normalization, cookie stripping, etc.
    config.set(
        config.get("route") + ":passthrough-enabled",
        "0");

    # Debug mode toggle (boolean). When enabled, responses to requests from
    # IPs matching 'send_debug_acl' will include additional debugging headers.
    config.set(
        config.get("route") + ":debug-enabled",
        "1");

    # Force HTTPS redirecting all HTTP requests (boolean). When enabled,
    # non-HTTPS requests will be redirected to HTTPS URLs, unless the client IP
    # matches 'can_bypass_https_acl'.
    config.set(
        config.get("route") + ":force-https",
        "0");

    # Maximum size of request bodies that may be cached for PUT & POST requests
    # (string valid for 'std.bytes()').
    config.set(
        config.get("route") + ":max-cacheable-body-size",
        "64KB");

    # Maximum object lifetime (duration). Leave empty to disable the upper limit.
    config.set(
        config.get("route") + ":max-object-lifetime",
        "");

    # Shared secret used to authorize incoming invalidation requests (string).
    # Leave empty to disable the authorization feature. Even when disabled, only
    # requests from IPs matching 'can_invalidate_acl' will be allowed.
    config.set(
        config.get("route") + ":invalidation-secret",
        "");

    # Ykeys namespace (string).
    config.set(
        config.get("route") + ":ykeys-namespace",
        "");

    # Prefix to be added to all ban expressions submitted using the BAN HTTP
    # method (valid ban expression).
    config.set(
        config.get("route") + ":bans-prefix",
        "obj.status != 0");

    # Maximum number of times a request to the backend may be retried before
    # giving up in case of errors or unexpected responses (integer). This value
    # will be upper-limited by the 'max_retries' parameter.
    config.set(
        config.get("route") + ":max-retries",
        "1");

    # TTL and grace used when reviving stale objects (duration).
    config.set(
        config.get("route") + ":stale-revive-ttl",
        "10s");
    config.set(
        config.get("route") + ":stale-revive-grace",
        "1m");

    # List of synthetic HTTP status codes handled by the route's 'vcl_synth'
    # subroutine (comma-separated string with a trailing comma and no spaces).
    # Anything not listed here will be handled by the top-level VCL logic if (1)
    # below 600; or (2) it's a known reserved synth status code (e.g., 701 for
    # 301 redirects, etc.).
    config.set(
        config.get("route") + ":synth-status-codes",
        "503,");

    # Clean up the route name to avoid side effects.
    config.delete("route");
}
