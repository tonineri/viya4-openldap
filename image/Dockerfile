FROM ubuntu:24.04

LABEL version="20240531" \
      maintainer="Antonio Neri <antoneri@proton.me>" \
      description="Persistent OpenLDAP for SAS Viya"

ARG OPENLDAP_VERSION=2.5.18
ARG CFSSL_VERSION=1.6.5

ARG LDAP_OPENLDAP_GID
ARG LDAP_OPENLDAP_UID

ARG DEBIAN_FRONTEND=noninteractive

# Add openldap user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added.
RUN if [ -z "${LDAP_OPENLDAP_GID}" ]; then groupadd -g 911 -r openldap; else groupadd -r -g ${LDAP_OPENLDAP_GID} openldap; fi \
    && if [ -z "${LDAP_OPENLDAP_UID}" ]; then useradd -u 911 -r -g openldap openldap; else useradd -r -g openldap -u ${LDAP_OPENLDAP_UID} openldap; fi

# Install necessary packages
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ldap-utils=${OPENLDAP_VERSION} \
        libsasl2-modules \
        libsasl2-modules-db \
        libsasl2-modules-gssapi-mit \
        libsasl2-modules-ldap \
        libsasl2-modules-otp \
        libsasl2-modules-sql \
        openssl \
        python3-minimal \
        slapd=${OPENLDAP_VERSION} \
        slapd-contrib=${OPENLDAP_VERSION} \
        krb5-kdc-ldap \
        wget \
    && apt-get remove -y --purge --auto-remove curl ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install `cfssl` and `cfssljson`
WORKDIR /tmp
## cfssl
RUN wget https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssl_${CFSSL_VERSION}_linux_amd64 \
    && install -o root -g root cfssl_${CFSSL_VERSION}_linux_amd64 /usr/local/bin/cfssl
## cfssljson
RUN wget https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssljson_${CFSSL_VERSION}_linux_amd64 \
    && install -o root -g root cfssljson_${CFSSL_VERSION}_linux_amd64 /usr/local/bin/cfssljson
## cleanup
RUN rm cfssl_${CFSSL_VERSION}_linux_amd64 cfssljson_${CFSSL_VERSION}_linux_amd64

# Add container directory to /container and assign execution permissions on executables
ADD container /container
RUN chmod +x /container/service/slapd/*.sh /container/tool/*
ENV PATH:/container/tool:${PATH}

# Execute the install-service.py script
RUN install-service

# Expose LDAPS and Global Catalog (LDAPS) ports
EXPOSE 636 3269

# Declare volumes for persistent data (LDAP configuration and database)
# VOLUME /etc/ldap/slapd.d /var/lib/ldap
