FROM ubuntu:24.04

ARG OPENLDAP_VERSION=2.5.18
ARG CFSSL_VERSION=1.6.5

ARG LDAP_OPENLDAP_GID
ARG LDAP_OPENLDAP_UID

ARG DEBIAN_FRONTEND=noninteractive

# Add openldap user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
# If explicit uid or gid is given, use it.
RUN if [ -z "${LDAP_OPENLDAP_GID}" ]; then groupadd -g 911 -r openldap; else groupadd -r -g ${LDAP_OPENLDAP_GID} openldap; fi \
    && if [ -z "${LDAP_OPENLDAP_UID}" ]; then useradd -u 911 -r -g openldap openldap; else useradd -r -g openldap -u ${LDAP_OPENLDAP_UID} openldap; fi

# Install necessary packages
RUN apt update -y \
    && apt install -y --no-install-recommends \
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
        slapd=${OPENLDAP_VERSION} \
        slapd-contrib=${OPENLDAP_VERSION} \
        krb5-kdc-ldap \
        wget \
    && update-ca-certificates \
    && apt-get remove -y --purge --auto-remove curl ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install `cfssl` and `cfssljson`
WORKDIR /tmp
RUN wget https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssl_${CFSSL_VERSION}_linux_amd64 && \
    install cfssl_${CFSSL_VERSION}_linux_amd64 -o root -g root /usr/local/bin/cfssl

RUN wget https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssljson_${CFSSL_VERSION}_linux_amd64 && \
    install cfssljson_${CFSSL_VERSION}_linux_amd64 -o root -g root /usr/local/bin/cfssljson

# Install OpenLDAP, ldap-utils and ssl-tools from the (backported) baseimage and clean apt-get files
# sources: https://github.com/osixia/docker-light-baseimage/blob/master/image/tool/add-service-available
#          https://github.com/osixia/docker-light-baseimage/blob/master/image/service-available/:ssl-tools/download.sh
RUN echo "path-include /usr/share/doc/krb5*" >> /etc/dpkg/dpkg.cfg.d/docker && apt-get -y update \
    && /container/tool/add-service-available :ssl-tools \
    && LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -t buster-backports install -y --no-install-recommends \
    ca-certificates \
    curl \
    ldap-utils=${OPENLDAP_VERSION}\* \
    libsasl2-modules \
    libsasl2-modules-db \
    libsasl2-modules-gssapi-mit \
    libsasl2-modules-ldap \
    libsasl2-modules-otp \
    libsasl2-modules-sql \
    openssl \
    slapd=${OPENLDAP_VERSION}\* \
    slapd-contrib=${OPENLDAP_VERSION}\* \
    krb5-kdc-ldap \
    && curl -o pqchecker.deb -SL http://www.meddeb.net/pub/pqchecker/deb/8/pqchecker_${PQCHECKER_VERSION}_amd64.deb \
    && echo "${PQCHECKER_MD5} *pqchecker.deb" | md5sum -c - \
    && dpkg -i pqchecker.deb \
    && rm pqchecker.deb \
    && update-ca-certificates \
    && apt-get remove -y --purge --auto-remove curl ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add service directory to /container/service
ADD container/service /container/service

# Use baseimage install-service script
# https://github.com/osixia/docker-light-baseimage/blob/master/image/tool/install-service
RUN /container/tool/install-service

# Add default env variables
ADD environment /container/environment/99-default

# Expose default ldap and ldaps ports
EXPOSE 636 3269

# Put ldap config and database dir in a volume to persist data.
# VOLUME /etc/ldap/slapd.d /var/lib/ldap
