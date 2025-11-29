#!/bin/bash

# -----------------------------------------------  header  -----------------------------------------------

# SAS Viya 4 - Persistent OpenLDAP Light
# Description: This script fully prepares and deploys an OpenLDAP server for use with SAS Viya 4.

# Copyright © 2025, Antonio Neri <antoneri@proton.me>
# SPDX-License-Identifier: Apache-2.0

# -----------------------------------------------  version -----------------------------------------------

V4LDAPVER="v1.1.1"                   # viya4-openldap version
V4LDAPRELDATE="November 29th, 2025"  # viya4-openldap version release date

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
TMPERROR="/tmp/$$$RANDOM.err"
VERBOSE=0

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
                    
                    # Show error details in verbose mode
                    if [[ $VERBOSE -eq 1 ]] && [[ -f $TMPERROR ]]; then
                        echo -e "\n   ${ERRORMSG} | Error details:"
                        while IFS= read -r line; do
                            echo -e "   ${RED}│${NONE} $line"
                        done < "$TMPERROR"
                        echo ""
                    fi
                    
                    rm -f $TMPFILE $TMPERROR
                    exit 1
                else
                    rm -f $TMPFILE $TMPERROR
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
        # Clear error file
        > "$TMPERROR"
        
        for arg in "${args[@]}"; do
            if [[ $VERBOSE -eq 1 ]]; then
                # Verbose mode: show output
                eval "$arg" 2>&1 | tee -a "$TMPERROR"
                status=${PIPESTATUS[0]}
            else
                # Normal mode: capture stderr only
                eval "$arg" 2>"$TMPERROR" 1>/dev/null
                status=$?
            fi
            
            if [[ $status -ne 0 ]]; then
                # Add custom error message if provided
                if [[ ${#errors[@]} -gt 0 ]]; then
                    echo "${errors[0]}" >> "$TMPERROR"
                fi
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

# Verbose logging function
vlog() {
  if [[ $VERBOSE -eq 1 ]]; then
    echo -e "   ${CYAN}[VERBOSE]${NONE} $1"
  fi
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
    -v|--verbose)
      VERBOSE=1
      echo -e "\n${INFOMSG} | Verbose mode enabled"
      ;;
    --version)
	    echo -e "\n$V4LDAPVER | $V4LDAPRELDATE"
	    echo -e ""
      exit 0
      ;;
    *)
      echo -e "\n$ERRORMSG | Unknown option: $1"
      echo -e "____________________________________________"
      echo -e "\n$INFOMSG | Usage:"
  	  echo -e "$0 --namespace ${ITALIC}<desired-ldap-namespace-name>${NONE} [-v|--verbose]"
  	  echo -e "$0 --version to see script version"
      exit 1
      ;;
  esac
  shift
done

# options | Check if the required options are provided
if [ -z "$NS" ]; then
  echo -e "\n$INFOMSG | Usage:"
  echo -e "$0 --namespace ${ITALIC}<desired-ldap-namespace-name>${NONE} [-v|--verbose]"
  echo -e "$0 --version to see script version"
  exit 1
fi

# ----------------------------------------------- introHeader --------------------------------------------

printHeader

# ---------------------------------------------- prerequisites -------------------------------------------

## Check if kubectl, kustomize and ldap-utils are installed
echo -e "\n⮞  ${BYELLOW}Prerequisites Check${NONE}\n"

requiredPackages=("kubectl" "kustomize")
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
  vlog "Replacing namespace placeholder in namespace.yaml with: $NS"
  
  if ! sed -i "s|{{ SASLDAP-NAMESPACE }}|$NS|g" assets/namespace.yaml > /dev/null 2>&1; then
    echo -e "$ERRORMSG | Failed to edit namespace.yaml" >&2
    return 1 # namespace.yaml edit failed
  fi
  
  vlog "Running kustomize build to generate deployment manifest..."
  
  if ! kustomize build ./assets/ -o ${NS}-deployment.yaml > /dev/null 2>&1; then
    echo -e "$ERRORMSG | Kustomize build failed" >&2
    return 1 # OpenLDAP deployment build failed
  fi
  
  vlog "Deployment manifest created: ${NS}-deployment.yaml"
  
  return 0
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
  local podOpenLDAP=""
  
  vlog "Waiting for pod to be created..."

  local wait_secs=60
  while [ $wait_secs -gt 0 ]; do
    podOpenLDAP=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$podOpenLDAP" ]; then
      vlog "Pod created: $podOpenLDAP"
      break
    fi
    sleep 1
    ((wait_secs--))
  done
  
  if [ -z "$podOpenLDAP" ]; then
    echo -e "$ERRORMSG | Pod not created within timeout" >&2
    return 1
  fi

  vlog "Waiting for 'slapd starting' message in logs (timeout: ${secs}s)..."
  
  # Check if "slapd starting" message appears in the pod's logs
  while [ $secs -gt 0 ]; do
    if kubectl logs -n $NS $podOpenLDAP 2>/dev/null | grep -q "slapd starting"; then
      vlog "LDAP server started successfully"
      return 0 # Return success if the message is found
    else
      sleep 1
      ((secs--))
    fi
  done

  echo -e "$ERRORMSG | Timeout: 'slapd starting' message not found in logs" >&2
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

## OpenLDAP configuration
### Print connection info
printConnectionInfo() {
  echo ""
  echo -e "⮞  ${CYAN}OpenLDAP${NONE} connection info"
  sleep 0.5
  echo ""
  echo -e "   Host:   IP/hostname of this host"
  echo -e "   Port:   1389 / 1636"
  echo -e "   User:   cn=admin,dc=sasldap,dc=com"
  echo -e "   Pass:   SAS@ldapAdm1n"
  echo -e "   BaseDN: dc=sasldap,dc=com"
  echo -e "   CA:     $PWD/assets/certificates/sasldap_CA.crt"
  sleep 0.5
  echo ""
  echo -e "   $NOTEMSG | To manage your LDAP, launch the following command ${YELLOW}before${NONE} accessing it via LDAP browser:"
  echo -e "   ${ITALIC}kubectl -n $NS port-forward svc/sas-ldap-service 1389:1389${NONE}"
}

### Print default tree
printDefaultTree() {
  echo ""
  echo -e "🌐 dc=sasldap,dc=com"
  echo -e " └───🛠️ cn=admin         | 🔑 SAS@ldapAdm1n"
}

### Print SAS tree
printSAStree() {
  echo ""
  echo -e "🌐 dc=sasldap,dc=com"
  echo -e " ├───🛠️ cn=admin         | 🔑 SAS@ldapAdm1n"
  echo -e " ├───🔗 uid=sasbind      | 🔑 SAS@ldapB1nd"
  echo -e " ├───📁 ou=groups"
  echo -e " │   ├───👥 cn=sas       | 🤝 cas, sas"
  echo -e " │   ├───👥 cn=sasadmins | 🤝 sasadm"
  echo -e " │   ├───👥 cn=sasdevs   | 🤝 sasdev"
  echo -e " │   └───👥 cn=sasusers  | 🤝 sasuser"
  echo -e " └───📁 ou=users"
  echo -e "     ├───👤 uid=cas      | 🔑 lnxsas"
  echo -e "     ├───👤 uid=sas      | 🔑 lnxsas"
  echo -e "     ├───👤 uid=sasadm   | 🔑 lnxsas"
  echo -e "     ├───👤 uid=sasdev   | 🔑 lnxsas"
  echo -e "     └───👤 uid=sasuser  | 🔑 lnxsas"
}

printGoodbye(){
  echo ""
  echo -e "${BOLD}Persistent OpenLDAP${NONE} for ${BCYAN}SAS Viya${NONE} deployed successfully!"
  sleep 0.5
  echo -e "This script will now exit."
}

### Enable `memberOf` attribute
applyMemberOf(){
  local podOpenLDAP=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}')
  
  vlog "Applying memberOf module to pod: $podOpenLDAP"
  
  sleep 5
  vlog "Loading memberOf module..."
  kubectl -n $NS exec -it $podOpenLDAP -- ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/loadMemberOfModule.ldif
  
  vlog "Configuring memberOf overlay..."
  kubectl -n $NS exec -it $podOpenLDAP -- ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/configureMemberOfOverlay.ldif
  sleep 2
  
  vlog "Restarting pod to apply changes..."
  
  kubectl -n $NS delete pod $podOpenLDAP
  sleep 5
  
  vlog "Waiting for new pod to be ready..."
  
  if kubectl wait --for=condition=ready pod -l app=sas-ldap-server -n $NS --timeout=120s > /dev/null 2>&1; then
    sleep 5
    vlog "MemberOf configuration applied successfully"
    return 0
  else
    echo -e "$ERRORMSG | Failed to wait for pod restart" >&2
    return 1
  fi
}

