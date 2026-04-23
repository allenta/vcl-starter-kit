##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##
## Please, check out the following links for a better understanding of all the
## logic included here:
##
##   - https://docs.varnish-software.com/varnish-enterprise/
##   - https://docs.varnish-software.com/book/
##   - https://www.varnish-software.com/developers/tutorials/
##   - https://www.varnish.org/docs/index.html
##   - varnishd -x builtin
##
## Reserved synth codes:
##
##   - 701: HTTP 301 redirection.
##   - 702: HTTP 302 redirection.
##   - 703: HTTP 503 for maintenance mode.
##
## Invalidation methods, optionally protected using 'X-Timestamp' + 'X-Signature'
## headers:
##
##   - Purges:
##     - HEAD/GET/PUT/POST/PURGE method.
##     - 'X-Purge' marker header (implicit for PURGE method).
##     - 'X-Refresh' marker header (optional).
##
##   - Soft purges:
##     - HEAD/GET/PUT/POST/PURGE method.
##     - 'X-Soft-Purge' marker header.
##     - 'X-Refresh' marker header (optional).
##
##   - Ykeys:
##     - HEAD/GET/PUT/POST/PURGE method.
##     - 'X-Ykeys' header (comma separated list of keys).
##
##   - Soft Ykeys:
##     - HEAD/GET/PUT/POST/PURGE method.
##     - 'X-Soft-Ykeys' header (comma separated list of keys).
##
##   - Bans:
##     - HEAD/GET/PUT/POST/BAN method.
##     - 'X-Ban' header (ban expression; defaults to current URL for BAN method).
##
##   - Forced cache misses:
##     - HEAD/GET/PUT/POST/REFRESH method.
##     - 'X-Forced-Miss' marker header (implicit for REFRESH method).
##
## Basic cheat sheet:
##
##   - varnishd -C -p "vcl_path=$PWD:/usr/share/varnish-plus/vcl" -f main.vcl
##
##   - '/etc/varnish/maintenance' marker file enables maintenance mode. It
##     controls the response to 'GET /health-check/', used for upper layer
##     health-checks.
##
##   - Boolean values in the 'config' object are modeled as '1' (true) and '0'
##     (false) strings. However, marker headers use any value (usually '1') to
##     indicate true, and absence of the header to indicate false. In particular,
##     a marker header with value '0' is considered true.
##
##   - 'X-Varnish-Uncacheable' marker header can be used in the client side to
##     enforce uncacheable (i.e., passed) requests. Beware presence of an
##     incoming 'Cookie' won't make the request uncacheable by default. If
##     that's needed, 'X-Varnish-Uncacheable' must be set explicitly.
##
##   - 'X-Varnish-Hash-Url' and 'X-Varnish-Hash-Host' headers can be used to
##     control the URL and 'Host' values used for caching key generation. This
##     is a dangerous pattern that should be used with caution.
##
##   - 'X-Varnish-Uncacheable' header can be used in the backend side to enforce
##     creation of HFM ('hfm' value) or HFP ('hfp' value) marker objects.
##
##   - Additional headers can be used to control caching behavior in the backend
##     side:
##     - 'X-Varnish-Ttl'.
##     - 'X-Varnish-Stale-While-Revalidate'.
##     - 'X-Varnish-Stale-If-Error'.
##     - 'X-Varnish-Esi'.
##     - 'X-Varnish-Ykeys'.
##
##   - If using VHA as replication strategy:
##     - '/etc/varnish/disabled-VHA-replication' marker file disables VHA
##       replication: stops submitting requests to the local broadcaster, and
##       makes the node reject replication requests coming from other peers.
##     - The 'X-Varnish-Vha-Forbid-Replication' marker header can be used to
##       disable VHA replication on a per-request basis. If a different
##       replication strategy is in use, this header will have no effect.
##     - Unlike self-routing cluster replication, VHA replication requests
##       cannot reach the top-level logic, so no need for any mechanism to
##       identify internal VHA replication requests and bypass certain
##       processing steps.
##     - Cache invalidations require two serialized rounds.
##
##   - If using a self-routing cluster as replication strategy:
##     - '/etc/varnish/disabled-cluster' marker file disables cluster behavior.
##       It controls the response to 'GET /cluster-health-check/', used by peers
##       in the self-routing cluster for internal health-checks. It also sets
##       'X-Cluster-Skip' on every incoming request, effectively disabling
##       auto-sharding.
##     - 'X-Cluster-Skip' boolean header can be used (when set to 'true') to
##       skip auto-sharding and go directly to the origin in case of a cache
##       MISS. If a different replication strategy is in use, this header will
##       have no effect.
##     - 'X-Cluster-Skip-Accounting' boolean header can be used (when set to
##       'true') to mark the request to skip receiving accounting keys. If a
##       different replication strategy is in use, this header will have no
##       effect.
##     - 'X-Cluster-Token' header can be used to skip logic that should not be
##       applied to internal self-routed cluster requests. If a different
##       replication strategy is in use, is guaranteed that this header will
##       never be present.
##     - Cache invalidations require two serialized rounds.
##

vcl 4.1;

# This is the top-level logic, providing a foundation shared by all routes. It's
# acceptable to extend and parametrize this as much as needed, but it's very
# important to keep it route-agnostic.

###############################################################################
## PREAMBLE
###############################################################################

import accounting;
import activedns;
import blob;
import bodyaccess;
import cookieplus;
import digest;
import headerplus;
import kvstore;
import mse4;
import purge;
import stale;
import stat;
import std;
import str;
import udo;
import urlplus;
import utils;
import ykey;

# The location of the following 'vcl_recv' & 'vcl_backend_fetch' subroutines
# just before any other logic is intentional to achieve the desired effect.

