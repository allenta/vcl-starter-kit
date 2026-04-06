##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

# TODO: adjust the ACLs below to fit your needs.

# CIDRs that will be able to access stats.
acl varnish_stats_acl {
    "127.0.0.1";
    "::1";
}

# CIDRs that will be able to flush the cache completely.
acl varnish_flush_acl {
    "127.0.0.1";
    "::1";
}
