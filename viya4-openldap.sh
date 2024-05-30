#!/bin/bash

# -----------------------------------------------  header  -----------------------------------------------

# SAS Viya 4 - Persistent OpenLDAP Light
# Description: the script can fully prepare a bastion host for a SAS Viya 4 cluster creation and management on Azure, AWS and Google Cloud Plaform.

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

# textStyle | messageLevels
INFOMSG="${BOLD}${CYAN}INFO${NONE}"
WARNMSG="${BOLD}${YELLOW}WARN${NONE}"
ERRORMSG="${BOLD}${RED}ERROR${NONE}"
NOTEMSG="${BOLD}${CYAN}NOTE${NONE}"
OPTMSG="${BOLD}${YELLOW}OPTIONAL${NONE}"

# -----------------------------------------------  options  ----------------------------------------------

V4LDAPVER="v1.0.0"        # viya4-openldap version

# Initialize variables
PWD=$PWD
NS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --namespace)
      if [ -n "$2" ]; then
        NS="$2"
        shift
      else
        echo -e "\n$ERRORMSG | Namespace not provided. Please use the ${ITALIC}--namespace${NONE} option."
        exit 1
      fi
      ;;
    --version)
	    echo -e "\n$V4LDAPVER | April 14th, 2024   "
	    echo -e ""
      exit 0
      ;;
    *)
      echo -e "\n$ERRORMSG | Unknown option: $1"
      echo -e "____________________________________________"
      echo -e "\n$INFOMSG | Usage:"
  	  echo -e "$0 --namespace ${ITALIC}<desired-ldap-namespace-name>${NONE}"
  	  echo -e "$0 --version to see script version"
      exit 1
      ;;
  esac
  shift
done

# Check if the required options are provided
if [ -z "$NS" ]; then
  echo -e "\n$INFOMSG | Usage:"
  echo -e "$0 --namespace ${ITALIC}<desired-ldap-namespace-name>${NONE}"
  echo -e "$0 --version to see script version"
  exit 1
fi

# -------------------------------------------- preRequirements -------------------------------------------

# Check if kubectl, kustomize and ldap-utils are installed
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo -e "\n$ERRORMSG | ${ITALIC}$1${NONE} not found. Please install ${ITALIC}$1${NONE} before running this script."
    exit 1
  fi
}
check_command kubectl
check_command kustomize
check_command ldapadd
check_command nc

# ---------------------------------------------- mainScript ----------------------------------------------

# Check if namespace exists
if kubectl get ns "$NS" > /dev/null 2>&1; then
  echo -e "\n$INFOMSG | $NS namespace found."
else
  # Create the namespace if it doesn't exist
  if kubectl create namespace "$NS" > /dev/null 2>&1; then
    echo -e "\n$INFOMSG | $NS namespace created."
  else
    echo -e "\n$ERRORMSG | $NS namespace could not be created."
  fi
fi

# Create certificates
echo -e "________________________________________________________________"
echo -e "\n$INFOMSG | Creating certificates..."
mkdir -p certificates > /dev/null 2>&1
# Create CA private key
openssl genrsa -aes256 -passout pass:SAS-ld4p -out certificates/sasldap_CA.key 2048 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to create CA private key."
    exit 1
fi

# Create CA certificate
openssl req -new -x509 -sha256 -extensions v3_ca \
    -days 3650 \
    -subj "/C=IT/ST=Lombardy/L=Milan/O=SASLDAP/CN=SAS Viya LDAP Root CA/emailAddress=noreply@sasldap.com" \
    -key certificates/sasldap_CA.key \
    -out certificates/sasldap_CA.crt \
    -passin pass:SAS-ld4p > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to create CA certificate."
    exit 1
fi

# Remove passphrase from CA key
openssl rsa -in certificates/sasldap_CA.key -out certificates/sasldap_CA_nopass.key -passin pass:SAS-ld4p > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to remove passphrase from CA private key."
    exit 1
fi

