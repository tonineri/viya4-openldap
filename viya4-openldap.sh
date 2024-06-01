#!/bin/bash

# -----------------------------------------------  header  -----------------------------------------------

# SAS Viya 4 - Persistent OpenLDAP Light
# Description: the script can fully prepare a bastion host for a SAS Viya 4 cluster creation and management on Azure, AWS and Google Cloud Plaform.

# Copyright © 2024, SAS Institute Inc., Cary, NC, USA. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# -----------------------------------------------  version -----------------------------------------------

V4LDAPVER="v1.0.0"        # viya4-openldap version

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
                    printf " ❌  $before_msg\n" 2>/dev/null
                    rm -f $TMPFILE
                    exit 1
                else
                    rm -f $TMPFILE
                    tput cnorm
                    printf "\033[2K" 2>/dev/null
                    printf " ✔  $after_msg\n" 2>/dev/null
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
  echo -e "________________________________________________________________"
}

printHeader() {
  divider
  echo -e "\n⮞               ${BOLD}Persistent OpenLDAP${NONE} for ${BCYAN}SAS Viya${NONE}              ⮜"
  divider
}
# -----------------------------------------------  options  ----------------------------------------------

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
	    echo -e "\n$V4LDAPVER | June 1st, 2024   "
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

# options | Check if the required options are provided
if [ -z "$NS" ]; then
  echo -e "\n$INFOMSG | Usage:"
  echo -e "$0 --namespace ${ITALIC}<desired-ldap-namespace-name>${NONE}"
  echo -e "$0 --version to see script version"
  exit 1
fi

# ----------------------------------------------- introHeader --------------------------------------------

printHeader

# ---------------------------------------------- prerequisites -------------------------------------------

## Check if kubectl, kustomize and ldap-utils are installed
echo -e "\n⮞ ${BYELLOW}Prerequisites Check${NONE}\n"

requiredPackages=("kubectl" "kustomize" "ldapadd" "nc")
for pkg in "${requiredPackages[@]}"; do
    execute \
      --title "Checking if ${CYAN}$pkg${NONE} is installed" \
      "which $pkg &>/dev/null" \
      --error "$ERRORMSG | ${CYAN}$pkg${NONE} is not installed"
done

## Check if namespace exists
checkNamespace() {
    if kubectl get ns "$NS" > /dev/null 2>&1; then
        return 0  # Namespace found
    else
        # Create the namespace if it doesn't exist
        if kubectl create namespace "$NS" > /dev/null 2>&1; then
            return 0  # Namespace created successfully
        else
            return 1  # Namespace creation failed
        fi
    fi
}

execute \
  --title "Checking namespace ${CYAN}$NS${NONE}" \
  checkNamespace \
  --error "$ERRORMSG | ${CYAN}$NS${NONE} namespace creation failed."

divider

# ---------------------------------------------- mainScript ----------------------------------------------

## Certificates
echo -e "\n⮞ ${BYELLOW}Certificate Generation for LDAP(S)${NONE}\n"
mkdir -p certificates > /dev/null 2>&1

### Self-signed CA
#### Generate self-signed CA key
generateCAkey() {
  if openssl genrsa -aes256 -passout pass:SAS-ld4p -out certificates/sasldap_CA.key 2048 > /dev/null 2>&1; then
    return 0 # CA private key generated
    if openssl rsa -in certificates/sasldap_CA.key -out certificates/sasldap_CA_nopass.key -passin pass:SAS-ld4p > /dev/null 2>&1; then
      return 0 # Removed CA private key passphrase
    fi
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
      -key certificates/sasldap_CA.key \
      -out certificates/sasldap_CA.crt \
      -passin pass:SAS-ld4p > /dev/null 2>&1; then
    return 0 # CA generated
  fi
}

execute \
  --title "Generating self-signed ${CYAN}CA certificate${NONE}" \
  generateCAcrt \
  --error "$ERRORMSG | ${CYAN}CA certificate${NONE} generation failed."


