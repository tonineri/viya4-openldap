<div align="center">

![SAS Viya](/.design/sasviya.png)

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

![Divider](/.design/divider.png)

## Description

Based on [bitnami/openldap](https://github.com/bitnami/containers/tree/main/bitnami/openldap), this script streamlines the establishment of a dedicated namespace for OpenLDAP, deploying it effortlessly with default user and group configurations.
The tool supports unencrypted connection to port **1389** (LDAP) and encrypted connection to port **1636** (LDAPS).

![Divider](/.design/divider.png)

## Prerequisites

Ensure the following prerequisites are met before executing the script:

- **Packages:**
  - `kubectl`
  - `kustomize`

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


5. **OPTIONAL**: If you chose to load the **SAS Viya**-ready structure and no modifications were made to the script, consider copying the [samples/sitedefault.yaml](samples/sitedefault.yaml) to `$deploy/site-config/sitedefault.yaml`.

    > ![Note](/.design/note.png)
    >
    > Ensure you also defined it in the 'transformers' section of your `$deploy/kustomization.yaml` file.

![Divider](/.design/divider.png)

## Port-forwarding and management

1. To access and manage your LDAP, execute the following command on your jump host:

    ```bash
    kubectl -n <desiredNamespaceName> port-forward --address localhost svc/sas-ldap-service 1636:1636
    ```

![Divider](/.design/divider.png)

2. While port-forwarding in running on you jump host, access the LDAP server through an LDAP browser (like ApacheDirectoryStudio, LdapAdmin, etc.) from your client machine using the following parameters:

    - Host:         `IP/hostname of your jump host`
    - Port:         `1389 / 1636`
    - User:         `cn=admin,dc=sasldap,dc=com`
    - Pass:         `SAS@ldapAdm1n`
    - BaseDN:       `dc=sasldap,dc=com`
    - Certificate:  `viya4-openldap/certificates/sasldap_CA.crt`


![Divider](/.design/divider.png)

## Users and Passwords

* These are the accounts (and their passwords) deployed by default:

  | username  | password       | distinguishedName                        |
  |-----------|----------------|------------------------------------------|
  | `admin`   | `SAS@ldapAdm1n`| `cn=admin,dc=sasldap,dc=com`             |

  ```text
  🌐 dc=sasldap,dc=com
   └──🛠️ cn=admin   | 🔑 SAS@ldapAdm1n
  ```

- These are the additional default accounts (**if** you decided to configure the **SAS Viya**-ready structure):

  | username  | password       | distinguishedName                        |
  |-----------|----------------|------------------------------------------|
  | `sasbind` | `SAS@ldapB1nd` | `uid=sasbind,dc=sasldap,dc=com`     |
  | `sas`     | `lnxsas`       | `uid=sas,ou=users,dc=sasldap,dc=com`     |
  | `cas`     | `lnxsas`       | `uid=cas,ou=users,dc=sasldap,dc=com`     |
  | `sasadm`  | `lnxsas`       | `uid=sasadm,ou=users,dc=sasldap,dc=com`  |
  | `sasdev`  | `lnxsas`       | `uid=sasdev,ou=users,dc=sasldap,dc=com`  |
  | `sasuser` | `lnxsas`       | `uid=sasuser,ou=users,dc=sasldap,dc=com` |

  ```text
  🌐 dc=sasldap,dc=com
   ├──🛠️ cn=admin         | 🔑 SAS@ldapAdm1n
   ├──🔗 cn=sasbind       | 🔑 SAS@ldapB1nd
   ├──📁 ou=groups
   │   ├──👥 cn=sas       | 🤝 cas, sas
   │   ├──👥 cn=sasadmins | 🤝 sasadm
   │   ├──👥 cn=sasdevs   | 🤝 sasdev
   │   └──👥 cn=sasusers  | 🤝 sasuser
   └──📁 ou=users
       ├──👤 uid=cas      | 🔑 lnxsas
       ├──👤 uid=sas      | 🔑 lnxsas
       ├──👤 uid=sasadm   | 🔑 lnxsas
       ├──👤 uid=sasdev   | 🔑 lnxsas
       └──👤 uid=sasuser  | 🔑 lnxsas
  ```

![Divider](/.design/divider.png)

## Configure with SAS Viya

For LDAP**S** (secure), copy the `viya4-openldap/certificates/sasldap_CA.crt` file in your `$deploy/site-config/security/cacerts` directory and define it in your `customer-provided-ca-certificates.yaml` file."

    > ![Note](/.design/note.png)
    >
    > Ensure you also defined the `customer-provided-ca-certificates.yaml` file in the 'transformers' section of your `$deploy/kustomization.yaml` file.

![Divider](/.design/divider.png)