# Check that all files were created successfully
CERTFILES="certificates/sasldap_CA.crt certificates/sasldap_CA_nopass.key certificates/sasldap_CA.key"
for file in $CERTFILES; do
    if [ -s "$file" ]; then
        echo -e "$INFOMSG | $file created."
    else
        echo -e "$ERRORMSG | Certificates not created correctly."
        exit 1
    fi
done

# Create server private key
openssl genrsa -out certificates/sasldap_server.key 2048 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to create server private key."
    exit 1
fi

# Create OpenSSL config file for the server certificate
cat > certificates/sasldap_server.cnf <<EOF
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
O  = SASLDAP
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

# Create server certificate signing request (CSR)
openssl req -new -key certificates/sasldap_server.key -out certificates/sasldap_server.csr \
    -config certificates/sasldap_server.cnf > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to create server CSR."
    exit 1
fi

# Sign the server certificate with the CA
openssl x509 -req -in certificates/sasldap_server.csr -CA certificates/sasldap_CA.crt -CAkey certificates/sasldap_CA_nopass.key \
    -CAcreateserial -out certificates/sasldap_server.crt -days 3650 -sha256 \
    -extensions v3_req -extfile certificates/sasldap_server.cnf > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to sign server certificate."
    exit 1
fi

# Check that the server certificate and key were created successfully
SERVER_CERTFILES="certificates/sasldap_server.crt certificates/sasldap_server.key"
for file in $SERVER_CERTFILES; do
    if [ -s "$file" ]; then
        echo -e "$INFOMSG | $file created."
    else
        echo -e "$ERRORMSG | Server certificates not created correctly."
        exit 1
    fi
done

# Create Kubernetes secrets
echo -e "$INFOMSG | Creating Kubernetes secrets..."

kubectl create secret generic sas-ldap-ca-certificate --from-file=ca.crt=certificates/sasldap_CA.crt --from-file=ca.key=certificates/sasldap_CA_nopass.key -n $NS
if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to create CA secret."
    exit 1
fi

kubectl create secret generic sas-ldap-certificate --from-file=tls.crt=certificates/sasldap_server.crt --from-file=tls.key=certificates/sasldap_server.key -n $NS
if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to create server certificate secret."
    exit 1
fi

echo -e "$INFOMSG | Kubernetes secrets created successfully."
echo -e "$INFOMSG | Certificates created."
#kubectl -n ${NS} apply -f assets/cert-manager-ca.yml > /dev/null 2>&1
echo -e "________________________________________________________________"

# Deploy OpenLDAP
echo -e "\n$INFOMSG | Deploying OpenLDAP..."
kustomize build ./assets/ | kubectl -n ${NS} apply -f - > /dev/null 2>&1

# Wait pod to start and print default users/passwords
if kubectl wait --for=condition=ready pod -l app=sas-ldap-server -n $NS > /dev/null 2>&1; then
  kubectl port-forward -n $NS $(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}') 1636:636 > /dev/null 2>&1 &
fi
# Wait for the local port to be open
until nc -z localhost 1636; do
    sleep 1
done
kill $(jobs -p)

#if kubectl wait --for=condition=ready pod -l app=sas-ldap-server -n $NS > /dev/null 2>&1; then
  echo -e "$INFOMSG | OpenLDAP deployed."
	echo -e "________________________________________________________________"
	echo -e "\nThese are the default account and passwords available in SASLDAP:"
	echo -e "\n| username | password      |"
	echo -e "|----------|---------------|"
	echo -e "| admin    | SAS@ldapAdm1n |"
	echo -e "| sasbind  | SAS@ldapB1nd  |"

