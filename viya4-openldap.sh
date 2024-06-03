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
  echo -e "\n________________________________________________________________"
}

printHeader() {
  echo -e "\n________________________________________________________________"
  echo -e "\n                ${BOLD}Persistent OpenLDAP${NONE} for ${BCYAN}SAS Viya${NONE}               "
  echo -e "________________________________________________________________"
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
echo -e "\n⮞  ${BYELLOW}Prerequisites Check${NONE}\n"

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
    return 0 # Namespace found
  else
    # Create the namespace if it doesn't exist
    if kubectl create namespace "$NS" > /dev/null 2>&1; then
      return 0 # Namespace created successfully
    else
      return 1 # Namespace creation failed
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
echo -e "\n⮞  ${BYELLOW}Certificate Generation for LDAP(S)${NONE}\n"
mkdir -p assets/certificates > /dev/null 2>&1

### Self-signed CA
#### Generate self-signed CA key
generateCAkey() {
  if openssl genrsa -aes256 -passout pass:SAS-ld4p -out assets/certificates/sasldap_CA.key 2048 > /dev/null 2>&1; then
    if openssl rsa -in assets/certificates/sasldap_CA.key -out assets/certificates/sasldap_CA_nopass.key -passin pass:SAS-ld4p > /dev/null 2>&1; then
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
      -key assets/certificates/sasldap_CA.key \
      -out assets/certificates/sasldap_CA.crt \
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
  if openssl genrsa -out assets/certificates/sasldap_server.key 2048 > /dev/null 2>&1; then
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
  cat > assets/certificates/sasldap_server.conf <<EOF
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
      -key assets/certificates/sasldap_server.key \
      -out assets/certificates/sasldap_server.csr \
      -config assets/certificates/sasldap_server.conf > /dev/null 2>&1; then
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
      -in assets/certificates/sasldap_server.csr \
      -CA assets/certificates/sasldap_CA.crt \
      -CAkey assets/certificates/sasldap_CA_nopass.key \
      -CAcreateserial \
      -out assets/certificates/sasldap_server.crt \
      -days 3650 \
      -sha256 \
      -extensions v3_req \
      -extfile assets/certificates/sasldap_server.conf > /dev/null 2>&1; then
    return 0 # Server certificate generated
  else
    return 1 # Failed to generate Server certificate
  fi
}

execute \
  --title "Generating self-signed ${CYAN}Server certificate${NONE}" \
  generateServerCrt \
  --error "$ERRORMSG | ${CYAN}Server certificate${NONE} generation failed."

divider

## Deploy OpenLDAP
echo -e "\n⮞  ${BYELLOW}OpenLDAP Deployment${NONE}\n"

### Build OpenLDAP deployment
buildOpenLDAP() {
  if kustomize build ./assets/ -o ${NS}-deployment.yaml > /dev/null 2>&1; then
    return 0 # OpenLDAP deployment built
  else
    return 1 # OpenLDAP deployment build failed
  fi
}

execute \
  --title "Building ${CYAN}OpenLDAP${NONE} deployment" \
  buildOpenLDAP \
  --error "$ERRORMSG | ${CYAN}OpenLDAP${NONE} deployment build failed."

### Apply OpenLDAP deployment
applyOpenLDAP() {
  if kubectl -n ${NS} apply -f ${NS}-deployment.yaml > /dev/null 2>&1; then
    return 0 # OpenLDAP deployment applied
  else
    return 1 # OpenLDAP deployment application failed
  fi
}

execute \
  --title "Applying ${CYAN}OpenLDAP${NONE} deployment" \
  applyOpenLDAP \
  --error "$ERRORMSG | ${CYAN}OpenLDAP${NONE} deployment application failed."

### Wait for OpenLDAP server to start
waitForOpenLDAP() {
  local secs=$1
  local podOpenLDAP
  local port_forward_pid
  podOpenLDAP=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}')

  # Wait for pod to be ready
  if kubectl wait --for=condition=ready pod/$podOpenLDAP -n $NS; then
    kubectl port-forward -n $NS $podOpenLDAP 1389:1389 > /dev/null 2>&1 &
    port_forward_pid=$!
  else
    return 1 # Failed to find the pod or pod not ready
  fi

  # Wait for the local port to be open
  until nc -z localhost 1389; do
      sleep 1
  done

  # Check if "slapd starting" message appears in the pod's logs
  while [ $secs -gt 0 ]; do
    if kubectl logs -n $NS $podOpenLDAP | grep -q "slapd starting"; then
      kill $port_forward_pid
      wait $port_forward_pid 2>/dev/null
      return 0 # Return success if the message is found
    else
      sleep 1
      ((secs--))
    fi
  done

  kill $port_forward_pid
  wait $port_forward_pid 2>/dev/null
  echo -e "$ERRORMSG | Timeout: 'slapd starting' message not found in logs"
  return 1 # Return failure if the message is not found within the timeout
}