##### Check that all CA files were generated successfully
#CAfiles=("certificates/sasldap_CA.crt" "certificates/sasldap_CA_nopass.key" "certificates/sasldap_CA.key")
#checkCAfiles() {
#  for file in "${CAfiles[@]}"; do
#    if [ -s "$file" ]; then
#        return 0 # File exists
#    fi
#  done
#}
#
#execute \
#  --title "Checking if self-signed ${CYAN}CA files${NONE} were generated" \
#  checkCAfiles \
#  --error "$ERRORMSG | One or more ${CYAN}CA files${NONE} missing."
#
### Self-signed Server
#### Generate self-signed server private key
generateServerKey() {
  if openssl genrsa -out certificates/sasldap_server.key 2048 > /dev/null 2>&1; then
    return 0 # Server private key generated
  fi
}

execute \
  --title "Generating self-signed ${CYAN}Server private key${NONE}" \
  generateServerKey \
  --error "$ERRORMSG | ${CYAN}Server private key${NONE} generation failed."

#### Create OpenSSL config file for the self-signed Server certificate
createServerConf() {
  cat > certificates/sasldap_server.conf <<EOF
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
}

generateServerCSR() {
  createServerConf
  if openssl req -new \
      -key certificates/sasldap_server.key \
      -out certificates/sasldap_server.csr \
      -config certificates/sasldap_server.conf > /dev/null 2>&1; then
    return 0 # Server CSR generated
  fi
}

execute \
  --title "Generating self-signed ${CYAN}Server CSR${NONE}" \
  generateServerCSR \
  --error "$ERRORMSGG | ${CYAN}Server CSR${NONE} generation failed."

#### Generate Server certificate with the CA
generateServerCrt() {
  if openssl x509 -req \
      -in certificates/sasldap_server.csr \
      -CA certificates/sasldap_CA.crt \
      -CAkey certificates/sasldap_CA_nopass.key \
      -CAcreateserial \
      -out certificates/sasldap_server.crt \
      -days 3650 \
      -sha256 \
      -extensions v3_req \
      -extfile certificates/sasldap_server.conf > /dev/null 2>&1; then
    return 0 # Server certificate generated
  fi
}

execute \
  --title "Generating self-signed ${CYAN}Server certificate${NONE}" \
  generateServerCrt \
  --error "$ERRORMSG | ${CYAN}Server certificate${NONE} generation failed."

##### Check that all Server certificate files were generated successfully
#serverFiles=("certificates/sasldap_server.crt" "certificates/sasldap_server.key")
#checkServerFiles() {
#  for file in "${CcheckServerFiles[@]}"; do
#    if [ -s "$file" ]; then
#        return 0 # File exists
#    fi
#  done
#}
#
#execute \
#  --title "Checking if self-signed ${CYAN}Server files${NONE} were generated" \
#  checkCAfiles \
#  --error "$ERRORMSG | One or more ${CYAN}Server files${NONE} missing."
#
divider

## Kubernetes secrets
echo -e "\n⮞ ${BYELLOW}Kubernetes Secrets Generation${NONE}\n"

### CA secret
createCAsecret() {
  if kubectl create secret generic sas-ldap-ca-certificate \
      --from-file=ca.crt=certificates/sasldap_CA.crt \
      --from-file=ca.key=certificates/sasldap_CA_nopass.key \
      -n $NS > /dev/null 2>&1; then
    return 0 # CA secret created
  fi
}

execute \
  --title "Creating ${CYAN}CA secret${NONE}" \
  createCAsecret \
  --error "$ERRORMSG | ${CYAN}CA secret${NONE} creation failed."

### Server secret
createServerSecret() {
  if kubectl create secret generic sas-ldap-certificate \
      --from-file=tls.crt=certificates/sasldap_server.crt \
      --from-file=tls.key=certificates/sasldap_server.key \
      -n $NS > /dev/null 2>&1; then
    return 0 # Server secret created
  fi
}

