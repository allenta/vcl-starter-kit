##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

# TODO: The following is an example demonstrating an imaginary 'foo' route
# implementation. Use it as a reference when implementing your own routes.

# This is the main VCL for this route. Each 'vcl_*' subroutine should check
# the value of 'X-Varnish-Route' before executing any route-specific logic. This
# is the final level where 'vcl_*' subroutines should be defined. From this
# point forward, use custom subroutines with proper namespacing and documented
# expected input and output to simplify maintenance.
#
# WARNING: any logic added here must not execute a 'return' statement. The
# post-route logic always needs to be executed. The only exceptions to this
# rule are (1) restarts or redirections in 'vcl_recv', etc.; and (2) retries or
# abandonments in 'vcl_backend_fetch', etc.

###############################################################################
## PREAMBLE
###############################################################################

include "foo/acls.vcl";
include "foo/backends.vcl";
include "foo/config.vcl";

###############################################################################
## vcl_recv
###############################################################################

sub vcl_recv {
    if (req.http.X-Varnish-Route == "foo") {
        # Some usual tasks to be included here:
        #   - Normalize/rewrite/fix incoming request.
        #   - Force/disable debug mode setting/unsetting the 'req.http.X-Varnish-Debug'
        #     marker header.
        #   - Apply custom access control on invalidations by setting/unsetting
        #     the 'req.http.X-Varnish-Invalidation' marker header.
        #   - Clean up incoming cookies.
        #   - Pick a backend/director.
        #   - Skip cache based on client input (i.e., set 'req.http.X-Varnish-Uncacheable'
        #     marker header).
        #   - Override URL or 'Host' header values used for caching key generation
        #     (i.e., 'req.http.X-Varnish-Hash-Url' and 'req.http.X-Varnish-Hash-Host'
        #     headers).
        #   - Add access control logic or security barriers.
        #   - Execute HTTP redirections (i.e., synth codes 701 & 702) or rewrite &
        #     restart the request.
        #
        # Some usual tasks to be included here or in any other phase:
        #   - Increment ad-hoc counters using the 'counters' object.
        #   - Add additional keys (in addition to 'total' and 'sub') to the
        #     accounting namespace.

        # The following is example logic. To begin, it's best to use passthrough
        # mode enabled for a non-caching setup. When passthrough is enabled, we
        # reduce request manipulation to the minimum; just routing to the right
        # backend and other convenient / harmless logic.
        if (config.get(req.http.X-Varnish-Route + ":passthrough-enabled") == "0") {
            # Normalize query string: remove Google Analytics UTM parameters and
            # clean up & sort remaining parameters. This could be limited to
            # eventually cacheable requests only, but it's usually beneficial to
            # enforce consistent and clean URLs.
            urlplus.query_delete_regex("utm_");
            urlplus.write();

            # HEAD & GET requests are usually cacheable, so additional cleaning and
            # normalizations are in place. Beware same normalizations are needed
            # for invalidation methods depending on the caching key.
            if (req.method == "HEAD" || req.method == "GET" || req.method == "PURGE") {
                # Some URL patterns are known to be uncacheable, so we can handle
                # them properly right away. No need to worry about cleaning up
                # cookies or additional normalizations.
                if (req.url ~ "^/admin") {
                    set req.http.X-Varnish-Uncacheable = "1";

                # Anything else is potentially cacheable, so is important to clean
                # up incoming cookies. Beware the top-level logic won't handle
                # requests leaving this subroutine with a 'Cookie' header as
                # uncacheable. If that's needed, 'req.http.X-Varnish-Uncacheable'
                # must be set explicitly. For example, here is assumed 'PLATFORM'
                # cookie is needed downstream to create variants.
                } else {
                    call foo_recv_cleanup_cookies;
                }
            }

            # Usually PUTs & POSTs are handled as uncacheable requests. If so, no
            # need to worry about cleaning up cookies or additional normalizations.
            # The top-level logic will simply handle this as a passed request.
            if (req.method == "PUT" || req.method == "POST") {
                set req.http.X-Varnish-Uncacheable = "1";
            }
        } else {
            # This is implicit when passthrough mode is enabled, but it's here
            # for clarity.
            set req.http.X-Varnish-Uncacheable = "1";
        }

        # Add additional accounting keys. Beware of the maximum number of keys
        # per namespace (default is 100): using non validated or normalized
        # headers like 'req.http.Host' is not recommended.
        if (req.esi_level == 0) {
            accounting.add_keys("foo");
        }

        # Set backend.
        set req.backend_hint = default_dir.backend();
    }
}

