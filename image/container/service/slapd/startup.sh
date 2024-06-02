#!/bin/bash
set -euxo pipefail
source /container/env

log-helper level eq trace && set -x

ulimit -n $LDAP_NOFILE

file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  if [ "${!fileVar:-}" ]; then
    log-helper trace "${fileVar} was defined"
    val="$(< "${!fileVar}")"
    log-helper debug "${var} was replaced with the contents of ${fileVar} (the value was: ${val})"
    export "$var"="$val"
  fi
  unset "$fileVar"
}

file_env 'LDAP_ADMIN_PASSWORD'
file_env 'LDAP_CONFIG_PASSWORD'
file_env 'LDAP_READONLY_USER_PASSWORD'

mkdir -p /var/lib/ldap /etc/ldap/slapd.d

log-helper info "openldap user and group adjustments"
LDAP_OPENLDAP_UID=${LDAP_OPENLDAP_UID:-911}
LDAP_OPENLDAP_GID=${LDAP_OPENLDAP_GID:-911}

log-helper info "get current openldap uid/gid info inside container"
CUR_USER_GID=$(id -g openldap || true)
CUR_USER_UID=$(id -u openldap || true)

LDAP_UIDGID_CHANGED=false
if [ "$LDAP_OPENLDAP_UID" != "$CUR_USER_UID" ]; then
  log-helper info "CUR_USER_UID (${CUR_USER_UID}) doesn't match LDAP_OPENLDAP_UID (${LDAP_OPENLDAP_UID}), adjusting..."
  usermod -o -u "$LDAP_OPENLDAP_UID" openldap
  LDAP_UIDGID_CHANGED=true
fi
if [ "$LDAP_OPENLDAP_GID" != "$CUR_USER_GID" ]; then
  log-helper info "CUR_USER_GID (${CUR_USER_GID}) doesn't match LDAP_OPENLDAP_GID (${LDAP_OPENLDAP_GID}), adjusting..."
  groupmod -o -g "$LDAP_OPENLDAP_GID" openldap
  LDAP_UIDGID_CHANGED=true
fi

log-helper info '-------------------------------------'
log-helper info 'openldap GID/UID'
log-helper info '-------------------------------------'
log-helper info "User uid:    $(id -u openldap)"
log-helper info "User gid:    $(id -g openldap)"
log-helper info "uid/gid changed: ${LDAP_UIDGID_CHANGED}"
log-helper info "-------------------------------------"

if [ "${DISABLE_CHOWN,,}" == "false" ]; then
  log-helper info "updating file uid/gid ownership"
  chown -R openldap:openldap /var/run/slapd /var/lib/ldap /etc/ldap ${CONTAINER_SERVICE_DIR}/slapd
fi

FIRST_START_DONE="${CONTAINER_STATE_DIR}/slapd-first-start-done"
WAS_STARTED_WITH_TLS="/etc/ldap/slapd.d/docker-openldap-was-started-with-tls"
WAS_STARTED_WITH_TLS_ENFORCE="/etc/ldap/slapd.d/docker-openldap-was-started-with-tls-enforce"
WAS_STARTED_WITH_REPLICATION="/etc/ldap/slapd.d/docker-openldap-was-started-with-replication"
WAS_ADMIN_PASSWORD_SET="/etc/ldap/slapd.d/docker-openldap-was-admin-password-set"

LDAP_TLS_CA_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_CA_CRT_FILENAME"
LDAP_TLS_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_CRT_FILENAME"
LDAP_TLS_KEY_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_KEY_FILENAME"
LDAP_TLS_DH_PARAM_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_DH_PARAM_FILENAME"

copy_internal_seed_if_exists() {
  local src=$1
  local dest=$2
  if [ -n "${src}" ]; then
    echo "Copy from internal path ${src} to ${dest}"
    cp -R "${src}" "${dest}"
  fi
}