execute \
  --title "Creating ${CYAN}Server secret${NONE}" \
  createServerSecret \
  --error "$ERRORMSG | ${CYAN}Server secret${NONE} creation failed."

divider

## Deploy OpenLDAP
echo -e "\n⮞ ${BYELLOW}OpenLDAP Deployment${NONE}\n"

### Build OpenLDAP deployment
buildOpenLDAP() {
  if kustomize build ./assets/ -o assets/${NS}-deployment.yaml | kubectl -n ${NS} apply -f - > /dev/null 2>&1; then
    return 0 # OpenLDAP deployment built
  fi
}

execute \
  --title "Building ${CYAN}OpenLDAP${NONE} deployment" \
  buildOpenLDAP \
  --error "$ERRORMSG | ${CYAN}OpenLDAP${NONE} deployment build failed."

### Apply OpenLDAP deployment
applyOpenLDAP() {
  if kubectl -n ${NS} apply -f assets/${NS}-deployment.yaml > /dev/null 2>&1; then
    return 0 # OpenLDAP deployment applied
  fi
}

execute \
  --title "Applying ${CYAN}OpenLDAP${NONE} deployment" \
  applyOpenLDAP \
  --error "$ERRORMSG | ${CYAN}OpenLDAP${NONE} deployment application failed."

### Wait for OpenLDAP server to start
podOpenLDAP=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}')
waitOpenLDAP() {
  if kubectl wait --for=condition=ready pod -l app=sas-ldap-server -n $NS > /dev/null 2>&1; then
    kubectl port-forward -n $NS $podOpenLDAP 1636:636 > /dev/null 2>&1 &
  fi
  # Wait for the local port to be open
  until nc -z localhost 1636; do
      sleep 1
  done
  kill $(jobs -p)
  return 0 # OpenLDAP server started
}

### Check if "slapd starting" message appears in the pod's logs
checkSlapdStarting() {
  waitOpenLDAP
  if kubectl logs -n $NS $podOpenLDAP | grep -q "slapd starting"; then
    return 0  # Return success if the message is found
  else
    return 1  # Return failure if the message is not found
  fi
}

### Wait until "slapd starting" message appears in the pod's logs
waitSlapdStarting() {
  secs=$1
  while [ $secs -gt 0 ]; do
    if checkSlapdStarting; then
      return 0  # Return success if the message is found
    else
      sleep 1
      : $((secs--))
    fi
  done
  echo -e "$ERRORMSG | Timeout: slapd starting message not found in pod's logs."
  return 1  # Return failure if the message is not found within the timeout
}

execute \
  --title "Waiting for ${CYAN}OpenLDAP${NONE} server to start" \
  waitSlapdStarting 120 \
  --error "$ERRORMSG | ${CYAN}OpenLDAP${NONE} server failed to start."

divider

