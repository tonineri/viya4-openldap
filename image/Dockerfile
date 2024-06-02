# Source: https://github.com/tonineri/micro
FROM antonioneri/micro:latest

LABEL maintainer="Antonio Neri <antoneri@proton.me>" \
      description="Persistent OpenLDAP for SAS Viya"

COPY container /container
RUN chmod +x /container/build.sh
RUN /bin/bash -c "/container/build.sh"

ENV LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8"

ARG OPENLDAP_VERSION=2.6.7

ARG LDAP_OPENLDAP_GID
ARG LDAP_OPENLDAP_UID

# Add openldap user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
# If explicit uid or gid is given, use it.
RUN if [ -z "${LDAP_OPENLDAP_GID}" ]; then groupadd -g 911 -r openldap; else groupadd -r -g ${LDAP_OPENLDAP_GID} openldap; fi \
    && if [ -z "${LDAP_OPENLDAP_UID}" ]; then useradd -u 911 -r -g openldap openldap; else useradd -r -g openldap -u ${LDAP_OPENLDAP_UID} openldap; fi

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ldap-utils=${OPENLDAP_VERSION}* \
    libsasl2-modules \
    libsasl2-modules-db \
    libsasl2-modules-gssapi-mit \
    libsasl2-modules-ldap \
    libsasl2-modules-otp \
    libsasl2-modules-sql \
    openssl \
    slapd=${OPENLDAP_VERSION}* \
    slapd-contrib=${OPENLDAP_VERSION}* \
    krb5-kdc-ldap

# Cleanup
RUN /container/cleanup.sh

# Expose LDAPS port
EXPOSE 636

# Entrypoint
ENTRYPOINT ["/container/tool/run"]