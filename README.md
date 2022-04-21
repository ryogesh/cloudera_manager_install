# Cloudera Manager Installation script
Install Cloudera Manager(CM) server and agents on CDP Private Base cluster with a bash script on RH/CentOS servers. 
Script should be run as root and requires root password to setup password-less ssh. Root should be the same on all servers.

Script includes install and configure of Postgres10 DB, MIT KDC on the CM server. Enabled by default, can be disabled. See below.
If the servers TLS certificate and private keys are available, script can enable AutoTLS on the cluster.

# Mandatory Configuration Items
Edit the following before running the installation

## Cloudera repo archive.cloudera.com userid/password
REPOUID=

REPOPWD=

## Root password of all nodes
export SSHPASS=

## Truststore and Keystore passwords for enabling Auto-TLS
TSTORE_PWD=

KEYSTORE_PWD=

## Credentials for MIT KDC installation
kdcadmin=

kdcadmpwd=

KDBSECRET=

## Postgresql DB passwords for oozie,hive,ranger,hue,rman,scm databases
PWDO=

PWDHI=

PWDRN=

PWDRR=

PWDHU=

PWDR=

PWDS=

## change the realm for AD OR MIT KDC
myrealmL=secure.my.site 

## Change the kdc and kadmin server; defaults to cmserver host
kdc_server=cmserver

kadmin_server=cmserver


# Other Key Configuration Items 

## List of cluster hosts, 1 host FQDN per line 
HFILE=/root/allh

## OS version
OSVER=redhat7 (or redhat8 for CDP 7.1.7 and above)

## CM version
CDPVER=7.1.7

## Install postgres10 server
INSTALLPG10=Y

## Install kerberos server
INSTALLMITKDC=Y

## Install Kerberos client on all hosts
INSTALLKRBCLIENT=Y