# Print access info
echo -e "________________________________________________________________"
echo -e "\nWhile script running, you can access the LDAP from your client via LDAP browser using following parameters:"
echo -e "Host:   IP/hostname of this host"
echo -e "Port:   1636"
echo -e "User:   cn=admin,dc=sasldap,dc=com"
echo -e "Pass:   SAS@ldapAdm1n"
echo -e "BaseDN: dc=sasldap,dc=com"
echo -e "Certificate: $PWD/certificates/sasldap_CA.crt"
echo -e "________________________________________________________________"
echo -e "\n$OPTMSG | You can upload the default OU/User/Group structure by launching the following command ${BOLD}on a new terminal while port-forwarding is running${NONE}:"
echo -e "${ITALIC}LDAPTLS_REQCERT=allow LDAPTLS_CACERT="$PWD/certificates/sasldap_CA.crt" ldapadd -x -H ldaps://localhost:1636 -D cn=admin,dc=sasldap,dc=com -w SAS@ldapAdm1n -f $PWD/samples/default_ldap_structure.ldif${NONE}"
echo -e "\n$NOTEMSG | These are the default accounts and passwords that would be deployed in the LDAP, ${BOLD}${YELLOW}if${NONE} you'd choose to upload the default structure:"
echo -e "\n| username | password      |"
echo -e "|----------|---------------|"
echo -e "| admin    | SAS@ldapAdm1n |"
echo -e "| sasbind  | SAS@ldapB1nd  |"
echo -e "| sas      | lnxsas        |"
echo -e "| cas      | lnxsas        |"
echo -e "| sasadm   | lnxsas        |"
echo -e "| sasdev   | lnxsas        |"
echo -e "| sasuser  | lnxsas        |"
echo -e "________________________________________________________________"
echo -e ""

# Function to check if "slapd starting" message appears in the pod's logs
check_slapd_starting() {
    pod_name=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}')
    if kubectl logs -n $NS $pod_name | grep -q "slapd starting"; then
        return 0  # Return success if the message is found
    else
        return 1  # Return failure if the message is not found
    fi
}

# Function to wait until "slapd starting" message appears in the pod's logs
wait_for_slapd_starting() {
    secs=$1
    while [ $secs -gt 0 ]; do
        if check_slapd_starting; then
            echo -e ""
            echo -e "$INFOMSG | OpenLDAP TLS configuration completed."
            echo -e "________________________________________________________________"
            echo -e "\n$INFOMSG | Port-forwarding started. ${BOLD}${RED}Ctrl-C${NONE} to stop it."
            return 0  # Return success if the message is found
        else
            echo -ne "$INFOMSG | The script is waiting for${BOLD}${YELLOW} $secs ${NONE}seconds for slapd to start...\033[0K\r"
            sleep 1
            : $((secs--))
        fi
    done
    echo -e "$ERRORMSG | Timeout: slapd starting message not found in pod's logs."
    return 1  # Return failure if the message is not found within the timeout
}

# Call the function to wait for "slapd starting" message
wait_for_slapd_starting 120

# Cleanup function to be trapped
cleanup() {
  echo -e "________________________________________________________________"
  echo -e "\n$INFOMSG | Port forwarding stopped!"
  echo -e "$INFOMSG | To access your LDAP again, launch the following command before accessing it via LDAP browser:"
  echo -e "${ITALIC}kubectl --namespace $NS port-forward --address localhost svc/sas-ldap-service 1636:636${NONE}"
  echo -e ""
  exit 0
}

# Trap Ctrl-C and call cleanup function
trap cleanup INT

# Port-forward until Ctrl-C

while true; do
  kubectl --namespace "$NS" port-forward --address localhost svc/sas-ldap-service 1636:636
done

echo -e "\n$NOTEMSG | Copy the ${ITALIC}../certificates/sasldap_CA.crt${NONE} file in your ${ITALIC}\$deploy/site-config/security/cacerts${NONE} directory and define it in your ${ITALIC}customer-provided-ca-certificates.yaml${NONE} file."
echo -e "        If no modifications were made to the script, consider copying the ${ITALIC}samples/sitedefault.yaml${NONE} to ${ITALIC}\$deploy/site-config/sitedefault.yaml${NONE}."
echo -e "        Ensure you also defined it in the 'transformers' section of your ${ITALIC}\$deploy/kustomization.yaml${NONE} file."
exit 1

# ----------------------------------------------  scriptEnd  ---------------------------------------------