execute \
  --title "Starting ${CYAN}OpenLDAP${NONE} server" \
  "waitForOpenLDAP 120" \
  --error "$ERRORMSG | ${CYAN}OpenLDAP${NONE} server failed to start."

if [ $? -eq 0 ]; then
  OpenLDAPdeployed="YES"
else
  OpenLDAPdeployed="NO"
fi

divider

## OpenLDAP info
### Print connection info
printConnectionInfo() {
  echo ""
  echo -e "⮞  ${CYAN}OpenLDAP${NONE} connection info"
  sleep 0.5
  echo ""
  echo -e "   Host:   IP/hostname of this host"
  echo -e "   Port:   1389"
  echo -e "   User:   cn=admin,dc=sasldap,dc=com"
  echo -e "   Pass:   SAS@ldapAdm1n"
  echo -e "   BaseDN: dc=sasldap,dc=com"
  echo -e "   CA:     $PWD/assets/certificates/sasldap_CA.crt"
  sleep 0.5
  echo ""
  echo -e "   $NOTEMSG | To manage your LDAP, launch the following command ${YELLOW}before${NONE} accessing it via LDAP browser:"
  echo -e "   ${ITALIC}kubectl --namespace $NS port-forward --address localhost svc/sas-ldap-service 1389:1389${NONE}"
}

### Print default tree
printDefaultTree() {
  echo ""
  echo -e "🌐 dc=sasldap,dc=com"
  sleep 0.5
  echo -e " ├──🛠️ cn=admin   | 🔑 SAS@ldapAdm1n"
  echo -e " └──🔗 uid=sasbind | 🔑 SAS@ldapB1nd"
}

### Print SAS tree
printSAStree() {
  echo ""
  echo -e "🌐 dc=sasldap,dc=com"
  sleep 0.5
  echo -e " ├──🛠️ cn=admin   | 🔑 SAS@ldapAdm1n"
  echo -e " ├──🔗 uid=sasbind | 🔑 SAS@ldapB1nd"
  echo -e " ├──📁 ou=groups"
  sleep 0.5
  echo -e " │   ├──👥 cn=sas       | 🤝 cas, sas"
  echo -e " │   ├──👥 cn=sasadmins | 🤝 sasadm"
  echo -e " │   ├──👥 cn=sasdevs   | 🤝 sasdev"
  echo -e " │   └──👥 cn=sasusers  | 🤝 sasuser"
  sleep 0.5
  echo -e " └──📁 ou=users"
  echo -e "     ├──👤 uid=cas      | 🔑 lnxsas"
  echo -e "     ├──👤 uid=sas      | 🔑 lnxsas"
  echo -e "     ├──👤 uid=sasadm   | 🔑 lnxsas"
  echo -e "     ├──👤 uid=sasdev   | 🔑 lnxsas"
  echo -e "     └──👤 uid=sasuser  | 🔑 lnxsas"
}

printGoodbye(){
  echo ""
  echo -e "${BOLD}Persistent OpenLDAP${NONE} for ${BCYAN}SAS Viya${NONE} deployed successfully!"
  sleep 0.5
  echo -e "This script will now exit."
}

## OpenLDAP info
deploySASViyaStructure() {
  # Launch port-forward in the background
  kubectl --namespace "$NS" port-forward --address localhost svc/sas-ldap-service 1389:1389 > /dev/null 2>&1 &
  port_forward_pid=$!
  sleep 5 # Give port-forward some time to set up

  # Add the default LDAP structure
  LDAPTLS_REQCERT=allow LDAPTLS_CACERT="assets/certificates/sasldap_CA.crt" \
  ldapadd -x \
  -H ldap://localhost:1389 \
  -D cn=admin,dc=sasldap,dc=com \
  -w SAS@ldapAdm1n \
  -f samples/sas_ldap_structure.ldif > /dev/null 2>&1

  # Check if ldapadd was successful
  if [ $? -eq 0 ]; then
    # Kill the background port-forward task
    kill $port_forward_pid
    wait $port_forward_pid 2>/dev/null
    return 0
  else
    echo -e "$ERRORMSG | ldapadd command failed. Check if the certificate and credentials are correct."
    kill $port_forward_pid
    wait $port_forward_pid 2>/dev/null
    return 1
  fi
}