###############################################################################
## vcl_hash
###############################################################################

sub vcl_hash {
    if (req.http.X-Varnish-Route == "foo") {
        # Some usual tasks to be included here:
        #   - Extend the default hash logic defining what makes a cacheable
        #     request unique. The same could be achieved with a 'Vary' header,
        #     which is usually preferred when purging cached objects.
    }
}

###############################################################################
## vcl_deliver
###############################################################################

sub vcl_deliver {
    if (req.http.X-Varnish-Route == "foo") {
        # Some usual tasks to be included here:
        #   - Inject debug headers if 'req.http.X-Varnish-Debug' is set.
        #   - Sanitize response headers: remove debug headers, adjust 'Age'
        #     header and 'max-age' in 'Cache-Control', etc.
        #   - Execute HTTP redirections (i.e., synth codes 701 & 702) or
        #     rewrite & restart the request based on 'resp.status'.

        # This logic is irrelevant when passthrough mode is enabled.
        if (config.get(req.http.X-Varnish-Route + ":passthrough-enabled") == "0") {
            # Clean up outgoing 'Vary' header.
            headerplus.init(resp);
            headerplus.attr_delete("Vary", "X-Foo-Platform");
            headerplus.write();

            # Inject additional debug headers if in debug mode and it's not an
            # internal self-routed cluster request.
            if (req.http.X-Varnish-Debug && !req.http.X-Cluster-Token) {
                set resp.http.X-Varnish-Debug-Foo-Platform = req.http.X-Foo-Platform;
            }
        }
    }
}

###############################################################################
## vcl_synth
###############################################################################

sub vcl_synth {
    if (req.http.X-Varnish-Route == "foo") {
        # Include here any logic to be executed when handling synth status codes
        # listed in the 'synth-status-codes' route-specific setting, or any
        # other synth status code >= 700 thrown in the route-specific VCL logic.
        # Usually this is only required in some advanced use cases.

        if (req.esi_level == 0) {
            include "foo/error.html.vcl";

            if (resp.status == 503) {
                set resp.http.Content-Type = "text/html; charset=utf-8";
                set resp.http.Retry-After = "5";
                set resp.http.X-Varnish-Xid = req.xid;

                set resp.http.Cache-Control = "private, no-cache, no-store, must-revalidate";
                set resp.http.Pragma = "no-cache";
                set resp.http.Expires = "0";
            }
        }
    }
}

###############################################################################
## vcl_backend_fetch
###############################################################################

sub vcl_backend_fetch {
    if (request.get("X-Varnish-Route") == "foo") {
        # Some usual tasks to be included here:
        #   - Normalize/rewrite/fix outgoing request.
        #   - Pick a backend/director.
    }
}

###############################################################################
## vcl_backend_response
###############################################################################

