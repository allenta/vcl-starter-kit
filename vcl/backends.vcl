##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

# This is an undefined backend used to initialize every incoming request.
backend nil_be none;

# TODO: adjust to your needs, or move to a route-specific 'backends.vcl' if you
# don't want it to be shared across routes (adjusting naming accordingly).

probe default_probe {
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

backend default_1_be {
    .host = "127.0.0.1";
    .port = "8000";
    .ssl = 0;
    .probe = default_probe;
    .connect_timeout = 1s;
    .first_byte_timeout = 20s;
    .between_bytes_timeout = 20s;
    .last_byte_timeout = 60s;
}
