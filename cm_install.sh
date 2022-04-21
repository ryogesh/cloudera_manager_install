#/bin/bash

# Below script works only on RH/CentOS
# Run the script as root on the CM server host

#DO NOT list the current (CM server) host, this host is the CM server
#List of cluster hosts except this host, 1 host per line, FQDN
HFILE=/root/allh

cm_server=$(hostname -f)

## Start Mandatory inputs

# Cloudera repo archive.cloudera.com userid/password
REPOUID=
REPOPWD= 

#Root password of all nodes
export SSHPASS= 

# Java key, truststore password for AutoTLS
TSTORE_PWD=
KEYSTORE_PWD=

#credentials for MIT KDC installation 
kdcadmin=
kdcadmpwd=
KDBSECRET=

#Postgresql DB passwords for oozie,hive,ranger,ranger rms,hue,rman,scm databases, see below, change password as required
PWDO=
PWDHI=
PWDRN=
PWDRR=
PWDHU=
PWDR=
PWDS=

# change the realm for AD OR MIT
myrealmL=secure.my.site

# Change the kdc and kadmin server; defaults to cm_server host
kdc_server=${cm_server}
kadmin_server=${cm_server}

## End Mandatory inputs

# Install postgres10 server
INSTALLPG10=Y

# Install kerberos server
INSTALLMITKDC=Y

#Install Kerberos client on all hosts
INSTALLKRBCLIENT=Y


# Specify CDP version to install, 7.1.7, 7.1.6, 7.1.5 or 7.1.4
CDPVER=7.1.7

# Specify OS version for 7.1.7 and above, 7.1.6, 7.1.5 or 7.1.4 supports redhat7 only
OSVER=redhat7
#OSVER=redhat8

# Refer Auto-TLS documentation
# https://docs.cloudera.com/cdp-private-cloud-base/7.1.7/security-encrypting-data-in-transit/topics/cm-security-use-case-3.html
#ca-certs should be in ${tmp_cert_dir}/ca-certs
#keys should be in ${tmp_cert_dir}/keys
#certs should be in .pem format in ${tmp_cert_dir}/certs
#.pem files should be of the format <FQDN>.pem
autotls_location=/opt/cloudera/AutoTLS
configureAllServices=true
tmp_cert_dir=/tmp/auto-tls
payload_file=/tmp/ca_payload.json

#CM Repo details ; CM server is installed on the host running this script
if [ ${CDPVER} == "7.1.7" ]; then
  CMVER=7.6.1
  if [ ${OSVER} == "redhat8" ]; then
    CMRPMV=24046616.el8.x86_64
  else
    CMRPMV=24046616.el7.x86_64
  fi
elif [ ${CDPVER} == "7.1.6" ]; then
  CMVER=7.3.1
  CMRPMV=10891891.el7.x86_64
  OSVER=redhat7 
elif [ ${CDPVER} == "7.1.5" ]; then
  CMVER=7.2.4
  CMRPMV=7594142.el7.x86_64
  OSVER=redhat7
elif [ ${CDPVER} == "7.1.4" ]; then
  CMVER=7.1.4
  CMRPMV=6363010.el7.x86_64
  OSVER=redhat7
else
  echo "Unknown CDP version. Exiting..."
fi
cdir=`pwd`

install_cleanup () {
  echo "Performing cleanup of install files, logs"
  rm -rf /tmp/jdkinstall.log /tmp/agentinstall.log /tmp/dbuser.sql ${payload_file} ${cdir}/cm${CMVER}-${OSVER}.tar.gz ${cdir}/cm${CMVER} ${cdir}/cloudera-manager.repo.bak
  for i in `cat $HFILE`; do ssh -f $i "rm -rf cm${CMVER} cm${CMVER}-${OSVER}.tar.gz /tmp/config.ini"; done
}

install_pg10 () {
  echo "Will install PostgreSQL server"
  yum install -y postgresql10-server

  # Initialize the database and enable automatic start:
  /usr/pgsql-10/bin/postgresql-10-setup initdb
  systemctl enable postgresql-10

  #edit /var/lib/pgsql/10/data/pg_hba.conf (md5) and postgresql.conf (listen); change the IP range, as required
  sed -i.bak "s/#listen_addresses = 'localhost'/listen_addresses = '${cm_server}'/" /var/lib/pgsql/10/data/postgresql.conf
  sed -i "s/max_connections = 100/max_connections = 1000/" /var/lib/pgsql/10/data/postgresql.conf
  sed -i.bak "/host    all             all             127/ i host    all             all             $(hostname -i|cut -d'.' -f1,2).0.1/16            md5" /var/lib/pgsql/10/data/pg_hba.conf

  # Start postgresql
  systemctl start postgresql-10
  systemctl enable postgresql-10
}

