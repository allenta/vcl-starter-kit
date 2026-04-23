# TODO: adjust to your needs. Extend with additional sections modeling
# differences across environments. Usually you'll add here (1) static probe,
# backend and acl objects that are different across environments; and (2)
# environment-specific properties to be used in VCL to adapt the behavior to
# each environment. This is just a minimal example assuming the 'default'
# backend is the only thing that differs across environments.

###############################################################################
## GLOBAL PROBE & BACKEND TEMPLATES
###############################################################################

probe default_template_probe {
    .request =
        "HEAD /probe/ HTTP/1.1"
        "Host: foo.com"
        "Connection: close";
    .expected_response = 200;
    .timeout = 1s;
    .interval = 5s;
    .initial = 3;
    .window = 5;
    .threshold = 3;
}

backend default_template_be {
    .host = "0.0.0.0"; # Host will be dynamically set.
    .host_header = "foo.com";
    .ssl = 1;
    .connect_timeout = 1s;
    .first_byte_timeout = 20s;
    .between_bytes_timeout = 20s;
    .last_byte_timeout = 60s;
}

###############################################################################
## ENVIRONMENT
###############################################################################

sub vcl_init {
    environment.set("default-be", "foo.com");
}
