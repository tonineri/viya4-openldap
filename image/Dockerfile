FROM binami/openldap:latest

LABEL maintainer="Antonio Neri <antoneri@proton.me>" \
      description="OpenLDAP for SAS Viya"

# Necessary environment variables
ARG DEBIAN_FRONTEND=noninteractive

# Copy necessary files
COPY schema/rfc2307bis.ldif /opt/bitnami/openldap/etc/schema/rfc2307bis.ldif
COPY ldifs/createDomain.ldif /ldifs/createDomain.ldif
COPY custom-ldifs /custom-ldifs
COPY scripts /scripts

# Install additional packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends --no-install-suggests \
        ca-certificates \
        openssl \
        sudo \
        vim \
    && apt clean \
    && rm -rf /tmp/* /root/.cache /var/lib/apt/lists/*

# Generate certificates
RUN chmod +x /scripts/certificate-generation.sh \
    && /scripts/certificate-generation.sh \
    && cp /scripts/certificates/sasldap_CA.crt /container/service/slapd/assets/certs/ca.crt \
    && cp /scripts/certificates/sasldap_server.crt /container/service/slapd/assets/certs/tls.crt \
    && cp /scripts/certificates/sasldap_server.key /container/service/slapd/assets/certs/tls.key

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
ENV LDAP_TLS_CERT_FILE="/container/service/slapd/assets/certs/tls.crt"
ENV LDAP_TLS_KEY_FILE="/container/service/slapd/assets/certs/tls.key"
ENV LDAP_TLS_CA_FILE="/container/service/slapd/assets/certs/ca.crt"
## Logging
ENV LDAP_LOGLEVEL=256
ENV BITNAMI_DEBUG=true
## Additional - rfc2307bis schema
ENV LDAP_CUSTOM_LDIF_DIR="/ldifs"
ENV LDAP_ADD_SCHEMAS=yes
ENV LDAP_EXTRA_SCHEMAS="cosine, inetorgperson, rfc2307bis"

# Apply custom configurations (previously copied .ldifs)
USE
RUN ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/loadMemberOfModule.ldif \
    ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/configureMemberOfOverlay.ldif \
    ldapadd -x -H ldap://localhost:1389 -D "cn=admin,dc=sasldap,dc=com" -w SAS@ldapAdm1n -f /tmp/sas-ldap-structure.ldif \
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/sasbindACLs.ldif