install_cm () {
  #Check if sshpass is installed, if not install and then remove
  if [ $(which sshpass 2>/dev/null |wc -l) == 0 ]; then
    echo -e "\nRequires sshpass to continue installation. sshpass will be uninstalled after the initial setup."
    read  -r -p "Install sshpass?, type Confirm: " response
    if [ "$response" == "Confirm" ]; then
      echo ""
      yum install -y sshpass
      INSTALLED_SSHP=Y
    else
      echo "Cannot proceed without sshpass"
      exit 1
    fi
  fi

  ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa
  for i in ${cm_server} `cat $HFILE`; do sshpass -e ssh-copy-id -o StrictHostKeyChecking=no $i ;done
  if [ ${INSTALLED_SSHP} == "Y" ]; then
    yum remove -y sshpass
  fi
    
  # Configure cloudera repo; required for JDK and Postgres10 install
  download_url=https://${REPOUID}:${REPOPWD}@archive.cloudera.com/p/cm7/${CMVER}/${OSVER}/yum/cloudera-manager.repo
  echo "Downloading cloudera manager repo"
  curl ${download_url} -o cloudera-manager.repo
  # edit and then scp to all other hosts
  # Can be in 1 of the 2 formats, so trying both
  sed -i.bak "s/changeme:changeme@/${REPOUID}:${REPOPWD}@/" cloudera-manager.repo

  sed -i "s/username=changeme/username=${REPOUID}/" cloudera-manager.repo
  sed -i "s/password=changeme/password=${REPOPWD}/" cloudera-manager.repo

  for i in `cat $HFILE`; do scp cloudera-manager.repo $i:/etc/yum.repos.d/cloudera-manager.repo; done
  mv cloudera-manager.repo /etc/yum.repos.d/cloudera-manager.repo

  # Download tarball and copy for install
  CMTAR=archive.cloudera.com/p/cm7/${CMVER}/repo-as-tarball/cm${CMVER}-${OSVER}.tar.gz
  curl https://${REPOUID}:${REPOPWD}@${CMTAR} -o cm${CMVER}-${OSVER}.tar.gz
  for i in `cat $HFILE`; do scp ${cdir}/cm${CMVER}-${OSVER}.tar.gz $i:~/. ; done

  #JDK install, Hue Python packages
  #On other servers
  echo "Installing JDK on all other hosts"
  for i in `cat $HFILE`; do ssh -f $i "cd /root; tar -xf cm${CMVER}-${OSVER}.tar.gz; yum install -y python-pip; pip install psycopg2==2.7.5 --ignore-installed; yum install -y openjdk8; update-alternatives --install /usr/bin/java java /usr/java/jdk1.8.0_232-cloudera/bin/java 1000; update-alternatives --install /usr/bin/javac javac /usr/java/jdk1.8.0_232-cloudera/bin/javac 1000; mkdir /usr/share/java"; done 1>/tmp/jdkinstall.log 2>&1

  # On CM server
  echo "Installing JDK on CM server"
  tar -xf *.tar.gz; yum install -y python-pip; pip install psycopg2==2.7.5 --ignore-installed; yum install -y openjdk8; update-alternatives --install /usr/bin/java java /usr/java/jdk1.8.0_232-cloudera/bin/java 1000; update-alternatives --install /usr/bin/javac javac /usr/java/jdk1.8.0_232-cloudera/bin/javac 1000; mkdir /usr/share/java

  if [ ${INSTALLPG10} == "Y" ]; then
    install_pg10
  fi
  #create db, users
  echo "
  create user scm password '${PWDS}';
  create user rman password '${PWDR}';
  create user hive password '${PWDHI}';
  create user ranger password '${PWDRN}';
  create user rrms password '${PWDRR}';
  create user oozie password '${PWDO}';
  create user hue password '${PWDHU}';

  create database scm owner scm;
  create database rman owner rman;
  create database ranger owner ranger;
  create database rrms owner rrms;
  create database hive owner hive;
  create database oozie owner oozie;
  create database hue owner hue;
  \l
  \q
  " > /tmp/dbuser.sql

  runuser -l postgres -c 'psql -f /tmp/dbuser.sql'

  echo "Installing on CM server"
  #Install CM server, CM agent and daemon
  cd /root/cm${CMVER}/RPMS/x86_64/
  yum localinstall -y cloudera-manager-server-${CMVER}-${CMRPMV}.rpm cloudera-manager-daemons-${CMVER}-${CMRPMV}.rpm cloudera-manager-agent-${CMVER}-${CMRPMV}.rpm cloudera-manager-server-db-2-${CMVER}-${CMRPMV}.rpm
  cd -

  #Edit cloudera-scm-agent ini file; change local to CM server host
  sed -i.bak "s/server_host=localhost/server_host=${cm_server}/" /etc/cloudera-scm-agent/config.ini
  for i in `cat $HFILE`; do scp /etc/cloudera-scm-agent/config.ini  $i:/tmp/config.ini; done

  #Download and Copy postgresql driver
  curl https://jdbc.postgresql.org/download/postgresql-42.2.18.jar -o postgresql-42.2.18.jar
  for i in `cat $HFILE`; do scp postgresql-42.2.18.jar $i:/usr/share/java/postgresql-connector-java.jar; done
  mv postgresql-42.2.18.jar /usr/share/java/postgresql-connector-java.jar

  #Start CM server
  /opt/cloudera/cm/schema/scm_prepare_database.sh -h ${cm_server} postgresql scm scm ${PWDS}
  systemctl enable cloudera-scm-server
  systemctl start cloudera-scm-server
  systemctl enable cloudera-scm-agent
  systemctl start cloudera-scm-agent


  #Install cm agents and daemons on all hosts
  echo "Installing CM agent on all other hosts"
  for i in `cat $HFILE`; do ssh -f $i "yum localinstall -y /root/cm${CMVER}/RPMS/x86_64/cloudera-manager-daemons-${CMVER}-${CMRPMV}.rpm /root/cm${CMVER}/RPMS/x86_64/cloudera-manager-agent-${CMVER}-${CMRPMV}.rpm; mv /tmp/config.ini /etc/cloudera-scm-agent/config.ini; systemctl enable cloudera-scm-agent; systemctl start cloudera-scm-agent; echo 'CM Install done' ";done 1>/tmp/agentinstall.log 2>&1
  sleep 120

  #Login to http://cmserver:7180; upload License, verify all hosts, add CMS
  echo ""
  echo "Login to CM, http://${cm_server}:7180"
  echo "If all hosts are not present, wait for the cloudera-scm-agent install to complete; check the log files on the missing servers"
  echo "****If you do NOT want to proceed futher with AutoTLS and Kerberos, press any key on below prompt*****"
  echo ""
  read  -r -p "In CM, Upload License, Verify all hosts, Add CMS. When the 3 steps are done, press any key to continue: " response
}

