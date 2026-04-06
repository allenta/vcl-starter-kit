# The location of the following 'vcl_recv' & 'vcl_backend_fetch' subroutines
# just before the Cluster include is intentional to achieve the desired effect.

sub vcl_recv {
    # Execute one-time initializations.
    if (req.restarts == 0) {
        # Beware at this point 'X-Cluster-Token' hasn't been validated yet. A
        # request looking like coming from a peer but with an invalid token will
        # still be tagged as such. This is only relevant for logging purposes.
        if (req.http.X-Cluster-Token) {
            std.log("Cluster-Origin:peer");
        } else {
            std.log("Cluster-Origin:client");
        }
    }
}

sub vcl_backend_fetch {
    # Execute one-time initializations.
    if (bereq.retries == 0) {
        if (bereq.http.X-Cluster-Token) {
            std.log("Cluster-Origin:peer");
        } else {
            std.log("Cluster-Origin:client");
        }
    }
}

include "cluster.vcl";

import nodes;

probe cluster_template_probe {
    .url = "/cluster-health-check/";
    .timeout = 1s;
    .interval = 5s;
    .initial = 3;
    .window = 5;
    .threshold = 3;
}

# TODO: cluster discovery is based on a '/etc/varnish/nodes.conf' file. You
# might want to adjust the backend template to fit your needs: timeouts, TLS
# settings, etc.
backend cluster_template_be {
    .host = "0.0.0.0"; # Placeholder to keep the VCL compiler happy.
    .connect_timeout = 1s;
    .first_byte_timeout = 20s;
    .between_bytes_timeout = 20s;
    .last_byte_timeout = 60s;
}

sub vcl_init {
    # TODO: adjust to your needs, specially the authentication token.

    nodes.set_default_probe_template(cluster_template_probe);
    nodes.set_default_backend_template(cluster_template_be);
    new nodes_conf = nodes.config_group("/etc/varnish/nodes.conf");
    cluster.subscribe(nodes_conf.get_tag());

    cluster_opts.set("token", "s3cr3t"); # TODO: change me!
    cluster_opts.set("fallback", "0");
    cluster_opts.set("primaries", "1");
    cluster_opts.set("trace", "true"); # Clean up handled by debug mode.
}

sub vcl_recv {
    # Simple health-check URL for self-routing cluster nodes.
    if (req.method == "GET" && req.url == "/cluster-health-check/") {
        if (std.file_exists("/etc/varnish/disabled-cluster")) {
            return (synth(503, "Cluster disabled"));
        } else {
            return (synth(200, "OK"));
        }
    }

    # Use a filesystem marker to disable auto-sharding (i.e., go directly to the
    # origin in case of a cache MISS). Same marker is also used to fail the
    # internal health-checks used by other peers, that will stop them to route
    # requests to this node (see above).
    if (std.file_exists("/etc/varnish/disabled-cluster")) {
        set req.http.X-Cluster-Skip = "true";
    }

    # Workaround for cacheable PUT & POST requests downgraded to GET during
    # self-routing. The symmetric logic in 'v_b_f' in the top-level logic is not
    # reached during self-routing, so we need to execute the method restoration
    # when the self-routed request reaches the origin.
    if (req.http.X-Cluster-Token && req.http.X-Varnish-Bodyaccess-Method) {
        set req.method = req.http.X-Varnish-Bodyaccess-Method;
    }
}

sub vcl_backend_response {
    # TODO: adjust to your needs.

    # # Decide storage sharding strategy: full replication (default) vs. full
    # # sharding vs. partial sharding. With the following logic objects will be
    # # ephemeral on all but the primary node (i.e., full sharding).
    # if (bereq.backend == cluster.backend() && !cluster.self_is_next(1)) {
    #     mse4.set_storage(EPHEMERAL);
    # }
}
