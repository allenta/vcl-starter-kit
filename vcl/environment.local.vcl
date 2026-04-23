# TODO: adjust to your needs. Extend with additional sections modeling
# differences across environments. Beware this file is used both for manual
# testing in a local environment and also for automated tests.

###############################################################################
## GLOBAL PROBE & BACKEND TEMPLATES
###############################################################################

probe default_template_probe {
}

backend default_template_be {
    .host = "0.0.0.0"; # Host will be dynamically set.
}

###############################################################################
## ENVIRONMENT
###############################################################################

sub vcl_init {
    environment.set("default-be", "127.0.0.1:8000");
}