sub vcl_recv {
    # Execute one-time initializations.
    if (req.restarts == 0) {
        # Extract the real client IP to 'X-Client-Ip' (used for logging, ACL
        # checks, etc.) as soon as possible, even for VHA requests. This is
        # useful for having the complete picture in NCSA logs. Some examples:
        #
        #   - Akamai:
        #     if (req.http.True-Client-Ip) {
        #         set req.http.X-Client-Ip = req.http.True-Client-Ip;
        #     } else {
        #         set req.http.X-Client-Ip = client.ip;
        #     }
        #
        #   - AWS CLB (without PROXY protocol) / ELB:
        #     if (req.http.X-Forwarded-For ~ ",") {
        #         set req.http.X-Client-Ip = regsub(
        #             req.http.X-Forwarded-For,
        #             "^.*(?:^|,)\s*([^,\s]+)\s*,[^,]+$", "\1");
        #     } else {
        #         set req.http.X-Client-Ip = client.ip;
        #     }
        #
        #   - Fastly:
        #     if (req.http.Fastly-Client-Ip) {
        #         set req.http.X-Client-Ip = req.http.Fastly-Client-Ip;
        #     } else {
        #         set req.http.X-Client-Ip = client.ip;
        #     }
        #
        #   - Raw XFF (beware of XFF unreliability!):
        #     set req.http.X-Client-Ip = regsub(req.http.X-Forwarded-For, ",.*$", "");
        #
        # Beware self-routed cluster requests will override this value later
        # (at this point is too early to reliably detect them).
        #
        # TODO: adjust this logic as needed for your setup. Keep in mind
        # 'X-Client-Ip' is used in security-critical checks that depend on
        # correct IP extraction (e.g., invalidation ACL checks, etc.).
        set req.http.X-Client-Ip = client.ip;

        # Log server name to VSL. Same reason as above: NCSA logs.
        std.log("Server:" + server.hostname);
    }
}

sub vcl_backend_fetch {
    # Execute one-time initializations.
    if (bereq.retries == 0) {
        # Log server name to VSL. Same reason as above: NCSA logs.
        std.log("Server:" + server.hostname);
    }
}

include "environment.vcl";

# TODO: choose the replication strategy that best fits your needs. Only one of
# the following should be included at a time.
include "replication-disabled.vcl";
# include "replication-vha.vcl";
# include "replication-cluster.vcl";

# TODO: if integrating with Akamai, uncomment the following line.
# include "akamai.vcl";

include "acls.vcl";
include "backends.vcl";
include "config.vcl";
include "helpers.vcl";

###############################################################################
## PRE-ROUTE SUBROUTINES
###############################################################################

sub recv_clean_req_headers {
    # Some headers must be cleaned up only when the incoming client request
    # arrives for the first time.
    if (req.restarts == 0) {
        unset req.http.X-Varnish-Route;
        unset req.http.X-Varnish-Debug;
    }

    # Clean up all 'X-Varnish-*' headers except the previously mentioned ones.
    headerplus.init(req);
    headerplus.delete_regex("^X-Varnish-(?!Route|Debug)");
    headerplus.write();
}

#
# Output:
#   - req.http.X-Varnish-Route (optional)
#
sub recv_decide_route {
    if (req.url ~ "^/varnish/") {
        set req.http.X-Varnish-Route = "varnish";
    # TODO: add your routing logic here. Some examples:
    #   - req.http.Host ~ "(?i)^www\.foo\.org$"
    #   - req.http.Host ~ "(?i)^(?:|(?:www|media)\.)foo\.es$"
    #   - req.http.Host ~ "(?i)^(?:css|js|img)\.(?:foo\.es|bar\.com)$"
    } elsif (req.http.Host ~ "(?i)^.*$") {
        set req.http.X-Varnish-Route = "foo";
    }
}

#
# Input:
#   - req.http.X-Varnish-Route
#
sub recv_execute_route_preflight {
    # Use the route name as the accounting namespace. Note that:
    #   - Although this is executed very early in request processing, some
    #     requests may still bypass it (e.g., self-routed cluster requests
    #     with an invalid token, unknown routes, etc.).
    #   - The namespace can only be set once per request and full scope is
    #     intentionally used.
    #   - The namespace must be created during 'vcl_init'. Otherwise, the
    #     request will fail.
    if (req.esi_level == 0) {
        accounting.set_namespace(req.http.X-Varnish-Route);
    }

    # Reset backend selection. This helps prevent bugs when the default backend
    # is unexpectedly used.
    set req.backend_hint = nil_be;

    # Enable debug mode?
    if (config.get(req.http.X-Varnish-Route + ":debug-enabled") == "1" &&
        std.ip(req.http.X-Client-Ip, "0.0.0.0") ~ send_debug_acl) {
        set req.http.X-Varnish-Debug = "1";
    }

    # Normalize invalidation methods.
    if (req.method == "PURGE") {
        if (!req.http.X-Soft-Purge && !req.http.X-Ykeys && !req.http.X-Soft-Ykeys) {
            set req.http.X-Purge = "1";
        }
        set req.method = "GET";
    } elsif (req.method == "BAN") {
        if (!req.http.X-Ban) {
            set req.http.X-Ban =
                "obj.http.X-Host == " + req.http.Host + " && " +
                "obj.http.X-Url == " + req.url;
        }
        set req.method = "GET";
    } elsif (req.method == "REFRESH") {
        set req.http.X-Forced-Miss = "1";
        set req.method = "GET";
    }

    # Enable invalidation mode?
    if ((req.method == "HEAD" || req.method == "GET" || req.method == "PUT" ||
        req.method == "POST") &&
        (req.http.X-Purge || req.http.X-Soft-Purge || req.http.X-Ykeys ||
        req.http.X-Soft-Ykeys || req.http.X-Ban || req.http.X-Forced-Miss) &&
        std.ip(req.http.X-Client-Ip, "0.0.0.0") ~ can_invalidate_acl) {
        set req.http.X-Varnish-Invalidation = "1";
    }
}