enable_autotls () {
  echo -e "\n****If you do NOT want to proceed futher with AutoTLS configuration, press any key on below prompt*****"
  read  -r -p "Enable AutoTLS?, type Confirm: " response
  if [ "$response" != "Confirm" ]; then
    echo "Auto-TLS will NOT be enabled."
  else
    if ! [ -d "${tmp_cert_dir}/ca-certs" ]; then
      echo -e "\nCA Certificates directory ${tmp_cert_dir}/ca-certs does not exist. Exiting..."
      exit 1
    fi
    if ! [ -d "${tmp_cert_dir}/keys" ]; then
      echo -e "\nPrivate keys directory ${tmp_cert_dir}/keys does not exist. Exiting..."
      exit 1
    fi
    if ! [ -d "${tmp_cert_dir}/certs" ]; then
      echo -e "\nServer Certificates directory ${tmp_cert_dir}/certs does not exist. Exiting..."
      exit 1
    fi
    echo ${TSTORE_PWD} > ${tmp_cert_dir}/ca-certs/truststore.pwd
    echo ${KEYSTORE_PWD} > ${tmp_cert_dir}/keys/key.pwd

    echo "{
    \"location\" : "\"${autotls_location}"\",
    \"customCA\" : true,
    \"interpretAsFilenames\" : true,
    \"cmHostCert\" : "\"${tmp_cert_dir}/certs/${cm_server}.pem"\",
    \"cmHostKey\" : "\"${tmp_cert_dir}/keys/${cm_server}.key"\",
    \"caCert\" : "\"${tmp_cert_dir}/ca-certs/truststore.pem"\",
    \"keystorePasswd\" : "\"${tmp_cert_dir}/keys/key.pwd"\",
    \"truststorePasswd\" : "\"${tmp_cert_dir}/ca-certs/truststore.pwd"\",
    \"hostCerts\" : [ " > ${payload_file}

    for node in $cm_server `cat $HFILE`
    do
    echo "{
    \"hostname\" : "\"$node"\",
    \"certificate\" : "\"${tmp_cert_dir}/certs/$node.pem"\",
    \"key\" : "\"${tmp_cert_dir}/keys/$node.key"\"
    }," >> ${payload_file}
    done

    ## Remove the comma at the end
    sed -i "$ s/,/ ],/g" ${payload_file}

    ## Add the footer details which includes the credentials
    echo "\"configureAllServices\" : "\"${configureAllServices}"\",
    \"sshPort\" : 22,
    \"userName\" : "\"root"\",
    \"password\" : "\"${SSHPASS}"\"
    } " >> ${payload_file}

    # Enable TLS by running the CM API
    echo "****** Enter the Cloudera manager admin user password, when prompted ******"
    curl -i -v -u admin --header 'Content-Type: application/json' --header 'Accept: application/json' -d@${payload_file} \
    "http://${cm_server}:7180/api/v41/cm/commands/generateCmca"

    #Restart after enabling TLS
    echo "Restarting cloudera-scm-server and agents. Wait...."
    systemctl restart cloudera-scm-server
    systemctl restart cloudera-scm-agent
    for i in `cat $HFILE`; do ssh -f $i "systemctl restart cloudera-scm-agent"; done
    sleep 100
    echo ""
    read  -r -p "Login to https://${cm_server}:7183 and restart CMS. Verify CM and CMS. press any key to continue: " response
  fi
}