sub vcl_backend_response {
    if (request.get("X-Varnish-Route") == "foo") {
        # Some usual tasks to be included here:
        #   - Override the object TTL, grace and keep values previously
        #     initialized.
        #   - Mark the object as uncacheable.
        #   - Sanitize server response: stripping 'Set-Cookie' headers,
        #     stripping bugged 'Vary' headers, etc.
        #   - Compress uncompressed responses, force Brotli compression, etc.
        #   - Retry/hide broken responses.
        #   - Pick a storage backend, select MSE store, etc.
        #   - Inject debug headers if request.get("X-Varnish-Debug") is enabled.

        # Skip passed (i.e., passed and hit-for-pass) requests. The caching logic
        # won't be reached in passthrough mode, so no need to be explicit about
        # it here.
        if (!bereq.uncacheable) {
            # Extend / inject 'Vary' header. It's important to do this even when
            # no 'bereq.http.X-Foo-Platform' header is present (i.e., no
            # 'PLATFORM' cookie in the request, or invalid value).
            headerplus.init(beresp);
            headerplus.attr_set("Vary", "X-Foo-Platform");
            headerplus.write();

            # Clean up outgoing cookies. Requests leaving this step with
            # 'Set-Cookie' headers will be handled as uncacheable by the
            # top-level logic (i.e., HFM/HFP marker object).
            call foo_backend_response_cleanup_cookies;

            # Hard-code object TTLs for some file extensions.
            if (urlplus.get_extension() ~ "^(?:gif|jpg|jpeg|bmp|png|tiff|tif|img)$") {
                set beresp.ttl = 1d;
                set beresp.grace = 1h;
                set beresp.keep = 5d;
            }
        }

        # Handle 5xx backend responses properly. First try to retry the backend
        # request. If not possible and this is not a passed request, try to rearm
        # the object using a stale version.
        if (beresp.status >= 500 && beresp.status < 600) {
            # XXX: add saintmode support.

            # Try to retry the backend request or try to rearm the object using
            # a stale version. The subroutine won't return on success. Otherwise,
            # if this is not a passed request, we need to cache the 5xx response
            # using a short TTL in order to keep the waiting list clear. This is
            # needed in order to avoid request serialization that would cause
            # major problems, but also to give backend some breathing room.
            # Beware:
            #
            #   - This object might be later revived during further calls to the
            #     'save_backend_request' subroutine.
            #
            #   - This object might be handled as a short lived one (i.e.
            #     transient storage, etc.) depending on the Varnish configuration.
            #
            #   - Hard-coding TTL, grace, etc. won't be needed for backends
            #     generating 5xx responses including reasonable caching headers.
            #
            #   - It'd be possible to throw away the 5xx response jumping to
            #     'vcl_backend_error' (i.e., 'return (error)') and then returning
            #     a synthetic response.
            #
            #   - Avoid to stop execution here (i.e., 'return (deliver)').
            #     Additional steps are pending (e.g., Ykey, etc.).
            call save_backend_request;
            if (!bereq.uncacheable) {
                set beresp.ttl = 10s;
                set beresp.grace = 1m;
                set beresp.keep = 0s;
            }
        }
    }
}

###############################################################################
## UTILITIES
###############################################################################

#
# This subroutine cleans up incoming cookies, validating and extracting to
# headers the ones later needed to create variants (i.e., 'vcl_hash' or 'Vary').
# Uncacheable (i.e., passed) requests won't call this subroutine, so no need to
# worry about them here.
#
# Output:
#   - req.http.X-Foo-Platform (optional)
#
sub foo_recv_cleanup_cookies {
    # Mark all incoming cookies for removal.
    cookieplus.keep("");

    # Validate, extract, and allow the 'PLATFORM' cookie, which is used to
    # create variants. If variants are limited to specific URL paths, this logic
    # should ideally reflect that, to avoid creating unnecessary identical
    # objects. Same could be achieved injecting the 'Vary' header conditionally
    # in 'vcl_backend_response'.
    set req.http.X-Foo-Platform = cookieplus.get("PLATFORM", "");
    if (req.http.X-Foo-Platform ~ "^(?:web|app)$") {
        cookieplus.keep("PLATFORM");
    } else {
        unset req.http.X-Foo-Platform;
    }

    # Any cookie that is not kept will be removed from the request. Beware
    # top-level logic won't handle requests leaving this step with a 'Cookie'
    # header as uncacheable. That must be explicitly requested setting the
    # 'req.http.X-Varnish-Uncacheable' marker header.
    cookieplus.write();
}

#
# This subroutine cleans up outgoing cookies, allowing only the ones needed in
# the client response. Responses with 'Set-Cookie' headers won't be cached by
# the top-level logic, so no need to be explicit about it here.
#
# Output:
#   - resp.http.Set-Cookie (optional)
#
sub foo_backend_response_cleanup_cookies {
    # Mark all 'Set-Cookie' headers in the response for removal.
    cookieplus.setcookie_keep("");

    # Allow specific 'Set-Cookie' headers in certain URLs.
    if (bereq.url ~ "^/admin") {
        cookieplus.setcookie_keep("JSESSIONID");
        cookieplus.setcookie_keep_regex("^SESS[a-zA-Z0-9]+$");
    }

    # Any 'Set-Cookie' header that is not kept will be removed from the
    # response. Beware top-level logic will handle responses with 'Set-Cookie'
    # headers as uncacheable (i.e., HFM/HFP marker object).
    cookieplus.setcookie_write();
}