sub vcl_recv {
    # Log VCS global key 'ALL'.
    std.log("vcs-key:ALL");

    # Simple health-check URL for upper layer.
    if (req.method == "GET" && req.url == "/health-check/") {
        if (std.file_exists("/etc/varnish/maintenance")) {
            return (synth(703));
        } else {
            return (synth(200, "OK"));
        }
    }

    # Override previously extracted client IP for internal self-routed cluster
    # requests.
    if (req.http.X-Cluster-Token) {
        set req.http.X-Client-Ip = client.ip;
    }

    # Block blacklisted IPs.
    if (std.ip(req.http.X-Client-Ip, "0.0.0.0") ~ is_blacklisted_acl) {
        return (synth(403, "Forbidden"));
    }

    # Clean up incoming headers internally used during VCL processing.
    call recv_clean_req_headers;

    # Set 'X-Is-Https' header. Some examples:
    #
    #   - AWS CLB (without PROXY protocol) / ELB:
    #     if (req.http.X-Forwarded-Proto == "https") {
    #         set req.http.X-Is-Https = "1";
    #     } else {
    #         unset req.http.X-Is-Https;
    #     }
    #
    #   - PROXY protocol + proxy VMOD:
    #     if (proxy.is_ssl()) {
    #         set req.http.X-Is-Https = "1";
    #     } else {
    #         unset req.http.X-Is-Https;
    #     }
    #
    #   - Built-in TLS + tls VMOD:
    #     if (tls.is_tls()) {
    #         set req.http.X-Is-Https = "1";
    #     } else {
    #         unset req.http.X-Is-Https;
    #     }
    #
    # TODO: adjust the logic as needed to fit your setup.
    if (std.port(server.ip) == 443) {
        set req.http.X-Is-Https = "1";
    } else {
        unset req.http.X-Is-Https;
    }

    # Set 'X-Varnish-Esi-Level' header. Useful to simplify VSL filtering, and
    # also to have the information available in the backend side (e.g., useful
    # for throttling, etc.).
    set req.http.X-Varnish-Esi-Level = req.esi_level;

    # Execute several one-time normalizations & initializations.
    if (req.restarts == 0) {
        # Normalize host header converting to lowercase.
        set req.http.Host = std.tolower(req.http.Host);

        # Normalize host header dropping port number.
        if (req.http.Host ~ ":\d+$") {
            set req.http.Host = regsub(req.http.Host, ":\d+$", "");
        }

        # Repair weird requests containing full URLs in the HTTP payload.
        if (req.url ~ "(?i)^https?://") {
            set req.http.Host = regsub(req.url, "(?i)^https?://([^/]*).*", "\1");
            set req.url = regsub(req.url, "(?i)^https?://[^/]*/?(.*)$", "/\1");
            set req.http.X-Varnish-Vha-Forbid-Replication = "1";
        }

        # Decide the route to be used. This will set 'X-Varnish-Route', or
        # leave it unset if no route matches.
        call recv_decide_route;

        # If a route was found, execute preflight tasks required by all routes.
        if (req.http.X-Varnish-Route) {
            call recv_execute_route_preflight;
        }
    }
}

sub vcl_hit {
    # Set cache debug header.
    set req.http.X-Varnish-Debug-Cache = "hit";
}

sub vcl_miss {
    # Set cache debug header.
    set req.http.X-Varnish-Debug-Cache = "miss";
}

sub vcl_pass {
    # Set cache debug header.
    set req.http.X-Varnish-Debug-Cache = "pass";
}

sub vcl_pipe {
    # Set cache debug header.
    set req.http.X-Varnish-Debug-Cache = "pipe uncacheable";

    # WebSocket upgrade? See:
    #   - https://github.com/varnish/varnish/blob/6.0/doc/sphinx/users-guide/vcl-example-websockets.rst.
    if (req.http.upgrade) {
        set bereq.http.upgrade = req.http.upgrade;
        set bereq.http.connection = req.http.connection;
    }

    return (pipe);
}

sub vcl_deliver {
    # When a stale object is not available, a short lived dummy object including
    # a marker header is cached in order to avoid request serialization (see
    # 'vcl_backend_error'). Now it's time to transform that into an
    # user-friendly error response. This transformation could be avoided caching
    # the synthetic user-friendly error response during 'vcl_backend_error' but
    # it's better to centralize crafting of synthetic responses in a single
    # place.
    if (resp.http.X-Varnish-Synthetic-Backend-Error) {
        return (synth(503, "Service unavailable"));
    }

    # Set cache debug header.
    if (obj.uncacheable) {
        set req.http.X-Varnish-Debug-Cache = req.http.X-Varnish-Debug-Cache + " uncacheable";
    } else {
        set req.http.X-Varnish-Debug-Cache = req.http.X-Varnish-Debug-Cache + " cached";
    }

    # Inject a copy of the 'Vary' header before pre-delivery cleanups, if in
    # debug mode and it's not an internal self-routed cluster request.
    if (req.http.X-Varnish-Debug && !req.http.X-Cluster-Token) {
        set resp.http.X-Varnish-Debug-Vary = resp.http.Vary;
    }
}

