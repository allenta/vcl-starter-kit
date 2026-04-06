# The location of the following 'vcl_recv' & 'vcl_backend_fetch' subroutines
# just before and just after the VHA include is intentional to achieve the
# desired effect.

sub vcl_recv {
    # Use a filesystem marker to disable VHA replication dynamically. Unlike
    # replacing the 'vha6/vha_auto.vcl' include with 'vha6/vha_disable.vcl',
    # which requires a VCL reload, this approach takes effect immediately.
    if (req.method ~ "^VHA" &&
        std.file_exists("/etc/varnish/disabled-VHA-replication")) {
        return (synth(503, "VHA replication disabled"));
    }
}

include "vha6/vha_auto.vcl";

sub vcl_backend_fetch {
    # Use a filesystem marker or the 'X-Varnish-Vha-Forbid-Replication' marker
    # header to disable VHA replication. See above for details.
    if (bereq.http.X-Varnish-Vha-Forbid-Replication ||
        std.file_exists("/etc/varnish/disabled-VHA-replication")) {
        vha6_request.set("skip", "true");
        unset bereq.http.X-Varnish-Vha-Forbid-Replication;
    }
}

sub vcl_init {
    # TODO: adjust to your needs, specially the authentication token.
    vha6_opts.set("token", "s3cr3t"); # TODO: change me!
    vha6_opts.set("broadcaster_scheme", "http");
    vha6_opts.set("broadcaster_host", "localhost");
    vha6_opts.set("broadcaster_port", "8088");
    vha6_opts.set("broadcaster_group", "all");
    vha6_opts.set("origin_scheme", "");
    vha6_opts.set("token_ttl", "2m");
    vha6_opts.set("min_ttl", "3s");
    vha6_opts.set("min_grace", "10s");
    vha6_opts.set("broadcast_rate_limit", "75");
    vha6_opts.set("broadcast_limit", "75"); # = broadcast_rate_limit
    vha6_opts.set("request_rate_limit", "300"); # = (N-1) * 2 * broadcast_rate_limit
    vha6_opts.set("max_bytes", "25000000");
    vha6_opts.set("origin_backend_linger", "1h");
    call vha6_token_init;
}

sub vcl_recv {
    # Execute one-time initializations.
    if (req.restarts == 0) {
        # Ensure the marker header to disable VHA replication cannot be injected
        # from the outside.
        unset req.http.X-Varnish-Vha-Forbid-Replication;

        # Ensure injections of self-routing cluster headers used internally when
        # that strategy is not in use are not possible. It's important because
        # the top-level logic uses it to skip certain processing steps for
        # internal self-routed cluster requests.
        unset req.http.X-Cluster-Token;
    }
}
