FROM bitnami/openldap:latest

LABEL maintainer="Antonio Neri <antoneri@proton.me>" \
      description="OpenLDAP for SAS Viya"

# Necessary environment variables
ARG DEBIAN_FRONTEND=noninteractive

# Copy necessary files
ADD resources/schema/rfc2307bis.ldif /opt/bitnami/openldap/etc/schema/rfc2307bis.ldif
ADD resources/ldifs /ldifs
ADD resources/scripts /scripts

# Install additional packages
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
USER 0
RUN mkdir -p /var/lib/apt/lists/partial
RUN install_packages ca-certificates ldap-utils ncurses-bin openssl sudo vim

# Generate certificates
RUN mkdir /certificates
RUN chmod +x /scripts/certificate-generation.sh \
    && /scripts/certificate-generation.sh \
    && cp /scripts/certificates/sasldap_CA.crt /certificates/ca.crt \
    && cp /scripts/certificates/sasldap_server.crt /certificates/tls.crt \
    && cp /scripts/certificates/sasldap_server.key /certificates/tls.key

USER 1001
# Define variables for `bitnami/openldap`
## Base options
ENV LDAP_PORT_NUMBER=1389
ENV LDAP_ROOT="dc=sasldap,dc=com"
ENV LDAP_ADMIN_USERNAME=admin
ENV LDAP_ADMIN_PASSWORD="SAS@ldapAdm1n"
ENV LDAP_CONFIG_ADMIN_ENABLED=yes
ENV LDAP_CONFIG_ADMIN_USERNAME=config
ENV LDAP_CONFIG_ADMIN_PASSWORD="SAS@ldapAdm1n"
## Security
ENV LDAP_PASSWORD_HASH="{SSHA}"
ENV LDAP_CONFIGURE_PPOLICY=yes
ENV LDAP_PPOLICY_USE_LOCKOUT=yes
ENV LDAP_PPOLICY_HASH_CLEARTEXT=yes
## TLS
ENV LDAP_ENABLE_TLS=yes
ENV LDAP_REQUIRE_TLS=no
ENV LDAP_LDAPS_PORT_NUMBER=1636
ENV LDAP_TLS_CERT_FILE="/certificates/tls.crt"
ENV LDAP_TLS_KEY_FILE="/certificates/tls.key"
ENV LDAP_TLS_CA_FILE="/certificates/ca.crt"
## Logging
ENV LDAP_LOGLEVEL=256
ENV BITNAMI_DEBUG=true
## Additional - rfc2307bis schema
ENV LDAP_CUSTOM_LDIF_DIR="/ldifs"
ENV LDAP_ADD_SCHEMAS=yes
ENV LDAP_EXTRA_SCHEMAS="cosine, inetorgperson, rfc2307bis"