sub vcl_synth {
    # Set cache debug header.
    set req.http.X-Varnish-Debug-Cache = "synth synth";

    # Inject informational headers. These headers should be included in all
    # responses, reaching both the upstream CDN and the client. Beware of
    # disclosing sensitive information here.
    set resp.http.X-Varnish-Cache = req.http.X-Varnish-Debug-Cache;

    # Inject debug headers in the client response?
    if (req.http.X-Varnish-Debug) {
        # set resp.http.X-Varnish-Debug-Cache = req.http.X-Varnish-Debug-Cache;
    }

    # Treat resets as soon as possible (as in the built-in VCL): the client is
    # gone, no need to prepare a response that will not be delivered.
    if (req.is_reset) {
        return (deliver);
    }

    # Handle synthetic responses bellow 600 not reaching route's 'vcl_synth'
    # subroutine. Beware route might be unknown at this point.
    if (resp.status < 600 && (
        !req.http.X-Varnish-Route ||
        !str.contains(
            config.get(req.http.X-Varnish-Route + ":synth-status-codes"),
            resp.status + ","))) {
        call deliver_client_response;
    }

    # Handle known reserved synth status codes, unless they're handled in the
    # route-specific 'vcl_synth' subroutine. Beware route might be unknown at
    # this point.
    if (resp.status >= 700 && (
        !req.http.X-Varnish-Route ||
        !str.contains(
            config.get(req.http.X-Varnish-Route + ":synth-status-codes"),
            resp.status + ","))) {
        # 701 & 702: HTTP 301/302 redirection.
        if (resp.status == 701 || resp.status == 702) {
            set resp.http.Location = resp.reason;
            if (resp.status == 701) {
                set resp.status = 301;
                set resp.reason = "Moved permanently";
            } else {
                set resp.status = 302;
                set resp.reason = "Moved temporarily";
            }
            call deliver_client_response;
        }

        # 703: maintenance mode.
        if (resp.status == 703) {
            set resp.status = 503;
            set resp.reason = "Maintenance";
            call deliver_client_response;
        }
    }
}

sub backend_fetch_clean_bereq_headers {
    # To avoid sending internal headers to the backend, we populate the 'request'
    # kvstore with input from the client task and remove all 'X-Varnish-*'
    # headers from the backend request.
    if (bereq.retries == 0) {
        if (bereq.http.X-Varnish-Route) {
            request.set("X-Varnish-Route", bereq.http.X-Varnish-Route);
        } else {
            # This should never happen, but if it does, it's better to fail.
            return (fail);
        }

        if (bereq.http.X-Varnish-Esi-Level) {
            request.set("X-Varnish-Esi-Level", bereq.http.X-Varnish-Esi-Level);
        } else {
            # This should never happen, but if it does, it's better to fail.
            return (fail);
        }

        if (bereq.http.X-Varnish-Debug) {
            request.set("X-Varnish-Debug", "1");
        } else {
            request.set("X-Varnish-Debug", "0");
        }

        if (bereq.http.X-Varnish-Bodyaccess-Method) {
            request.set(
                "X-Varnish-Bodyaccess-Method",
                bereq.http.X-Varnish-Bodyaccess-Method);
        }

        headerplus.init(bereq);
        headerplus.delete_regex("^X-Varnish-");
        headerplus.write();
    }
}

sub vcl_backend_fetch {
    # Clean up headers previously generated during VCL processing and not
    # required in the outgoing backend request.
    call backend_fetch_clean_bereq_headers;

    # Announce ESI capability.
    set bereq.http.Surrogate-Capability = "key=ESI/1.0";

    # Ensure the backend gets the right method when caching PUT & POST requests.
    if (request.contains("X-Varnish-Bodyaccess-Method")) {
        set bereq.method = request.get("X-Varnish-Bodyaccess-Method");
    }
}

sub vcl_backend_response {
    # Initialize headerplus VMOD.
    headerplus.init(beresp);

    # Extract, validate and set TTL. Beware Varnish internally initialized
    # 'beresp.ttl' but 'X-Varnish-Ttl' has higher priority than all other
    # alternatives.
    if (beresp.http.X-Varnish-Ttl ~ "^\d{1,9}[smhdwy]?$") {
        if (beresp.http.X-Varnish-Ttl ~ "\d$") {
            set beresp.http.X-Varnish-Ttl = beresp.http.X-Varnish-Ttl + "s";
        }
        set beresp.ttl = std.duration(beresp.http.X-Varnish-Ttl, 0s);
    } else {
        unset beresp.http.X-Varnish-Ttl;
    }

    # Extract, validate and set grace (a.k.a. stale while revalidate or limited
    # grace). Beware Varnish internally initialized 'beresp.grace' but
    # 'X-Varnish-Stale-While-Revalidate' has higher priority than all other
    # alternatives.
    if (beresp.http.X-Varnish-Stale-While-Revalidate ~ "^\d{1,9}[smhdwy]?$") {
        if (beresp.http.X-Varnish-Stale-While-Revalidate ~ "\d$") {
            set beresp.http.X-Varnish-Stale-While-Revalidate =
                beresp.http.X-Varnish-Stale-While-Revalidate + "s";
        }
        set beresp.grace = std.duration(beresp.http.X-Varnish-Stale-While-Revalidate, 0s);
    } else {
        unset beresp.http.X-Varnish-Stale-While-Revalidate;
    }

    # Extract, validate and set keep (a.k.a stale if error or full grace).
    if (!beresp.http.X-Varnish-Stale-If-Error &&
        (headerplus.attr_get("Cache-Control", "stale-if-error") ~ "^\d+$")) {
        set beresp.http.X-Varnish-Stale-If-Error =
            headerplus.attr_get("Cache-Control", "stale-if-error");
    }
    if (beresp.http.X-Varnish-Stale-If-Error ~ "^\d{1,9}[smhdwy]?$") {
        if (beresp.http.X-Varnish-Stale-If-Error ~ "\d$") {
            set beresp.http.X-Varnish-Stale-If-Error =
                beresp.http.X-Varnish-Stale-If-Error + "s";
        }
        if (std.duration(beresp.http.X-Varnish-Stale-If-Error, 0s) > beresp.grace) {
            set beresp.keep =
                std.duration(beresp.http.X-Varnish-Stale-If-Error, 0s) -
                beresp.grace;
        } else {
            set beresp.keep = 0s;
        }
    } else {
        unset beresp.http.X-Varnish-Stale-If-Error;
    }

    # Validate & set uncacheable.
    if (beresp.http.X-Varnish-Uncacheable ~ "^(?:hfp|hfm)$") {
        set beresp.ttl = param.uncacheable_ttl;
        set beresp.uncacheable = true;
    } else {
        unset beresp.http.X-Varnish-Uncacheable;
    }

    # Validate & enable ESI.
    if (!beresp.http.X-Varnish-Esi && beresp.http.Surrogate-Control ~ "ESI/1.0") {
        set beresp.http.X-Varnish-Esi = "1";
    }
    if (beresp.http.X-Varnish-Esi == "1") {
        set beresp.do_esi = true;
    } else {
        unset beresp.http.X-Varnish-Esi;
    }
}

