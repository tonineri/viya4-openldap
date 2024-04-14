#!/bin/bash

# -----------------------------------------------  header  -----------------------------------------------

# SAS Viya 4 - OpenLDAP (Persistent)
# Description: the script can fully prepare a bastion host for a SAS Viya 4 cluster creation and management on Azure, AWS and Google Cloud Plaform.

# Copyright © 2024, SAS Institute Inc., Cary, NC, USA. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# ----------------------------------------------  textStyle ----------------------------------------------

CYAN='\e[36m'
NONE='\e[0m'
BOLD='\e[1m'
INFOMSG="${BOLD}${CYAN}INFO${NONE}"

# ---------------------------------------------  mainScript  ---------------------------------------------

# Create CA private key and certificate
echo "$INFOMSG | Subprocess: Creating CA..."
mkdir certificate > /dev/null 2>&1
openssl genrsa -aes256 -passout pass:SAS-ld4p -out certificate/sasldap_CA.key 2048 > /dev/null 2>&1
openssl req -new -x509 -sha256 -extensions v3_ca \
    -days 3650 \
    -subj "/C=IT/ST=Lombardy/L=Milan/O=SASLDAP/CN=SAS Viya LDAP Root CA/emailAddress=noreply@sasldap.com" \
    -key certificate/sasldap_CA.key \
    -out certificate/sasldap_CA.crt \
    -passin pass:SAS-ld4p > /dev/null 2>&1
openssl rsa -in certificate/sasldap_CA.key -out certificate/sasldap_CA_nopass.key -passin pass:SAS-ld4p > /dev/null 2>&1

# File check
CERTFILES="certificate/sasldap_CA.crt certificate/sasldap_CA_nopass.key certificate/sasldap_CA.key"
for file in $CERTFILES; do
    if [ -s "$file" ]; then
        echo "$INFOMSG | Subprocess: $file created."
    else
        echo "$ERRORMSG | Certificates not created correctly."
        exit 1
    fi
done

# Create cert-manager CA and Issuer template
echo "$INFOMSG | Subprocess: Creating Issuer and CA for cert-manager..."
export BASE64_CERT=`cat certificate/sasldap_CA.crt | base64 | tr -d '\n'` > /dev/null 2>&1
export BASE64_KEY=`cat certificate/sasldap_CA_nopass.key | base64 | tr -d '\n'` > /dev/null 2>&1

cat <<EOF | tee assets/cert-manager-ca.yml  > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: sas-ldap-certificate
data:
  tls.crt: $BASE64_CERT
  tls.key: $BASE64_KEY
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: sas-ldap-cert-issuer
spec:
  ca:
    secretName: sas-ldap-certificate
EOF

if [ -s "assets/cert-manager-ca.yml" ]; then
        echo "$INFOMSG | Subprocess: Issuer and CA for cert-manager file created."
    else
        echo "$INFOMSG | Subprocess: Issuer and CA for cert-manager file creation failed."
        exit 1
fi

# ---------------------------------------------  endScript  ----------------------------------------------