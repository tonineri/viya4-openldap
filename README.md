<div align="center">

![SAS Viya](./.design/logo.png)

# **SAS Viya 4 | OpenLDAP (Persistent)**

</div>

![Divider](/.design/divider.png)

## Table of Contents

1. [Description](#description)
2. [Prerequisites](#prerequisites)
3. [Usage](#usage)
4. [Port-forwarding and Management](#port-forwarding-and-management)
5. [Users and Passwords](#users-and-passwords)
6. [Configure with SAS Viya](#configure-with-sas-viya)
7. [Troubleshooting](#troubleshooting)

![Divider](/.design/divider.png)

## Description

This script streamlines the establishment of a dedicated namespace for OpenLDAP, deploying it effortlessly with default user and group configurations.
The tool **only** supports encrypted connection to ports **636** / **3269**.

![Divider](/.design/divider.png)

## Prerequisites

Ensure the following prerequisites are met before executing the script:

- **Packages:**
  - `kubectl`
  - `kustomize`
  - `ldap-utils`
  - `netcat` (nc)

- **Permissions:**
  - The user must have namespace creation permissions on the cluster.

- **Image Access:**
  - The cluster should be capable of pulling images from `docker.io`.

![Divider](/.design/divider.png)

## Usage

You can 

1. You can either clone the repository or get the latest tarball package:

- Clone the `viya4-openldap` repository:

```bash
git clone https://github.com/tonineri/viya4-openldap
```

- Get the latest package:

```bash
wget -O - https://github.com/tonineri/viya4-openldap/releases/latest/download/viya4-openldap.tgz | tar xz
```

2. Execute the script, specifying the desired namespace for OpenLDAP:

```bash
cd viya4-openldap 
chmod +x viya4-openldap.sh
./viya4-openldap.sh --namespace <desiredNamespaceName>
```

3. Follow any on-screen prompts or instructions to complete the deployment process seamlessly.

4. **OPTIONAL**: You can upload the default OU/User/Group structure (found in [samples/default_ldap_structure.ldif](samples/default_ldap_structure.ldif)) by opening a new terminal and launching the following command from the `viya4-openldap` directory **while port-forwarding is running**:

```bash
LDAPTLS_REQCERT=allow LDAPTLS_CACERT="$PWD/certificate/sasldap_CA.crt" ldapadd -x -H ldaps://localhost:1636 -D cn=admin,dc=sasldap,dc=com -w SAS@ldapAdm1n -f $PWD/samples/default_ldap_structure.ldif
```

5. **OPTIONAL**: If no modifications were made to the script, consider copying the [samples/sitedefault.yaml](samples/sitedefault.yaml) to `$deploy/site-config/sitedefault.yaml`.

   > ![Note](/.design/note.png)
   >
   > Ensure you also defined it in the 'transformers' section of your `$deploy/kustomization.yaml` file.

![Divider](/.design/divider.png)

## Port-forwarding and management

1. To access and manage your LDAP, execute the following command on your jump host:

  ```bash
  kubectl --namespace "$NS" port-forward --address 0.0.0.0 svc/sas-ldap-service 1636:636
  ```

![Divider](/.design/divider.png)

2. While port-forwarding in running on you jump host, access the LDAP server through an LDAP browser (like ApacheDirectoryStudio, LdapAdmin, etc.) from your client machine using the following parameters:

- Host:         `IP/hostname of your jump host`
- Port:         `1636`
- User:         `cn=admin,dc=sasldap,dc=com`
- Pass:         `SAS@ldapAdm1n`
- BaseDN:       `dc=sasldap,dc=com`
- Certificate:  `viya4-openldap/certificate/sasldap_CA.crt`

![Divider](/.design/divider.png)

## Users and Passwords

* These are the accounts (and their passwords) deployed by default:

  | username  | password       | distinguishedName                        |
  |-----------|----------------|------------------------------------------|
  | `admin`   | `SAS@ldapAdm1n`| `cn=admin,dc=sasldap,dc=com`             |
  | `sasbind` | `SAS@ldapB1nd` | `cn=sasbind,dc=sasldap,dc=com`           |

- These are the additional default accounts (**if** you decided to upload the [samples/default_ldap_structure.ldif](samples/default_ldap_structure.ldif) file as per [Usage: Point 4](README.md#usage)):

  | username  | password       | distinguishedName                        |
  |-----------|----------------|------------------------------------------|
  | `sas`     | `lnxsas`       | `uid=sas,ou=users,dc=sasldap,dc=com`     |
  | `cas`     | `lnxsas`       | `uid=cas,ou=users,dc=sasldap,dc=com`     |
  | `sasadm`  | `lnxsas`       | `uid=sasadm,ou=users,dc=sasldap,dc=com`  |
  | `sasdev`  | `lnxsas`       | `uid=sasdev,ou=users,dc=sasldap,dc=com`  |
  | `sasuser` | `lnxsas`       | `uid=sasuser,ou=users,dc=sasldap,dc=com` |

![Divider](/.design/divider.png)

## Configure with SAS Viya

Copy the `viya4-openldap/certificate/sasldap_CA.crt` file in your `$deploy/site-config/security/cacerts` directory and define it in your `customer-provided-ca-certificates.yaml` file."

![Divider](/.design/divider.png)

## Troubleshooting

If cert-manager Issuer and CAs cannot be created, make sure you have the appropriate CRDs set. If not, launch this command:

```bash
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.14.4/cert-manager.crds.yaml
```

![Divider](/.design/divider.png)