###############################################################################
## APW SUBROUTINES
###############################################################################

# TODO: if integrating with APW (Advanced Paywall by Allenta), uncomment and
# adjust the following block of code.
#
# include "apw.config.vcl";
#
# include "/opt/apw/vcls/apw/apw.vcl";
#
# sub vcl_init {
#     call apw_init;
# }
#
# sub vcl_recv {
#     unset req.http.X-Paywalled-Host;
#     if (!req.http.X-Cluster-Token &&
#         (req.http.Host ~ "(?i)^.*$" || req.url ~ "^/apw/api/.*$")) {
#         set req.http.X-Paywalled-Host = "1";
#         call apw_recv;
#     }
# }
#
# sub vcl_deliver {
#     if (req.http.X-Paywalled-Host) {
#         call apw_deliver;
#     }
# }
#
# sub vcl_synth {
#     if (req.http.X-Paywalled-Host) {
#         call apw_synth;
#     }
# }
#
# sub vcl_backend_fetch {
#     if (bereq.http.X-Paywalled-Host) {
#         call apw_backend_fetch;
#     }
# }
#
# sub vcl_backend_response {
#     if (bereq.http.X-Paywalled-Host) {
#         call apw_backend_response;
#     }
# }

###############################################################################
## ROUTE SUBROUTINES
###############################################################################

# TODO: add as many routes as needed. Order is not relevant.
include "foo/main.vcl";
include "varnish/main.vcl";

###############################################################################
## POST-ROUTE SUBROUTINES
###############################################################################

sub hit_miss_refresh_purged_object {
    # Clean up normal & soft purge headers.
    unset req.http.X-Purge;
    unset req.http.X-Soft-Purge;
    unset req.http.X-Refresh;

    # Restart the request.
    return (restart);
}

sub recv_handle_invalidation {
    # Is this an unauthorized invalidation request?
    if (config.get(req.http.X-Varnish-Route + ":invalidation-secret") != "" &&
        (std.time2integer(now, 0) - std.integer(req.http.X-Timestamp, 0) > 300 ||
         digest.hmac_sha256(
             config.get(req.http.X-Varnish-Route + ":invalidation-secret"),
             req.http.Host + req.url + req.http.X-Timestamp) != req.http.X-Signature)) {
        return (synth(403, "Not allowed"));
    }

    # Normal & soft purges.
    if (req.http.X-Purge || req.http.X-Soft-Purge) {
        return (hash);

    # Ykeys invalidations.
    } elsif (req.http.X-Ykeys) {
        ykey.namespace(config.get(req.http.X-Varnish-Route + ":ykeys-namespace"));
        set req.http.X-Varnish-Npurged = ykey.purge_header(req.http.X-Ykeys);
        return (synth(200, "Purged (" + req.http.X-Varnish-Npurged + ")"));

    # Soft Ykeys invalidations.
    } elsif (req.http.X-Soft-Ykeys) {
        ykey.namespace(config.get(req.http.X-Varnish-Route + ":ykeys-namespace"));
        set req.http.X-Varnish-Npurged = ykey.purge_header(req.http.X-Soft-Ykeys, soft=true);
        return (synth(200, "Soft purged (" + req.http.X-Varnish-Npurged + ")"));

    # Bans.
    } elsif (req.http.X-Ban) {
        # XXX: replace by 'std.ban()' & 'std.ban_error()' when possible.
        ban(config.get(req.http.X-Varnish-Route + ":bans-prefix") + " && " +
            req.http.X-Ban);
        return (synth(200, "Ban added"));

    # Forced cache misses.
    } elsif (req.http.X-Forced-Miss) {
        set req.hash_always_miss = true;

    # Other unsupported invalidation requests.
    } else {
        return (synth(400, "Bad invalidation request"));
    }
}

sub hit_miss_handle_invalidation {
    if (req.http.X-Purge) {
        set req.http.X-Varnish-Npurged = purge.hard();
        if (req.http.X-Refresh) {
            call hit_miss_refresh_purged_object;
        } else {
            return (synth(200, "Purged (" + req.http.X-Varnish-Npurged + ")"));
        }
    } elsif (req.http.X-Soft-Purge) {
        set req.http.X-Varnish-Npurged = purge.soft();
        if (req.http.X-Refresh) {
            call hit_miss_refresh_purged_object;
        } else {
            return (synth(200, "Soft purged (" + req.http.X-Varnish-Npurged + ")"));
        }
    }
}