#
#echo -e "$INFOMSG | OpenLDAP deployed."
#echo -e "________________________________________________________________"
#echo -e "\nThese are the default account and passwords available in SASLDAP:"
#echo -e "\n| username | password      |"
#echo -e "|----------|---------------|"
#echo -e "| admin    | SAS@ldapAdm1n |"
#echo -e "| sasbind  | SAS@ldapB1nd  |"
#
## Print access info
#echo -e "________________________________________________________________"
#echo -e "\nWhile script running, you can access the LDAP from your client via LDAP browser using following parameters:"
#echo -e "Host:   IP/hostname of this host"
#echo -e "Port:   1636"
#echo -e "User:   cn=admin,dc=sasldap,dc=com"
#echo -e "Pass:   SAS@ldapAdm1n"
#echo -e "BaseDN: dc=sasldap,dc=com"
#echo -e "Certificate: $PWD/certificates/sasldap_CA.crt"
#echo -e "________________________________________________________________"
#echo -e "\n$OPTMSG | You can upload the default OU/User/Group structure by launching the following command ${BOLD}on a new terminal while port-forwarding is running${NONE}:"
#echo -e "${ITALIC}LDAPTLS_REQCERT=allow LDAPTLS_CACERT="$PWD/certificates/sasldap_CA.crt" ldapadd -x -H ldaps://localhost:1636 -D cn=admin,dc=sasldap,dc=com -w SAS@ldapAdm1n -f $PWD/samples/default_ldap_structure.ldif${NONE}"
#echo -e "\n$NOTEMSG | These are the default accounts and passwords that would be deployed in the LDAP, ${BOLD}${YELLOW}if${NONE} you'd choose to upload the default structure:"
#echo -e "\n| username | password      |"
#echo -e "|----------|---------------|"
#echo -e "| admin    | SAS@ldapAdm1n |"
#echo -e "| sasbind  | SAS@ldapB1nd  |"
#echo -e "| sas      | lnxsas        |"
#echo -e "| cas      | lnxsas        |"
#echo -e "| sasadm   | lnxsas        |"
#echo -e "| sasdev   | lnxsas        |"
#echo -e "| sasuser  | lnxsas        |"
#echo -e "________________________________________________________________"
#echo -e ""
#
## Function to check if "slapd starting" message appears in the pod's logs
#check_slapd_starting() {
#    pod_name=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}')
#    if kubectl logs -n $NS $pod_name | grep -q "slapd starting"; then
#        return 0  # Return success if the message is found
#    else
#        return 1  # Return failure if the message is not found
#    fi
#}
#
## Function to wait until "slapd starting" message appears in the pod's logs
#wait_for_slapd_starting() {
#    secs=$1
#    while [ $secs -gt 0 ]; do
#        if check_slapd_starting; then
#            echo -e ""
#            echo -e "$INFOMSG | OpenLDAP TLS configuration completed."
#            echo -e "________________________________________________________________"
#            echo -e "\n$INFOMSG | Port-forwarding started. ${BOLD}${RED}Ctrl-C${NONE} to stop it."
#            return 0  # Return success if the message is found
#        else
#            echo -ne "$INFOMSG | The script is waiting for${BOLD}${YELLOW} $secs ${NONE}seconds for slapd to start...\033[0K\r"
#            sleep 1
#            : $((secs--))
#        fi
#    done
#    echo -e "$ERRORMSG | Timeout: slapd starting message not found in pod's logs."
#    return 1  # Return failure if the message is not found within the timeout
#}
#
## Call the function to wait for "slapd starting" message
#wait_for_slapd_starting 120
#
## Cleanup function to be trapped
#cleanup() {
#  echo -e "________________________________________________________________"
#  echo -e "\n$INFOMSG | Port forwarding stopped!"
#  echo -e "$INFOMSG | To access your LDAP again, launch the following command before accessing it via LDAP browser:"
#  echo -e "${ITALIC}kubectl --namespace $NS port-forward --address localhost svc/sas-ldap-service 1636:636${NONE}"
#  echo -e ""
#  exit 0
#}
#
## Trap Ctrl-C and call cleanup function
#trap cleanup INT
#
## Port-forward until Ctrl-C
#while true; do
#  kubectl --namespace "$NS" port-forward --address localhost svc/sas-ldap-service 1636:636
#done
#
#echo -e "\n$NOTEMSG | Copy the ${ITALIC}../certificates/sasldap_CA.crt${NONE} file in your ${ITALIC}\$deploy/site-config/security/cacerts${NONE} directory and define it in your ${ITALIC}customer-provided-ca-certificates.yaml${NONE} file."
#echo -e "        If no modifications were made to the script, consider copying the ${ITALIC}samples/sitedefault.yaml${NONE} to ${ITALIC}\$deploy/site-config/sitedefault.yaml${NONE}."
#echo -e "        Ensure you also defined it in the 'transformers' section of your ${ITALIC}\$deploy/kustomization.yaml${NONE} file."
#exit 1
#
## ----------------------------------------------  scriptEnd  ---------------------------------------------