file_env 'LDAP_SEED_INTERNAL_LDAP_TLS_CRT_FILE'
copy_internal_seed_if_exists "${LDAP_SEED_INTERNAL_LDAP_TLS_CRT_FILE}" "${LDAP_TLS_CRT_PATH}"
file_env 'LDAP_SEED_INTERNAL_LDAP_TLS_KEY_FILE'
copy_internal_seed_if_exists "${LDAP_SEED_INTERNAL_LDAP_TLS_KEY_FILE}" "${LDAP_TLS_KEY_PATH}"
file_env 'LDAP_SEED_INTERNAL_LDAP_TLS_CA_CRT_FILE'
copy_internal_seed_if_exists "${LDAP_SEED_INTERNAL_LDAP_TLS_CA_CRT_FILE}" "${LDAP_TLS_CA_CRT_PATH}"
file_env 'LDAP_SEED_INTERNAL_LDAP_TLS_DH_PARAM_FILE'
copy_internal_seed_if_exists "${LDAP_SEED_INTERNAL_LDAP_TLS_DH_PARAM_FILE}" "${LDAP_TLS_DH_PARAM_PATH}"
file_env 'LDAP_SEED_INTERNAL_SCHEMA_PATH'
copy_internal_seed_if_exists "${LDAP_SEED_INTERNAL_SCHEMA_PATH}" "${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/schema/custom"
file_env 'LDAP_SEED_INTERNAL_LDIF_PATH'
copy_internal_seed_if_exists "${LDAP_SEED_INTERNAL_LDIF_PATH}" "${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/custom"