sub vcl_recv {
    # A valid route was not found?
    if (!req.http.X-Varnish-Route) {
        return (synth(404, "Not found"));
    }

    # Should this request be using HTTPS and it's not? Beware self-routed cluster
    # requests are exempted from this check.
    if (!req.http.X-Cluster-Token &&
        !req.http.X-Is-Https &&
        std.ip(req.http.X-Client-Ip, "0.0.0.0") !~ can_bypass_https_acl &&
        config.get(req.http.X-Varnish-Route + ":force-https") == "1" &&
        !req.http.X-Varnish-Invalidation) {
        return (synth(701, "https://" + req.http.Host + req.url));
    }

    # Is this an invalidation request?
    if (req.http.X-Varnish-Invalidation) {
        call recv_handle_invalidation;
    }

    # SPDY or HTTP/2.0 is not supported.
    if (req.method == "PRI") {
        return (synth(405, "Not supported"));
    }

    # Non-RFC2616 or CONNECT?
    if (req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "DELETE" &&
        req.method != "PATCH") {
        return (pipe);
    }

    # WebSocket upgrade?
    if (req.http.Upgrade ~ "(?i)websocket") {
        return (pipe);
    }

    # Is this a uncacheable request? Beware presence of a 'Cookie' header won't
    # automatically make the request uncacheable (i.e., default built-in
    # behavior).
    if ((req.method != "GET" && req.method != "HEAD" &&
         req.method != "PUT" && req.method != "POST") ||
        req.http.Authorization ||
        req.http.X-Varnish-Uncacheable ||
        config.get(req.http.X-Varnish-Route + ":passthrough-enabled") == "1") {
        if (!req.http.X-Varnish-Uncacheable) {
            set req.http.X-Varnish-Uncacheable = "1";
        }
        return (pass);
    }

    # Get ready to cache PUT & POST requests.
    if (req.method == "PUT" || req.method == "POST") {
        std.cache_req_body(std.bytes(config.get(req.http.X-Varnish-Route + ":max-cacheable-body-size"), 32KB));
        if (bodyaccess.len_req_body() == -1) {
            # TODO: consider handling this case as an uncacheable request: set
            # set 'req.http.X-Varnish-Uncacheable' + pass.
            return (synth(413, "Request body size exceeds the caching limit"));
        } else {
            set req.http.X-Varnish-Bodyaccess-Method = req.method;
        }
    }

    # Perform lookup. Beware the previous logic mimics the built-in 'vcl_recv'
    # behavior, so it is safe to assume 'return (hash)' here.
    return (hash);
}

sub vcl_hash {
    # Extend the default hash to allow caching of PUT & POST requests. Note the
    # else branch to avoid obscure bugs that might result in two different
    # objects sharing the same caching key. Example:
    #   - Cacheable GET request for URL X executing 'hash_data("PUT")' and
    #     'hash_data("foo")' in its route-specific 'vcl_hash', both values
    #     extracted from incoming cookies.
    #   - Cacheable PUT request for URL X without 'hash_data()' executions in
    #     its route-specific 'vcl_hash' and a 'foo' body.
    if (req.http.X-Varnish-Bodyaccess-Method) {
        hash_data(req.http.X-Varnish-Bodyaccess-Method);
        bodyaccess.hash_req_body();
    } else {
        hash_data("");
        hash_data("");
    }

    # Mimic the built-in 'vcl_hash' behavior, providing flexibility for routes
    # to use alternative 'Host' and URL values when building the caching key.
    if (req.http.X-Varnish-Hash-Url) {
        hash_data(req.http.X-Varnish-Hash-Url);
    } else {
        hash_data(req.url);
    }
    if (req.http.X-Varnish-Hash-Host) {
        hash_data(req.http.X-Varnish-Hash-Host);
    } elsif (req.http.Host) {
        hash_data(req.http.Host);
    } else {
        hash_data(server.ip);
    }

    # No need to execute the built-in 'vcl_hash' logic.
    return (lookup);
}

sub vcl_hit {
    # Is this an invalidation request?
    if (req.http.X-Varnish-Invalidation) {
        call hit_miss_handle_invalidation;
    }
}

sub vcl_miss {
    # Is this an invalidation request?
    if (req.http.X-Varnish-Invalidation) {
        call hit_miss_handle_invalidation;
    }
}

