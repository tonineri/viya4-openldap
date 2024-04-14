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

# Deploy Issuer
echo -e "________________________________________________________________"
echo -e "\n$INFOMSG | Executing CA creation subprocess..."
chmod +x assets/certificate_generation.sh > /dev/null 2>&1
sh assets/certificate_generation.sh
echo -e "$INFOMSG | CA creation subprocess completed."
kubectl -n ${NS} apply -f assets/cert-manager-ca.yml > /dev/null 2>&1
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
echo -e "Certificate: $PWD/certificate/sasldap_CA.crt"
echo -e "________________________________________________________________"
echo -e "\n$OPTMSG | You can upload the default OU/User/Group structure by launching the following command ${BOLD}on a new terminal while port-forwarding is running${NONE}:"
echo -e "${ITALIC}LDAPTLS_REQCERT=allow LDAPTLS_CACERT="$PWD/certificate/sasldap_CA.crt" ldapadd -x -H ldaps://localhost:1636 -D cn=admin,dc=sasldap,dc=com -w SAS@ldapAdm1n -f $PWD/samples/default_ldap_structure.ldif${NONE}"
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
  echo -e "${ITALIC}kubectl --namespace $NS port-forward --address 0.0.0.0 svc/sas-ldap-service 1636:636${NONE}"
  echo -e ""
  exit 0
}

# Trap Ctrl-C and call cleanup function
trap cleanup INT

# Port-forward until Ctrl-C

while true; do
  kubectl --namespace "$NS" port-forward --address 0.0.0.0 svc/sas-ldap-service 1636:636
done

echo -e "\n$NOTEMSG | Copy the ${ITALIC}../certificate/sasldap_CA.crt${NONE} file in your ${ITALIC}\$deploy/site-config/security/cacerts${NONE} directory and define it in your ${ITALIC}customer-provided-ca-certificates.yaml${NONE} file."
echo -e "        If no modifications were made to the script, consider copying the ${ITALIC}samples/sitedefault.yaml${NONE} to ${ITALIC}\$deploy/site-config/sitedefault.yaml${NONE}."
echo -e "        Ensure you also defined it in the 'transformers' section of your ${ITALIC}\$deploy/kustomization.yaml${NONE} file."
exit 1

# ----------------------------------------------  scriptEnd  ---------------------------------------------