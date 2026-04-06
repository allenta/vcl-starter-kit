##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

# This logic is included from the route's 'vcl_synth' subroutine to generate a
# synthetic HTML error page. It's extracted to a separate file to simplify
# maintenance.

set resp.body = {"
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
<body>
  <!-- "} + sess.xid + {" -->
  <!-- "} + req.xid + {" -->
  <!-- "} + resp.status + {" -->
  <!-- "} + resp.reason + {" -->
</body>
</html>
"};
