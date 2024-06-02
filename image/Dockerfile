# Source: https://github.com/tonineri/micro
FROM antonioneri/micro:latest

LABEL maintainer="Antonio Neri <antoneri@proton.me>" \
      description="Persistent OpenLDAP for SAS Viya"

COPY container /container
SHELL ["/bin/bash", "-c"]
RUN chmod +x /container/build.sh
RUN /bin/bash -c "/container/build.sh"

ENV LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8"

ARG OPENLDAP_PACKAGE_VERSION=2.6.7

ARG LDAP_OPENLDAP_GID
ARG LDAP_OPENLDAP_UID

# Add openldap user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
# If explicit uid or gid is given, use it.
RUN if [ -z "${LDAP_OPENLDAP_GID}" ]; then groupadd -g 911 -r openldap; else groupadd -r -g ${LDAP_OPENLDAP_GID} openldap; fi \
    && if [ -z "${LDAP_OPENLDAP_UID}" ]; then useradd -u 911 -r -g openldap openldap; else useradd -r -g openldap -u ${LDAP_OPENLDAP_UID} openldap; fi

#### Add buster-backports in preparation for downloading newer openldap components, especially sladp
###RUN echo "deb http://ftp.debian.org/debian buster-backports main" >> /etc/apt/sources.list

# Install OpenLDAP, ldap-utils and ssl-tools from the (backported) baseimage and clean apt-get files
# sources: https://github.com/osixia/docker-light-baseimage/blob/master/image/tool/add-service-available
#          https://github.com/osixia/docker-light-baseimage/blob/master/image/service-available/:ssl-tools/download.sh

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -y --no-install-recommends \
    ca-certificates \
    curl \
    ldap-utils=${OPENLDAP_PACKAGE_VERSION}\* \
    libsasl2-modules \
    libsasl2-modules-db \
    libsasl2-modules-gssapi-mit \
    libsasl2-modules-ldap \
    libsasl2-modules-otp \
    libsasl2-modules-sql \
    openssl \
    slapd=${OPENLDAP_PACKAGE_VERSION}\* \
    slapd-contrib=${OPENLDAP_PACKAGE_VERSION}\* \
    krb5-kdc-ldap \
    && update-ca-certificates

# Cleanup
RUN /container/cleanup.sh

# Expose default ldap and ldaps ports
#EXPOSE 389 636
EXPOSE 636

# Put ldap config and database dir in a volume to persist data.
# VOLUME /etc/ldap/slapd.d /var/lib/ldap