### Deploy SAS Viya-ready structure
deploySASViyaStructure() {
  podOpenLDAP=$(kubectl get pod -l app=sas-ldap-server -n $NS -o jsonpath='{.items[0].metadata.name}')
  
  vlog "Deploying SAS Viya structure to pod: $podOpenLDAP"
  
  ### Copy the sas-ldap-structure.ldif file to the OpenLDAP container
  vlog "Copying sas-ldap-structure.ldif to pod..."
  kubectl -n $NS cp samples/sas-ldap-structure.ldif $podOpenLDAP:/tmp/sas-ldap-structure.ldif
  if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to copy sas-ldap-structure.ldif to the OpenLDAP container." >&2
    return 1
  fi

  ### ldapadd sas-ldap-structure.ldif
  vlog "Applying LDAP structure (users and groups)..."
  kubectl -n $NS exec -it $podOpenLDAP -- ldapadd -x -H ldap://localhost:1389 -D "cn=admin,dc=sasldap,dc=com" -w SAS@ldapAdm1n -f /tmp/sas-ldap-structure.ldif
  if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to apply SAS Viya-ready structure." >&2
    return 1
  fi

  ### ldapmodify sasbindACLs.ldif
  vlog "Applying ACLs for sasbind user..."
  kubectl -n $NS exec -it $podOpenLDAP -- ldapmodify -Y EXTERNAL -H ldapi:/// -f /custom-ldifs/sasbindACLs.ldif
  if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to apply ACLs to sasbind user." >&2
    return 1
  fi

  ### Restart $podOpenLDAP
  vlog "Restarting pod to finalize configuration..."
  sleep 2
  kubectl -n $NS delete pod $podOpenLDAP
  sleep 5

  vlog "Waiting for pod to be ready after restart..."
  
  kubectl wait --for=condition=ready pod -l app=sas-ldap-server -n $NS --timeout=120s
  if [ $? -ne 0 ]; then
    echo -e "$ERRORMSG | Failed to wait for OpenLDAP pod to be ready." >&2
    return 1
  fi

  vlog "SAS Viya structure deployed successfully"
  
  return 0
}

if [ "$OpenLDAPdeployed" = "YES" ]; then
  echo -e "\n⮞  ${BYELLOW}OpenLDAP configuration${NONE}\n"
  
  # Configure OpenLDAP initial structure
  execute \
    --title "Configuring ${CYAN}OpenLDAP${NONE} initial structure" \
    applyMemberOf \
    --error "$ERRORMSG | Failed to configure ${CYAN}OpenLDAP${NONE} initial structure."

  # Print current OpenLDAP structure
  echo -e "\nCurrent ${CYAN}OpenLDAP${NONE} structure:"
  sleep 0.5
  printDefaultTree
  sleep 0.5
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
        sleep 0.5
        printSAStree
        sleep 0.5
        divider
        sleep 0.5
        printConnectionInfo
        sleep 0.5
        divider
        sleep 0.5
        printGoodbye
      else
        echo -e "$ERRORMSG | Failed to deploy ${CYAN}SAS Viya${NONE}-ready structure."
        exit 1 # SAS Viya-ready structure failed to deploy
      fi
      break

    elif [[ "$user_input" =~ ^[Nn]$ ]]; then
      sleep 0.5
      printConnectionInfo
      sleep 0.5
      divider
      sleep 0.5
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