install_krb () {
  myrealm=${myrealmL^^}
  echo -e "\n****If you do NOT want to install Kerberos client or server, press any key on below prompt*****"
  read  -r -p "Install and configure Kerberos?, type Confirm: " response
  if [ "$response" != "Confirm" ]; then
    echo "Kerberos will NOT be configured."
  else 
    ## Kerberos client installation
    if [ ${INSTALLKRBCLIENT} = "Y" ]; then
      for i in `cat $HFILE`; do ssh -f $i "yum -y install krb5-workstation krb5-libs"; done

      #Update krb5.conf
      sed -i.bak "/dns_lookup_realm/ i \ dns_lookup_kdc = false\n kdc_timeout = 3000"  /etc/krb5.conf
      sed -i "s/# default_realm = EXAMPLE.COM/ default_realm = ${myrealm}/" /etc/krb5.conf
      sed '/[realms]/,$d' /etc/krb5.conf
      sed -i -n '/realms/q;p' /etc/krb5.conf

      echo "
[realms]
 ${myrealm} = {
  kdc = ${kdc_server}
  admin_server = ${kadmin_server}
 }

[domain_realm]
 .${myrealmL} = ${myrealm}
 ${myrealmL} = ${myrealm}
" >> /etc/krb5.conf

      for i in `cat $HFILE`; do scp /etc/krb5.conf $i:/etc/krb5.conf; done
      echo "Kerberos client installation complete."
    fi
    ## Kerberos server installation
    if [ ${INSTALLMITKDC} = "Y" ]; then
      yum -y install krb5-server

      #Update /var/kerberos/krb5kdc/kdc.conf; remove weak ciphers, set default realm, add max life
      sed -i.bak 's/\(des\|arc\|camellia\)\S*//g' kdc.conf
      sed -i "s/EXAMPLE.COM/${myrealm}/" /var/kerberos/krb5kdc/kdc.conf
      sed -i "/admin_keytab/ i \ max_life = 1d\n max_renewable_life = 7d" /var/kerberos/krb5kdc/kdc.conf

      # Initialize
      /usr/sbin/kdb5_util -P ${KDBSECRET} create -s

      #Enable and Start
      systemctl enable krb5kdc
      systemctl enable kadmin
      systemctl start krb5kdc
      systemctl start kadmin

      # create ${kdcadmin} admin account
      kadmin.local addprinc -pw ${kdcadmpwd} ${kdcadmin}@${myrealm}
      echo "${kdcadmin}@${myrealm}  *" >> /var/kerberos/krb5kdc/kadm5.acl
      systemctl restart krb5kdc
      systemctl restart kadmin
      echo "Kerberos server installation complete."
    fi
  fi
}

#Main section
read  -r -p "Is the Hosts file $HFILE ready? [Y/n]: " response
if [ "$response" != "Y" ] || [ ! -f "$HFILE" ]; then
  echo "File check $HFILE failed, exiting"
  exit 1
fi

install_cm
install_krb
enable_autotls
install_cleanup
echo -e "\n Certificate folders are not deleted, so that one can verify TLS config in case of any errors/issues"
echo "***Important: Make sure to cleanup the certificates, keys and password files from ${tmp_cert_dir}***"
echo -e "\nEnd of Installation...."