sub vcl_deliver {
    # Remove incoming 'If-Modified-Since' and 'If-None-Match' headers in order
    # to avoid 304 responses for top-level requests containing ESI fragments (in
    # order to allow those fragments to be refreshed  properly in the client
    # side). Beware removing 'resp.http.Last-Modified' and 'resp.http.ETag'
    # headers won't work because Varnish uses internal copies of them to decide
    # when to send 304 responses.
    if (resp.http.X-Varnish-Esi && req.esi_level == 0) {
        unset req.http.If-Modified-Since;
        unset req.http.If-None-Match;
    }

    # Avoid delivering useless headers to clients or peers.
    unset resp.http.X-Host;
    unset resp.http.X-Url;

    # Unless this is a internal self-routed cluster request, clean up caching
    # control headers targeting the origin cache. Beware this is intentionally
    # done here (rather than in 'vcl_backend_response') (1) to ensure proper
    # handling of conditional backend requests that receive 304 responses; and
    # (2) to allow self-routed cluster requests to behave properly.
    if (!req.http.X-Cluster-Token) {
        unset resp.http.Surrogate-Control;
        if (resp.http.Cache-Control) {
            headerplus.init(resp);
            # TODO: 's-maxage' might be used by upstream CDNs; consider allowing
            # it to be preserved in the response.
            headerplus.attr_delete("Cache-Control", "s-maxage");
            headerplus.attr_delete("Cache-Control", "stale-while-revalidate");
            headerplus.attr_delete("Cache-Control", "stale-if-error");
            headerplus.write();
        }
    }

    # Unless this is a internal self-routed cluster request, inject informational
    # headers. These headers should be included in all responses, reaching both
    # the upstream CDN and the client. Beware of disclosing sensitive
    # information here.
    # TODO: extend the list of informational headers as needed.
    if (!req.http.X-Cluster-Token) {
        set resp.http.X-Varnish-Cache = req.http.X-Varnish-Debug-Cache;
        set resp.http.X-Varnish-Hash = blob.encode(BASE64URLNOPAD, blob=req.hash);
        set resp.http.X-Varnish-Hits = obj.hits;
    }

    # Clean up internal headers only if not in debug mode and it's not an
    # internal self-routed cluster request. In debug mode we want to preserve
    # them, but if not in debug mode, we need to ensure this headers are not
    # removed for self-routed cluster requests. Beware these headers are
    # intentionally removed here (rather than in 'vcl_backend_response') (1) to
    # ensure proper handling of conditional backend requests that receive 304
    # responses; and (2) to allow self-routed cluster requests to behave
    # properly.
    if (!req.http.X-Varnish-Debug && !req.http.X-Cluster-Token) {
        unset resp.http.X-Varnish-Ttl;
        unset resp.http.X-Varnish-Stale-While-Revalidate;
        unset resp.http.X-Varnish-Stale-If-Error;
        unset resp.http.X-Varnish-Uncacheable;
        unset resp.http.X-Varnish-Esi;
        unset resp.http.X-Varnish-Ykeys;
    }

    # Clean up already injected debug headers if not in debug mode or if this
    # is a internal self-routed cluster request.
    if (!req.http.X-Varnish-Debug || req.http.X-Cluster-Token) {
        unset resp.http.X-Varnish-Debug-Initial-Ttl;
        unset resp.http.X-Varnish-Debug-Initial-Grace;
        unset resp.http.X-Varnish-Debug-Initial-Keep;
        unset resp.http.X-Varnish-Debug-Backend;
        unset resp.http.X-Varnish-Debug-Storage;

        unset resp.http.vha6-origin;

        if (!req.http.X-Cluster-Token) {
            unset resp.http.X-Cluster-Trace;
        }
    }

    # Inject additional debug headers if in debug mode and it's not an internal
    # self-routed cluster request. Some of them are commented out because the
    # same info was previously unconditionally injected as informational headers.
    if (req.http.X-Varnish-Debug && !req.http.X-Cluster-Token) {
        # set resp.http.X-Varnish-Debug-Cache = req.http.X-Varnish-Debug-Cache;
        # set resp.http.X-Varnish-Debug-Hash = blob.encode(BASE64URLNOPAD, blob=req.hash);
        # set resp.http.X-Varnish-Debug-Hits = obj.hits; # 0 == miss.
        set resp.http.X-Varnish-Debug-Instance = server.hostname;
        set resp.http.X-Varnish-Debug-Ttl = obj.ttl; # Remaining TTL.
        set resp.http.X-Varnish-Debug-Grace = obj.grace; # Absolute grace.
        set resp.http.X-Varnish-Debug-Keep = obj.keep; # Absolute keep.
        set resp.http.X-Varnish-Debug-Age = obj.age;
    }

    # Done!
    call deliver_client_response;
}

sub vcl_synth {
    call deliver_client_response;
}

sub vcl_backend_fetch {
    # Note that in 'vcl_backend_response' we use 'beresp.grace' as the healthy /
    # limited grace (i.e., no need to use 'req.grace' during 'vcl_recv').
    # Therefore we can delay the backend healthiness check until
    # 'vcl_backend_fetch'. If sick we jump to 'vcl_backend_error' (in all cases,
    # passes included) and then rearm the object in there. This means we are
    # taking a trip to the backend context, but on the plus side (1) we don't
    # have to check healthiness on requests which are hits; and (2) we can
    # provide a reasonable 'stale-while-revalidate' and 'stale-if-error'
    # implementation. A trip to the backend thread is cheap as long as no new
    # connection is opened.
    #
    # Beware checking backend healthiness using 'std.healthy()' and explicitly
    # jumping to 'vcl_backend_error' if sick is not needed here. That's the
    # default Varnish behavior when a backend is tagged as sick.
}

