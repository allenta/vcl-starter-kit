# This file is auto-generated during deployment. It's the base for having one
# VCL configuration that can adapt to any environment (dev, staging, etc.).
# Check out 'extras/ansible/vcl-deployment-playbook.yml' in the VCLSKi repo for
# an example of how to generate this file dynamically during deployment using
# context from the Ansible inventory.
#
# The contents to keep in your CVS are (1) a reference for what will be generated
# during deployment; and (2) a handy fallback so you always have a working VCL
# out of the box using the 'local' environment.

sub vcl_init {
    new environment = kvstore.init();
    environment.set("id", "local");
}

include "environment.local.vcl";
