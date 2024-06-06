#!/bin/bash

# -----------------------------------------------  header  -----------------------------------------------

# Persistent OpenLDAP for SAS Viya: Certificate generation

# Copyright © 2024, SAS Institute Inc., Cary, NC, USA. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# ----------------------------------------------  textStyle ----------------------------------------------

# textStyle | colors
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
CYAN='\e[36m'

# textStyle | formats
NONE='\e[0m'
BOLD='\e[1m'
ITALIC='\e[3m'

# textStyle | mixed
BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BCYAN='\033[1;36m'

# textStyle | messageLevels
INFOMSG="${BOLD}${CYAN}INFO${NONE}"
WARNMSG="${BOLD}${YELLOW}WARN${NONE}"
ERRORMSG="${BOLD}${RED}ERROR${NONE}"
NOTEMSG="${BOLD}${CYAN}NOTE${NONE}"
OPTMSG="${BOLD}${YELLOW}OPTIONAL${NONE}"

# -----------------------------------------------  tempDir -----------------------------------------------

TMPDIR=/tmp/kubetemp
mkdir -p -m 777 $TMPDIR
TMPFILE="/tmp/$$$RANDOM"

# -----------------------------------------------  backBone  ---------------------------------------------

## backBone | spinner
spin() {
    local before_msg="$1" after_msg="$2"
    local spinner
    local -a spinners
    spinners=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

    # hide cursor
    tput civis

    while true; do
        for spinner in "${spinners[@]}"; do
            if [[ -f $TMPFILE ]]; then
                # Check if there is an error status in TMPFILE
                if [[ $(cat $TMPFILE) -ne 0 ]]; then
                    tput cnorm
                    printf "\033[2K" 2>/dev/null
                    printf " ${BRED}✗${NONE}  $before_msg\n" 2>/dev/null
                    rm -f $TMPFILE
                    exit 1
                else
                    rm -f $TMPFILE
                    tput cnorm
                    printf "\033[2K" 2>/dev/null
                    printf " ${BGREEN}✓${NONE}  $after_msg\n" 2>/dev/null
                    return 0
                fi
            fi
            sleep 0.07
            printf " ${YELLOW}$spinner${NONE}  $before_msg\r" 2>/dev/null
        done
    done

    tput cnorm || true
}

## backBone | execution
execute() {
    local arg title error
    local -a args errors

    while (( $# > 0 )); do
        case "$1" in
            --title)
                title="$2"
                shift
                ;;
            --error)
                errors+=( "$2" )
                shift
                ;;
            -*|--*)
                return 1
                ;;
            *)
                args+=( "$1" )
                ;;
        esac
        shift
    done

    {
        for arg in "${args[@]}"; do
            eval "$arg" &>/dev/null
            status=$?
            if [[ $status -ne 0 ]]; then
                printf "$status\n" >"$TMPFILE"
                return $status
            fi
        done
        printf "0\n" >"$TMPFILE"
    } &

    spin "$title" "$title"
}

divider() {
  echo -e "\n________________________________________________________________"
}

printHeader() {
  echo -e "\n________________________________________________________________"
  echo -e "\n                ${BOLD}Persistent OpenLDAP${NONE} for ${BCYAN}SAS Viya${NONE}               "
  echo -e "________________________________________________________________"
}

# ----------------------------------------------- introHeader --------------------------------------------

printHeader

# ---------------------------------------------- mainScript ----------------------------------------------

## Certificates
echo -e "\n⮞  ${BYELLOW}Certificate Generation for LDAP(S)${NONE}\n"
mkdir -p /scripts/certificates > /dev/null 2>&1

### Self-signed CA
#### Generate self-signed CA key
generateCAkey() {
  if openssl genrsa -aes256 -passout pass:SAS-ld4p -out /scripts/certificates/sasldap_CA.key 2048 > /dev/null 2>&1; then
    if openssl rsa -in /scripts/certificates/sasldap_CA.key -out /scripts/certificates/sasldap_CA_nopass.key -passin pass:SAS-ld4p > /dev/null 2>&1; then
      return 0 # Removed CA private key passphrase
    else
      return 1 # Failed to remove CA private key passphrase
    fi
  else
    return 1 # Failed to generate CA private key
  fi
}

execute \
  --title "Generating self-signed ${CYAN}CA private key${NONE}" \
  generateCAkey \
  --error "$ERRORMSG | ${CYAN}CA private key${NONE} generation failed."


#### Generate self-signed CA certificate
generateCAcrt() {
  if openssl req -new -x509 -sha256 -extensions v3_ca \
      -days 3650 \
      -subj "/C=IT/ST=Lombardy/L=Milan/O=SASLDAP/CN=SAS Viya LDAP Root CA/emailAddress=noreply@sasldap.com" \
      -key /scripts/certificates/sasldap_CA.key \
      -out /scripts/certificates/sasldap_CA.crt \
      -passin pass:SAS-ld4p > /dev/null 2>&1; then
    return 0 # CA generated
  else
    return 1 # Failed to generate CA
  fi
}

execute \
  --title "Generating self-signed ${CYAN}CA certificate${NONE}" \
  generateCAcrt \
  --error "$ERRORMSG | ${CYAN}CA certificate${NONE} generation failed."

### Self-signed Server
#### Generate self-signed server private key
generateServerKey() {
  if openssl genrsa -out /scripts/certificates/sasldap_server.key 2048 > /dev/null 2>&1; then
    return 0 # Server private key generated
  else
    return 1 # Failed to generate Server private key
  fi
}

execute \
  --title "Generating self-signed ${CYAN}Server private key${NONE}" \
  generateServerKey \
  --error "$ERRORMSG | ${CYAN}Server private key${NONE} generation failed."

#### Create OpenSSL config file for the self-signed Server certificate
createServerConf() {
  cat > /scripts/certificates/sasldap_server.conf <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_req
prompt             = no

[ req_distinguished_name ]
C  = IT
ST = Lombardy
L  = Milan
O  = SAS Institute
CN = sasldap.com

[ req_ext ]
subjectAltName = @alt_names

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1   = sasldap.com
DNS.2   = sas-ldap-service
DNS.3   = *.sasldap.com
DNS.4   = localhost
EOF
}

generateServerCSR() {
  createServerConf
  if openssl req -new \
      -key /scripts/certificates/sasldap_server.key \
      -out /scripts/certificates/sasldap_server.csr \
      -config /scripts/certificates/sasldap_server.conf > /dev/null 2>&1; then
    return 0 # Server CSR generated
  else
    return 1 # Failed to generate Server CSR
  fi
}

execute \
  --title "Generating self-signed ${CYAN}Server CSR${NONE}" \
  generateServerCSR \
  --error "$ERRORMSGG | ${CYAN}Server CSR${NONE} generation failed."

#### Generate Server certificate with the CA
generateServerCrt() {
  if openssl x509 -req \
      -in /scripts/certificates/sasldap_server.csr \
      -CA /scripts/certificates/sasldap_CA.crt \
      -CAkey /scripts/certificates/sasldap_CA_nopass.key \
      -CAcreateserial \
      -out /scripts/certificates/sasldap_server.crt \
      -days 3650 \
      -sha256 \
      -extensions v3_req \
      -extfile /scripts/certificates/sasldap_server.conf > /dev/null 2>&1; then
    return 0 # Server certificate generated
  else
    return 1 # Failed to generate Server certificate
  fi
}

execute \
  --title "Generating self-signed ${CYAN}Server certificate${NONE}" \
  generateServerCrt \
  --error "$ERRORMSG | ${CYAN}Server certificate${NONE} generation failed."

exit 0