sub vcl_backend_response {
    # Clean up internal marker.
    unset beresp.http.X-Varnish-Synthetic-Backend-Error;

    # Log backend name to VSL, useful for NCSA logs. We could also do this in
    # post-route 'vcl_backend_fetch', setting 'bereq.backend =
    # utils.resolve_backend(bereq.backend)' to force early backend resolution
    # and avoid logging a director name. We prefer this approach because it
    # keeps 'bereq.backend' untouched, which is handy for retries (see
    # 'std.healthy()' in 'save_backend_request') when using directors.
    std.log("Backend:" + beresp.backend);

    # Set backend debug header.
    set beresp.http.X-Varnish-Debug-Backend = beresp.backend;

    # Update ad-hoc 'beresp-*' counters. Beware revived objects and synthetic
    # backend responses won't reach this logic.
    if (beresp.status >= 200 && beresp.status < 300) {
        counters.counter("beresp-2xx", 1, varnishstat=true);
    } elsif (beresp.status >= 300 && beresp.status < 400) {
        counters.counter("beresp-3xx", 1, varnishstat=true);
    } elsif (beresp.status >= 400 && beresp.status < 500) {
        counters.counter("beresp-4xx", 1, varnishstat=true);
    } elsif (beresp.status >= 500 && beresp.status < 600) {
        counters.counter("beresp-5xx", 1, varnishstat=true);
    }

    # Skip passed (i.e., passed and hit-for-pass) requests.
    if (!bereq.uncacheable) {
        # A copy of the built-in logic is executed here to avoid overriding TTLs
        # of HFM & HFP objects after limiting the object lifetime in the next
        # code block.
        if (beresp.ttl <= 0s ||
            beresp.http.Set-Cookie ||
            beresp.http.Surrogate-Control ~ "(?i)no-store" ||
            (!beresp.http.Surrogate-Control &&
                beresp.http.Cache-Control ~ "(?i:no-cache|no-store|private)") ||
            beresp.http.Vary == "*") {
            # The object will be marked as HFM (default) or HFP (if requested)
            # for the next 2 minutes (default).
            set beresp.ttl = param.uncacheable_ttl;
            set beresp.uncacheable = true;
        }

        # Limit object's lifetime in cache, if the feature is enabled.
        set bereq.http.X-Varnish-Max-Object-Lifetime = config.get(request.get("X-Varnish-Route") + ":max-object-lifetime");
        if (bereq.http.X-Varnish-Max-Object-Lifetime != "") {
            if (beresp.ttl > std.duration(bereq.http.X-Varnish-Max-Object-Lifetime, 1h)) {
                set beresp.ttl = std.duration(bereq.http.X-Varnish-Max-Object-Lifetime, 1h);
                set beresp.grace = 0s;
                set beresp.keep = 0s;
            } elsif (beresp.ttl + beresp.grace > std.duration(bereq.http.X-Varnish-Max-Object-Lifetime, 1h)) {
                set beresp.grace =
                    std.duration(bereq.http.X-Varnish-Max-Object-Lifetime, 1h) -
                    beresp.ttl;
                set beresp.keep = 0s;
            } elsif (beresp.ttl + beresp.grace + beresp.keep > std.duration(bereq.http.X-Varnish-Max-Object-Lifetime, 1h)) {
                set beresp.keep =
                    std.duration(bereq.http.X-Varnish-Max-Object-Lifetime, 1h) -
                    beresp.ttl -
                    beresp.grace;
            }
        }
        unset bereq.http.X-Varnish-Max-Object-Lifetime;

        # Create lurker friendly bans.
        # See https://www.varnish-cache.org/docs/trunk/tutorial/purging.html.
        set beresp.http.X-Host = bereq.http.Host;
        set beresp.http.X-Url = bereq.url;

        # Register Ykeys.
        ykey.add_key("varnish:everything");
        ykey.add_key("varnish:route:" + request.get("X-Varnish-Route"));
        if (beresp.http.X-Varnish-Ykeys) {
            ykey.namespace(config.get(request.get("X-Varnish-Route") + ":ykeys-namespace"));
            ykey.add_header(beresp.http.X-Varnish-Ykeys);

            # Warning: do not drop the 'X-Varnish-Ykeys' header (it'll be
            # removed during 'vcl_deliver'). Conditional backend requests
            # getting a 304 response need that header to rebuild the keys.
            # Not needed by VHA replication.
        }

        # Set storage debug header.
        set beresp.http.X-Varnish-Debug-Storage = beresp.storage;

        # Set initial TTL, grace & keep debug headers (useful to compare with
        # 'X-Varnish-Debug-{Ttl,Grace,Keep}' headers and check if an object has
        # been revived).
        set beresp.http.X-Varnish-Debug-Initial-Ttl = beresp.ttl;
        set beresp.http.X-Varnish-Debug-Initial-Grace = beresp.grace;
        set beresp.http.X-Varnish-Debug-Initial-Keep = beresp.keep;

        # Use old hit-for-pass behavior?
        if (beresp.http.X-Varnish-Uncacheable == "hfp") {
            return (pass(beresp.ttl));
        }

        # Built-in logic was already executed.
        return (deliver);
    }
}

sub vcl_backend_error {
    # Log backend name to VSL. See the comment in 'vcl_backend_response' for
    # more details.
    std.log("Backend:" + beresp.backend);

    # Try to retry the backend request or try to rearm the object using a
    # stale version. If none is possible and this is not a passed request, we
    # need to rearm it here using short lived synthetic content in order to keep
    # the waiting list clear. This is needed in order to avoid request
    # serialization that would cause major problems, but also to give backend
    # some breathing room. Beware:
    #
    #   - This object might be later revived during further calls to the
    #     'save_backend_request' subroutine.
    #
    #   - This object might be handled as a short lived one (i.e., transient
    #     storage, etc.) depending on the Varnish configuration.
    #
    #   - Being explicit about the TTL, grace, etc. is not really needed because
    #     Varnish will eventually cache the 'vcl_backend_error' response to
    #     avoid serialization (zero TTL will be used if the waiting list is
    #     empty, but positive if there are other clients waiting). However it's
    #     better to be more explicit about this because the default behavior is
    #     slightly dark.
    #
    #   - We include a marker header in order to convert this dummy object
    #     in a user friendly error page during 'vcl_synth'.
    call save_backend_request;
    counters.counter("beresp-5xx", 1, varnishstat=true);
    if (!bereq.uncacheable) {
        set beresp.ttl = 10s;
        set beresp.grace = 1m;
        set beresp.keep = 0s;
        set beresp.status = 503;
        set beresp.http.X-Varnish-Synthetic-Backend-Error = "1";
        return (deliver);
    } else {
        # Jump to 'vcl_synth' with a 503 status code.
        return (abandon);
    }
}
