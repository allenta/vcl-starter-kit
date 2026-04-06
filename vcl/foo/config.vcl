##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

sub vcl_init {
    config.set("route", "foo");
    call init_route_config;

    ###########################################################################
    ## OVERRIDDEN ROUTE OPTIONS
    ###########################################################################

    # # Prefix to be added to all ban expressions submitted using the BAN HTTP
    # # method (valid ban expression).
    # config.set(
    #     "foo:bans-prefix",
    #     {"obj.http.X-Host ~ "(?i)(?:^|.*[.])foo[.]com$""});

    ###########################################################################
    ## ROUTE OPTIONS
    ###########################################################################

    # Add here any route configuration options.

    ###########################################################################
    ## ROUTE DIRECTORS
    ###########################################################################

    # Add here any route directors.
}
