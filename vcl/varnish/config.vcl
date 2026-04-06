##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

sub vcl_init {
    config.set("route", "varnish");
    call init_route_config;
}
