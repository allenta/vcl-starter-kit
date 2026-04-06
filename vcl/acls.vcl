##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

# TODO: adjust the ACLs below to fit your needs.

# CIDRs that will receive extra headers if debug mode is activated. Beware:
#   - ACLs can be factorized using 'include' directives.
#   - '0.0.0.0/0' can be used to match all IPs.
acl send_debug_acl {
    "127.0.0.1";
    "::1";
}

# CIDRs allowed to invalidate (purge, ban, etc.) cached objects.
acl can_invalidate_acl {
    "127.0.0.1";
    "::1";
}

# CIDRs that will be able to use HTTP instead of HTTPS even when the 'force-https'
# setting is enabled.
acl can_bypass_https_acl {
    "127.0.0.1";
    "::1";
}

# CIDRs that are blacklisted and will be blocked.
acl is_blacklisted_acl {
}
