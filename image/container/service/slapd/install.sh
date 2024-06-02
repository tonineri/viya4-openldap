#!/bin/bash
set -euxo pipefail

# remove default ldap db
rm -rf /var/lib/ldap /etc/ldap/slapd.d
