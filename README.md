<div align="center">

![SAS Viya](/.design/sasviya.png)

# **Persistent OpenLDAP for SAS Viya**

</div>

![Divider](/.design/divider.png)

## Table of Contents

1. [Description](#description)
2. [Prerequisites](#prerequisites)
3. [Usage](#usage)
4. [OpenLDAP Management](#openldap-management)
5. [Users and Passwords](#users-and-passwords)
6. [Configure with SAS Viya](#configure-with-sas-viya)
7. [Known Issues](#known-issues)

![Divider](/.design/divider.png)

## Description

Based on [bitnami/openldap](https://github.com/bitnami/containers/tree/main/bitnami/openldap), this project automates the deployment and configuration of an OpenLDAP server tailored for SAS Viya 4, running in a Kubernetes environment. The setup includes custom schemas, ACLs, and integration with SAS applications, ensuring a ready-to-use LDAP service with necessary access controls and structure for SAS Viya.

The tool supports unencrypted connection to port **1389** (LDAP) and encrypted connection to port **1636** (LDAPS).

![Divider](/.design/divider.png)

## Prerequisites

Ensure the following prerequisites are met before executing the script:

- **Packages:**
  - `kubectl`
  - `kustomize`

- **Permissions:**
  - The user must have namespace creation/management permissions on the cluster.

- **Image Access:**
  - The cluster should be capable of pulling images from `docker.io`.
  
> [!TIP]
> Alternatively, you can mirror [bitnami/openldap:latest](https://hub.docker.com/r/bitnami/openldap/tags?page=&page_size=&ordering=&name=latest) to your local container registry.
> Be sure to modify it in the [kustomization.yaml](assets/kustomization.yaml) file before executing the [viya4-openldap.sh](viya4-openldap.sh) script.

![Divider](/.design/divider.png)

## Usage

1. Clone the `viya4-openldap` repository

  ```bash
  git clone https://github.com/tonineri/viya4-openldap
  ```

2. Execute the script, specifying the desired namespace for OpenLDAP

    ```bash
    cd viya4-openldap 
    chmod +x viya4-openldap.sh
    ./viya4-openldap.sh --namespace <desiredNamespaceName>
    ```

3. Follow any on-screen prompts or instructions to complete the deployment process seamlessly.

4. **OPTIONAL**: If you chose to load the **SAS Viya**-ready structure, consider copying the [samples/sitedefault.yaml](samples/sitedefault.yaml) to `$deploy/site-config/sitedefault.yaml` for automation purposes.

> [!IMPORTANT]
> Ensure you also defined it in the 'transformers' section of your `$deploy/kustomization.yaml` file.

![Divider](/.design/divider.png)

## OpenLDAP Management

1. Using a `ClusterIP` (default) service.
    - To access and manage your LDAP, execute the following command on your jump host:

      - **With** TLS (LDAP**S**)

        ```bash
        kubectl -n <desiredNamespaceName> port-forward --address localhost svc/sas-ldap-service 1636:1636
        ```

      - **Without** TLS (LDAP)

        ```bash
        kubectl -n <desiredNamespaceName> port-forward --address localhost svc/sas-ldap-service 1389:1389
        ```

    - While port-forwarding is running on you jump host, access the LDAP server through an LDAP browser (like ApacheDirectoryStudio, LdapAdmin, etc.) from your client machine using the following parameters:

      - Host:         `IP/hostname of your jump host`
      - Port:         `1389 / 1636` (LDAP / LDAP**S**)
      - User:         `cn=admin,dc=sasldap,dc=com`
      - Pass:         `SAS@ldapAdm1n`
      - BaseDN:       `dc=sasldap,dc=com`
      - Certificate:  `viya4-openldap/certificates/sasldap_CA.crt`

2. Using a `LoadBalancer` service.

    Access the LDAP server through an LDAP browser (like ApacheDirectoryStudio, LdapAdmin, etc.) from your  client machine using the following parameters:

      - Host:         `LoadBalancer EXTERNAL IP or hostname`
      - Port:         `1389 / 1636` (LDAP/LDAP**S**)
      - User:         `cn=admin,dc=sasldap,dc=com`
      - Pass:         `SAS@ldapAdm1n`
      - BaseDN:       `dc=sasldap,dc=com`
      - Certificate:  `viya4-openldap/certificates/sasldap_CA.crt`

![Divider](/.design/divider.png)

## Users and Passwords

- These are the accounts (and their passwords) deployed by default:

  | username  | password       | distinguishedName                        |
  |-----------|----------------|------------------------------------------|
  | `admin`   | `SAS@ldapAdm1n`| `cn=admin,dc=sasldap,dc=com`             |

  ```text
  🌐 dc=sasldap,dc=com
   └──🛠️ cn=admin   | 🔑 SAS@ldapAdm1n
  ```

- These are the additional default accounts (should you choose to configure the **SAS Viya**-ready structure) when asked during the script prompt:

  | username  | password       | distinguishedName                        |
  |-----------|----------------|------------------------------------------|
  | `sasbind` | `SAS@ldapB1nd` | `uid=sasbind,dc=sasldap,dc=com`          |
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

> [!IMPORTANT]
> Ensure you also defined the `customer-provided-ca-certificates.yaml` file in the 'transformers' section of your `$deploy/kustomization.yaml` file.

![Divider](/.design/divider.png)

## ACLs

The provided ACLs ensure that the `sasbind` user has read access to all attributes, facilitating application bindings while maintaining security.

## Known Issues

  - When using `ClusterIP` and `kubectl port-forwarding` with **TLS**, the connection might be unstable. Consider deploying a `LoadBalancer` or `NodePort` [service](assets/service.yaml) instead, depending on what suits you best.