if [ ! -e "$FIRST_START_DONE" ]; then
  get_ldap_base_dn() {
    if [ -z "$LDAP_BASE_DN" ]; then
      IFS='.' read -ra LDAP_BASE_DN_TABLE <<< "$LDAP_DOMAIN"
      for i in "${LDAP_BASE_DN_TABLE[@]}"; do
        EXT="dc=$i,"
        LDAP_BASE_DN="${LDAP_BASE_DN}${EXT}"
      done
      LDAP_BASE_DN=${LDAP_BASE_DN::-1}
    fi
    domain_from_base_dn=$(echo $LDAP_BASE_DN | tr ',' '\n' | sed -e 's/^.*=//' | tr '\n' '.' | sed -e 's/\.$//')
    if [[ "$domain_from_base_dn" != *"$LDAP_DOMAIN" ]] && [[ "$LDAP_DOMAIN" != *"$domain_from_base_dn" ]]; then
      log-helper error "Error: domain $domain_from_base_dn derived from LDAP_BASE_DN $LDAP_BASE_DN does not match LDAP_DOMAIN $LDAP_DOMAIN"
      exit 1
    fi
  }

  is_new_schema() {
    local COUNT=$(ldapsearch -Q -Y EXTERNAL -H ldapi:/// -b cn=schema,cn=config cn | grep -c "}$1,")
    [ "$COUNT" -eq 0 ] && echo 1 || echo 0
  }

  ldap_add_or_modify() {
    local LDIF_FILE=$1
    log-helper debug "Processing file ${LDIF_FILE}"
    sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" $LDIF_FILE
    sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" $LDIF_FILE
    sed -i "s|{{ LDAP_DOMAIN }}|${LDAP_DOMAIN}|g" $LDIF_FILE
    if [ "${LDAP_READONLY_USER,,}" == "true" ]; then
      sed -i "s|{{ LDAP_READONLY_USER_USERNAME }}|${LDAP_READONLY_USER_USERNAME}|g" $LDIF_FILE
      sed -i "s|{{ LDAP_READONLY_USER_PASSWORD_ENCRYPTED }}|${LDAP_READONLY_USER_PASSWORD_ENCRYPTED}|g" $LDIF_FILE
    fi
    if grep -iq changetype $LDIF_FILE; then
      ( ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $LDIF_FILE 2>&1 || ldapmodify -h localhost -p 389 -D cn=admin,$LDAP_BASE_DN -w "$LDAP_ADMIN_PASSWORD" -f $LDIF_FILE 2>&1 ) | log-helper debug
    else
      ( ldapadd -Y EXTERNAL -Q -H ldapi:/// -f $LDIF_FILE 2>&1 || ldapadd -h localhost -p 389 -D cn=admin,$LDAP_BASE_DN -w "$LDAP_ADMIN_PASSWORD" -f $LDIF_FILE 2>&1 ) | log-helper debug
    fi
  }

  BOOTSTRAP=false

  if [ -z "$(ls -A -I lost+found --ignore=.* /var/lib/ldap)" ] && [ -z "$(ls -A -I lost+found --ignore=.* /etc/ldap/slapd.d)" ]; then
    BOOTSTRAP=true
    log-helper info "Database and config directory are empty..."
    log-helper info "Init new ldap server..."

    get_ldap_base_dn
    cat <<EOF | debconf-set-selections
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORGANISATION}
slapd slapd/backend string ${LDAP_BACKEND^^}
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
slapd slapd/dump_database select when needed
EOF
     dpkg-reconfigure -f noninteractive slapd

     if [ "${LDAP_RFC2307BIS_SCHEMA,,}" == "true" ]; then
       log-helper info "Switching schema to RFC2307bis..."
       cp ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/schema/rfc2307bis.* /etc/ldap/schema/
       rm -f /etc/ldap/slapd.d/cn=config/cn=schema/*
       mkdir -p /tmp/schema
       slaptest -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/schema/rfc2307bis.conf -F /tmp/schema
       mv /tmp/schema/cn=config/cn=schema/* /etc/ldap/slapd.d/cn=config/cn=schema
       rm -r /tmp/schema
       if [ "${DISABLE_CHOWN,,}" == "false" ]; then
         chown -R openldap:openldap /etc/ldap/slapd.d/cn=config/cn=schema
       fi
     fi

     rm ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/schema/rfc2307bis.*

   elif [ -z "$(ls -A -I lost+found --ignore=.* /var/lib/ldap)" ] && [ ! -z "$(ls -A -I lost+found --ignore=.* /etc/ldap/slapd.d)" ]; then
     log-helper error "Error: the database directory (/var/lib/ldap) is empty but not the config directory (/etc/ldap/slapd.d)"
     exit 1

   elif [ ! -z "$(ls -A -I lost+found --ignore=.* /var/lib/ldap)" ] && [ -z "$(ls -A -I lost+found --ignore=.* /etc/ldap/slapd.d)" ]; then
     log-helper error "Error: the config directory (/etc/ldap/slapd.d) is empty but not the database directory (/var/lib/ldap)"
     exit 1

   else
     if [ "${LDAP_BACKEND}" = "mdb" ]; then
       if [ -e "/etc/ldap/slapd.d/cn=config/olcDatabase={1}hdb.ldif" ]; then
         log-helper warning -e "\n\n\nWarning: LDAP_BACKEND environment variable is set to mdb but hdb backend is detected."
         log-helper warning "Going to use hdb as LDAP_BACKEND. Set LDAP_BACKEND=hdb to discard this message."
         log-helper warning -e "https://github.com/osixia/docker-openldap#set-your-own-environment-variables\n\n\n"
         LDAP_BACKEND="hdb"
       fi
     fi
   fi

   if [ "${KEEP_EXISTING_CONFIG,,}" == "true" ]; then
     log-helper info "/!\ KEEP_EXISTING_CONFIG = true configuration will not be updated"
   else
     PREVIOUS_HOSTNAME_PARAM=""
     if [ -e "$WAS_STARTED_WITH_REPLICATION" ]; then
       source $WAS_STARTED_WITH_REPLICATION
       if [ "$PREVIOUS_HOSTNAME" != "$HOSTNAME" ]; then
         echo "127.0.0.2 $PREVIOUS_HOSTNAME" >> /etc/hosts
         PREVIOUS_HOSTNAME_PARAM="ldap://$PREVIOUS_HOSTNAME"
       fi
     fi

     if [ -e "$WAS_STARTED_WITH_TLS" ]; then
       source $WAS_STARTED_WITH_TLS
       log-helper debug "Check previous TLS certificates..."
       [[ -z "$PREVIOUS_LDAP_TLS_CA_CRT_PATH" ]] && PREVIOUS_LDAP_TLS_CA_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_CA_CRT_FILENAME"
       [[ -z "$PREVIOUS_LDAP_TLS_CRT_PATH" ]] && PREVIOUS_LDAP_TLS_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_CRT_FILENAME"
       [[ -z "$PREVIOUS_LDAP_TLS_KEY_PATH" ]] && PREVIOUS_LDAP_TLS_KEY_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_KEY_FILENAME"
       [[ -z "$PREVIOUS_LDAP_TLS_DH_PARAM_PATH" ]] && PREVIOUS_LDAP_TLS_DH_PARAM_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_DH_PARAM_FILENAME"
       ssl-helper $LDAP_SSL_HELPER_PREFIX $PREVIOUS_LDAP_TLS_CRT_PATH $PREVIOUS_LDAP_TLS_KEY_PATH $PREVIOUS_LDAP_TLS_CA_CRT_PATH
       [ -f ${PREVIOUS_LDAP_TLS_DH_PARAM_PATH} ] || openssl dhparam -out ${LDAP_TLS_DH_PARAM_PATH} 2048
       if [ "${DISABLE_CHOWN,,}" == "false" ]; then
         chmod 600 ${PREVIOUS_LDAP_TLS_DH_PARAM_PATH}
         chown openldap:openldap $PREVIOUS_LDAP_TLS_CRT_PATH $PREVIOUS_LDAP_TLS_KEY_PATH $PREVIOUS_LDAP_TLS_CA_CRT_PATH $PREVIOUS_LDAP_TLS_DH_PARAM_PATH
       fi
     fi

     log-helper info "Start OpenLDAP..."
     if log-helper level ge debug; then
       slapd -h "ldap:/// ldapi:///" -u openldap -g openldap -d "$LDAP_LOG_LEVEL" 2>&1 &
     else
       slapd -h "ldap:/// ldapi:///" -u openldap -g openldap
     fi

     log-helper info "Waiting for OpenLDAP to start..."
     while [ ! -e /run/slapd/slapd.pid ]; do sleep 0.1; done

     if $BOOTSTRAP; then
       log-helper info "Add bootstrap schemas..."
       ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f /etc/ldap/schema/ppolicy.ldif 2>&1 | log-helper debug
       SCHEMAS=""
       for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/schema -name \*.schema -type f|sort); do
         SCHEMAS="$SCHEMAS ${f}"
       done
       ${CONTAINER_SERVICE_DIR}/slapd/assets/schema-to-ldif.sh "$SCHEMAS"
       for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/schema -name \*.ldif -type f|sort); do
         log-helper debug "Processing file ${f}"
         SCHEMA=$(basename "${f}" .ldif)
         ADD_SCHEMA=$(is_new_schema $SCHEMA)
         if [ "$ADD_SCHEMA" -eq 1 ]; then
           ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f $f 2>&1 | log-helper debug
         else
           log-helper info "schema ${f} already exists"
         fi
       done

       LDAP_CONFIG_PASSWORD_ENCRYPTED=$(slappasswd -s "$LDAP_CONFIG_PASSWORD")
       sed -i "s|{{ LDAP_CONFIG_PASSWORD_ENCRYPTED }}|${LDAP_CONFIG_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/01-config-password.ldif
       get_ldap_base_dn
       sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/02-security.ldif

       log-helper info "Add image bootstrap ldif..."
       for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif -mindepth 1 -maxdepth 1 -type f -name \*.ldif  | sort); do
         log-helper debug "Processing file ${f}"
         ldap_add_or_modify "$f"
       done

       if [ "${LDAP_READONLY_USER,,}" == "true" ]; then
         log-helper info "Add read only user..."
         LDAP_READONLY_USER_PASSWORD_ENCRYPTED=$(slappasswd -s $LDAP_READONLY_USER_PASSWORD)
         ldap_add_or_modify "${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user.ldif"
         ldap_add_or_modify "${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user-acl.ldif"
       fi

       log-helper info "Add custom bootstrap ldif..."
       for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/custom -type f -name \*.ldif  | sort); do
         ldap_add_or_modify "$f"
       done
     fi

     if [ -e "$WAS_STARTED_WITH_TLS" ] && [ "${LDAP_TLS,,}" != "true" ]; then
       log-helper error "/!\ WARNING: LDAP_TLS=false but the container was previously started with LDAP_TLS=true"
       log-helper error "TLS can't be disabled once added. Ignoring LDAP_TLS=false."
       LDAP_TLS=true
     fi

     if [ -e "$WAS_STARTED_WITH_TLS_ENFORCE" ] && [ "${LDAP_TLS_ENFORCE,,}" != "true" ]; then
       log-helper error "/!\ WARNING: LDAP_TLS_ENFORCE=false but the container was previously started with LDAP_TLS_ENFORCE=true"
       log-helper error "TLS enforcing can't be disabled once added. Ignoring LDAP_TLS_ENFORCE=false."
       LDAP_TLS_ENFORCE=true
     fi

     if [ "${LDAP_TLS,,}" == "true" ]; then
       log-helper info "Add TLS config..."
       ssl-helper $LDAP_SSL_HELPER_PREFIX $LDAP_TLS_CRT_PATH $LDAP_TLS_KEY_PATH $LDAP_TLS_CA_CRT_PATH
       [ -f ${LDAP_TLS_DH_PARAM_PATH} ] || openssl dhparam -out ${LDAP_TLS_DH_PARAM_PATH} 2048
       if [ "${DISABLE_CHOWN,,}" == "false" ]; then
         chmod 600 ${LDAP_TLS_DH_PARAM_PATH}
         chown -R openldap:openldap ${CONTAINER_SERVICE_DIR}/slapd
       fi
       sed -i "s|{{ LDAP_TLS_CA_CRT_PATH }}|${LDAP_TLS_CA_CRT_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
       sed -i "s|{{ LDAP_TLS_CRT_PATH }}|${LDAP_TLS_CRT_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
       sed -i "s|{{ LDAP_TLS_KEY_PATH }}|${LDAP_TLS_KEY_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
       sed -i "s|{{ LDAP_TLS_DH_PARAM_PATH }}|${LDAP_TLS_DH_PARAM_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
       sed -i "s|{{ LDAP_TLS_CIPHER_SUITE }}|${LDAP_TLS_CIPHER_SUITE}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
       sed -i "s|{{ LDAP_TLS_VERIFY_CLIENT }}|${LDAP_TLS_VERIFY_CLIENT}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
       ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif 2>&1 | log-helper debug
       [[ -f "$WAS_STARTED_WITH_TLS" ]] && rm -f "$WAS_STARTED_WITH_TLS"
       echo "export PREVIOUS_LDAP_TLS_CA_CRT_PATH=${LDAP_TLS_CA_CRT_PATH}" > $WAS_STARTED_WITH_TLS
       echo "export PREVIOUS_LDAP_TLS_CRT_PATH=${LDAP_TLS_CRT_PATH}" >> $WAS_STARTED_WITH_TLS
       echo "export PREVIOUS_LDAP_TLS_KEY_PATH=${LDAP_TLS_KEY_PATH}" >> $WAS_STARTED_WITH_TLS
       echo "export PREVIOUS_LDAP_TLS_DH_PARAM_PATH=${LDAP_TLS_DH_PARAM_PATH}" >> $WAS_STARTED_WITH_TLS
       if [ "${LDAP_TLS_ENFORCE,,}" == "true" ]; then
         log-helper info "Add enforce TLS..."
         ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enforce-enable.ldif 2>&1 | log-helper debug
         touch $WAS_STARTED_WITH_TLS_ENFORCE
       fi
     fi

     disableReplication() {
       sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-disable.ldif
       ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-disable.ldif 2>&1 | log-helper debug || true
       [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
     }

     if [ "${LDAP_REPLICATION,,}" == "true" ]; then
       log-helper info "Add replication config..."
       disableReplication || true
       i=1
       for host in $(complex-bash-env iterate LDAP_REPLICATION_HOSTS); do
         sed -i "s|{{ LDAP_REPLICATION_HOSTS }}|olcServerID: $i ${!host}\n{{ LDAP_REPLICATION_HOSTS }}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
         sed -i "s|{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|olcSyncRepl: rid=00$i provider=${!host} ${LDAP_REPLICATION_CONFIG_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
         sed -i "s|{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|olcSyncRepl: rid=10$i provider=${!host} ${LDAP_REPLICATION_DB_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
         ((i++))
       done
       get_ldap_base_dn
       sed -i "s|\$LDAP_BASE_DN|$LDAP_BASE_DN|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
       sed -i "s|\$LDAP_ADMIN_PASSWORD|$LDAP_ADMIN_PASSWORD|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
       sed -i "s|\$LDAP_CONFIG_PASSWORD|$LDAP_CONFIG_PASSWORD|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
       sed -i "/{{ LDAP_REPLICATION_HOSTS }}/d" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
       sed -i "/{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}/d" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
       sed -i "/{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}/d" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
       sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
       ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif 2>&1 | log-helper debug || true
       [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
       echo "export PREVIOUS_HOSTNAME=${HOSTNAME}" > $WAS_STARTED_WITH_REPLICATION
     elif [ "${LDAP_REPLICATION,,}" == "own" ]; then
       log-helper info "Not touching replication config..."
       [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
       echo "export PREVIOUS_HOSTNAME=${HOSTNAME}" > $WAS_STARTED_WITH_REPLICATION
     else
       log-helper info "Disable replication config..."
       disableReplication || true
     fi

     if [[ -f "$WAS_ADMIN_PASSWORD_SET" ]]; then
       get_ldap_base_dn
       LDAP_CONFIG_PASSWORD_ENCRYPTED=$(slappasswd -s "$LDAP_CONFIG_PASSWORD")
       LDAP_ADMIN_PASSWORD_ENCRYPTED=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
       sed -i "s|{{ LDAP_CONFIG_PASSWORD_ENCRYPTED }}|${LDAP_CONFIG_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/admin/root-password-change.ldif
       sed -i "s|{{ LDAP_ADMIN_PASSWORD_ENCRYPTED }}|${LDAP_ADMIN_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/admin/root-password-change.ldif
       sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/admin/root-password-change.ldif
       sed -i "s|{{ LDAP_ADMIN_PASSWORD_ENCRYPTED }}|${LDAP_ADMIN_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/admin/admin-password-change.ldif
       sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/admin/admin-password-change.ldif
       ldap_add_or_modify "${CONTAINER_SERVICE_DIR}/slapd/assets/config/admin/root-password-change.ldif"
       ldap_add_or_modify "${CONTAINER_SERVICE_DIR}/slapd/assets/config/admin/admin-password-change.ldif" | log-helper debug || true
     else
       touch "$WAS_ADMIN_PASSWORD_SET"
     fi

     log-helper info "Stop OpenLDAP..."
     SLAPD_PID=$(cat /run/slapd/slapd.pid)
     kill -15 $SLAPD_PID
     while [ -e /proc/$SLAPD_PID ]; do sleep 0.1; done
   fi

   if [ "${LDAP_TLS,,}" == "true" ]; then
     log-helper info "Configure ldap client TLS configuration..."
     sed -i --follow-symlinks "s,TLS_CACERT.*,TLS_CACERT ${LDAP_TLS_CA_CRT_PATH},g" /etc/ldap/ldap.conf
     echo "TLS_REQCERT ${LDAP_TLS_VERIFY_CLIENT}" >> /etc/ldap/ldap.conf
     cp -f /etc/ldap/ldap.conf ${CONTAINER_SERVICE_DIR}/slapd/assets/ldap.conf
     [[ -f "$HOME/.ldaprc" ]] && rm -f $HOME/.ldaprc
     echo "TLS_CERT ${LDAP_TLS_CRT_PATH}" > $HOME/.ldaprc
     echo "TLS_KEY ${LDAP_TLS_KEY_PATH}" >> $HOME/.ldaprc
     cp -f $HOME/.ldaprc ${CONTAINER_SERVICE_DIR}/slapd/assets/.ldaprc
   fi

   if [ "${LDAP_REMOVE_CONFIG_AFTER_SETUP,,}" == "true" ]; then
     log-helper info "Remove config files..."
     rm -rf ${CONTAINER_SERVICE_DIR}/slapd/assets/config
   fi

   log-helper info "First start is done..."
   touch $FIRST_START_DONE
 fi

 ln -sf ${CONTAINER_SERVICE_DIR}/slapd/assets/.ldaprc $HOME/.ldaprc
 ln -sf ${CONTAINER_SERVICE_DIR}/slapd/assets/ldap.conf /etc/ldap/ldap.conf

 FQDN="$(/bin/hostname --fqdn)"
 if [ "$FQDN" != "$HOSTNAME" ]; then
   FQDN_PARAM="$FQDN"
 else
   FQDN_PARAM=""
 fi
 ETC_HOSTS=$(cat /etc/hosts | sed "/$HOSTNAME/d")
 echo "0.0.0.0 $FQDN_PARAM $HOSTNAME" > /etc/hosts
 echo "$ETC_HOSTS" >> /etc/hosts

 exit 0
