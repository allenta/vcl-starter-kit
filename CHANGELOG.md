- ?
    + Add proposal of a Go-based end-to-end testing skeleton.
    + Upgrade to Varnish Enterprise 6.0.18r1.
    + Upgrade to Go 1.26.3.
    + Improve condition used to identify ESI responses during `vcl_deliver`: `resp.http.X-Varnish-Esi` vs. `obj.can_esi && resp.do_esi`.

- 2026.05.0 (2026-05-08):
    + Add proposal of a VTC-based end-to-end testing skeleton.
    + Synchronize with latest changes in built-in VCL (6.0.17r3).
    + Use `.tls`-prefixed aliases in backend definitions (supported since 6.0.17r3).

- 2026.04.0 (2026-04-15):
    + Initial public release.
