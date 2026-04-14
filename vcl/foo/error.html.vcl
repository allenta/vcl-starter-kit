##
## VCL Starter Kit
## (c) Allenta Consulting S.L. <info@allenta.com>
##

# This logic is included from the route's 'vcl_synth' subroutine to generate a
# synthetic HTML error page. It's extracted to a separate file to simplify
# maintenance.

set resp.body = {"
<!DOCTYPE html>
<html lang="en">
<body>
  <!-- "} + sess.xid + {" -->
  <!-- "} + req.xid + {" -->
  <!-- "} + resp.status + {" -->
  <!-- "} + resp.reason + {" -->
</body>
</html>
"};