resetSasbindPassword() {
  local podOpenLDAP=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}')
  local sasbindPassword="SAS@ldapB1nd"
  local ldifTempFile="assets/change-sasbind-password.ldif"

  # Generate hashed password
  local hashedPassword=$(kubectl -s $NS exec -it slappasswd -s $sasbindPassword | tr -d '\r')

  # Create the LDIF content
  local ldifContent=$(cat <<EOF
dn: uid=sasbind,dc=sasldap,dc=com
changetype: modify
replace: userPassword
userPassword: $hashedPassword
EOF
  )
  
  # Create LDIF file locally
  echo "$ldifContent" > $ldifTempFile
  
  # Copy the LDIF file to the OpenLDAP container
  kubectl cp $ldifTempFile $podOpenLDAP:/custom-ldifs/change-sasbind-password.ldif

  # Apply the LDIF file using ldapmodify
  kubectl exec -it $podOpenLDAP -- ldapmodify -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/change-sasbind-password.ldif

  # Clean up
  rm -f $ldifTempFile
  kubectl exec -it $podOpenLDAP -- rm /custom-ldifs/change-sasbind-password.ldif

}

applyMemberOf(){
  local podOpenLDAP
  local port_forward_pid

  podOpenLDAP=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}')

  sleep 15
  kubectl -n $NS exec -it $podOpenLDAP -- ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/0-load-memberof-module.ldif
  kubectl -n $NS exec -it $podOpenLDAP -- ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/1-configure-memberof-overlay.ldif
  #kubectl -n $NS exec -it $podOpenLDAP -- ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/2-reset-sasbind-pwd.ldif
  sleep 5
  kubectl -n $NS delete pod $podOpenLDAP
  sleep 15
  if kubectl wait --for=condition=ready pod/$podOpenLDAP -n $NS; then
    sleep 5
  fi
}

if [ "$OpenLDAPdeployed" = "YES" ]; then
  echo -e "\n⮞  ${BYELLOW}OpenLDAP configuration${NONE}\n"
  
  # Configure OpenLDAP initial structure
  execute \
    --title "Configuring ${CYAN}OpenLDAP${NONE} initial structure" \
    "applyMemberOf && resetSasbindPassword" \
    --error "$ERRORMSG | Failed to configure ${CYAN}OpenLDAP${NONE} initial structure."

  # Print current OpenLDAP structure
  echo -e "\nCurrent ${CYAN}OpenLDAP${NONE} structure:"
  printDefaultTree
  divider

  # Prompt for deploying SAS Viya-ready structure
  while true; do
    echo -e "\nWould you like to deploy the ${CYAN}SAS Viya${NONE}-ready structure? [${BYELLOW}y${NONE}/${BYELLOW}n${NONE}]:"
    read -r user_input

    if [[ "$user_input" =~ ^[Yy]$ ]]; then
      echo ""
      if execute \
          --title "Deploying the ${CYAN}SAS Viya${NONE}-ready structure" \
          deploySASViyaStructure \
          --error "$ERRORMSG | Failed to deploy ${CYAN}SAS Viya${NONE}-ready structure."; then
        echo ""
        echo -e "\nThis is the new ${CYAN}OpenLDAP${NONE} structure:"
        printSAStree
        sleep 0.5
        divider
        printConnectionInfo
        sleep 0.5
        divider
        printGoodbye
      else
        echo -e "$ERRORMSG | Failed to deploy ${CYAN}SAS Viya${NONE}-ready structure."
        exit 1 # SAS Viya-ready structure failed to deploy
      fi
      break

    elif [[ "$user_input" =~ ^[Nn]$ ]]; then
      printConnectionInfo
      sleep 0.5
      divider
      printGoodbye
      break

    else
      echo -e "\n${ERRORMSG} | Accepted inputs: ${BYELLOW}y${NONE}/${BYELLOW}n${NONE}"
    fi
  done
else
  echo -e "\n${ERRORMSG} | ${CYAN}OpenLDAP${NONE} deployment failed.\n"
  exit 1
fi
sleep 0.5
divider
echo -e "\n \n"

## ----------------------------------------------  scriptEnd  ---------------------------------------------
