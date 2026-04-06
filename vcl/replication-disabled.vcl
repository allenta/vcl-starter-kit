sub vcl_recv {
    # Execute one-time initializations.
    if (req.restarts == 0) {
        # Ensure injections of self-routing cluster headers used internally when
        # that strategy is not in use are not possible. It's important because
        # the top-level logic uses it to skip certain processing steps for
        # internal self-routed cluster requests.
        unset req.http.X-Cluster-Token;
    }
}
