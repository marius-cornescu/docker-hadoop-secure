#####################################################################################################################################################
# Creates pseudo distributed kerberized hadoop 2.7.7
#
# docker build --rm -t knappek/hadoop-secure .
# docker build --rm --build-arg http_proxy=$http_proxy -t knappek/hadoop-secure .
# 
# docker run -it knappek/hadoop-secure /etc/bootstrap.sh -bash
# 
#####################################################################################################################################################
FROM sequenceiq/pam:centos-6.5
MAINTAINER Knappek
#
USER root
# 
ARG http_proxy
# 
ENV http_proxy $http_proxy
ENV https_proxy $http_proxy
# 
#====================================================================================================================================================
RUN touch /var/lib/rpm/* \
    && yum -y install yum-plugin-ovl
# 
# install dev tools
RUN yum clean all; \
    rpm --rebuilddb; \
    yum install -y curl which tar sudo openssh-server openssh-clients rsync wget \ 
    vim rsyslog unzip glibc-devel \
    glibc-headers gcc-c++ cmake git zlib-devel
# update libselinux. see https://github.com/sequenceiq/hadoop-docker/issues/14
RUN yum update -y libselinux \
    && yum clean all

RUN echo 'alias ll="ls -alF"' >> /root/.bashrc
#====================================================================================================================================================
# PASSWORD-LESS ssh
RUN ssh-keygen -q -N "" -t dsa -f /etc/ssh/ssh_host_dsa_key
RUN ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key
RUN ssh-keygen -q -N "" -t rsa -f /root/.ssh/id_rsa
RUN cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
#====================================================================================================================================================
# JAVA    ===========================================================================================================================================
# download/copy JDK. Comment one of these. The curl command can be retrieved
# from https://lv.binarybabel.org/catalog/java/jdk8
#RUN curl --insecure -LOH 'Cookie: oraclelicense=accept-securebackup-cookie' 'http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.rpm'
COPY local_files/jdk-8u221-linux-x64.rpm /

RUN rpm -i jdk-8u221-linux-x64.rpm
RUN rm jdk-8u221-linux-x64.rpm

#RUN yum -y install java-1.8.0-openjdk-devel.x86_64 && yum clean all

ENV JAVA_HOME /usr/java/default
ENV PATH $PATH:$JAVA_HOME/bin
RUN rm /usr/bin/java && ln -s $JAVA_HOME/bin/java /usr/bin/java
#====================================================================================================================================================
#RUN curl --insecure -LOH 'Cookie: oraclelicense=accept-securebackup-cookie' 'http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip'
COPY local_files/jce_policy-8.zip /
RUN unzip jce_policy-8.zip
RUN cp /UnlimitedJCEPolicyJDK8/local_policy.jar /UnlimitedJCEPolicyJDK8/US_export_policy.jar $JAVA_HOME/jre/lib/security

# Kerberos client
RUN yum install krb5-libs krb5-workstation krb5-auth-dialog -y
RUN mkdir -p /var/log/kerberos
RUN touch /var/log/kerberos/kadmind.log

#====================================================================================================================================================
# MAVEN   ===========================================================================================================================================
#RUN curl --insecure -L https://archive.apache.org/dist/maven/maven-3/3.5.0/binaries/apache-maven-3.5.0-bin.tar.gz | tar -xz -C /usr/local
COPY local_files/apache-maven-3.5.0-bin.tar.gz /tmp/apache-maven-3.5.0-bin.tar.gz
RUN tar -xzf /tmp/apache-maven-3.5.0-bin.tar.gz -C /usr/local

RUN cd /usr/local && ln -s ./apache-maven-3.5.0/ maven
ENV PATH $PATH:/usr/local/maven/bin

#COPY config_files/mvn_settings.xml /usr/local/maven/conf/settings.xml

#====================================================================================================================================================
# HADOOP  ===========================================================================================================================================
# hadoop
# download/copy hadoop. Choose one of these options
ENV HADOOP_PREFIX /usr/local/hadoop
RUN curl --insecure -s http://apache.mirror.anlx.net/hadoop/common/hadoop-2.7.7/hadoop-2.7.7.tar.gz | tar -xz -C /usr/local/
#COPY local_files/hadoop-2.7.7.tar.gz $HADOOP_PREFIX-2.7.7.tar.gz
#RUN tar -xzvf $HADOOP_PREFIX-2.7.7.tar.gz -C /usr/local

RUN cd /usr/local \
    && ln -s ./hadoop-2.7.7 hadoop \
    && chown root:root -R hadoop/

#====================================================================================================================================================
ENV HADOOP_COMMON_HOME $HADOOP_PREFIX
ENV HADOOP_HDFS_HOME $HADOOP_PREFIX
ENV HADOOP_MAPRED_HOME $HADOOP_PREFIX
ENV HADOOP_YARN_HOME $HADOOP_PREFIX
ENV HADOOP_CONF_DIR $HADOOP_PREFIX/etc/hadoop
ENV YARN_CONF_DIR $HADOOP_PREFIX/etc/hadoop
# 
ENV NM_CONTAINER_EXECUTOR_PATH $HADOOP_PREFIX/bin/container-executor
ENV HADOOP_BIN_HOME $HADOOP_PREFIX/bin
ENV PATH $PATH:$HADOOP_BIN_HOME

ENV KRB_REALM EXAMPLE.COM
ENV DOMAIN_REALM example.com
ENV KERBEROS_ADMIN admin/admin
ENV KERBEROS_ADMIN_PASSWORD admin
ENV KERBEROS_ROOT_USER_PASSWORD password
ENV KEYTAB_DIR /etc/security/keytabs
ENV FQDN hadoop.com

RUN mkdir $HADOOP_PREFIX/input
RUN cp $HADOOP_PREFIX/etc/hadoop/*.xml $HADOOP_PREFIX/input
# 
# pseudo distributed
ADD config_files/hadoop-env.sh $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh
ADD config_files/core-site.xml $HADOOP_PREFIX/etc/hadoop/core-site.xml
ADD config_files/hdfs-site.xml $HADOOP_PREFIX/etc/hadoop/hdfs-site.xml
# 
ADD config_files/mapred-site.xml $HADOOP_PREFIX/etc/hadoop/mapred-site.xml
ADD config_files/yarn-site.xml $HADOOP_PREFIX/etc/hadoop/yarn-site.xml
ADD config_files/container-executor.cfg $HADOOP_PREFIX/etc/hadoop/container-executor.cfg
# 
RUN mkdir $HADOOP_PREFIX/nm-local-dirs \
    && mkdir $HADOOP_PREFIX/nm-log-dirs 
ADD config_files/ssl-server.xml $HADOOP_PREFIX/etc/hadoop/ssl-server.xml
ADD config_files/ssl-client.xml $HADOOP_PREFIX/etc/hadoop/ssl-client.xml
ADD config_files/keystore.jks $HADOOP_PREFIX/lib/keystore.jks

# 
#====================================================================================================================================================
# HADOOP 2 ==========================================================================================================================================

# fetch hadoop source code to build some binaries natively
# for this, protobuf is needed
#RUN curl --insecure -L https://github.com/google/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.gz | tar -xz -C /tmp/
COPY local_files/protobuf-2.5.0.tar.gz /tmp/protobuf-2.5.0.tar.gz
RUN tar -xzf /tmp/protobuf-2.5.0.tar.gz -C /tmp/

RUN cd /tmp/protobuf-2.5.0 \
    && ./configure \
    && make \
    && make install
ENV HADOOP_PROTOC_PATH /usr/local/bin/protoc

#====================================================================================================================================================
RUN curl -L http://www.eu.apache.org/dist/hadoop/common/hadoop-2.7.7/hadoop-2.7.7-src.tar.gz | tar -xz -C /tmp
#COPY local_files/hadoop-2.7.7-src.tar.gz /tmp/hadoop-2.7.7-src.tar.gz
#RUN tar -xzf /tmp/hadoop-2.7.7-src.tar.gz -C /tmp
#
#==========================================================================
# build native hadoop-common libs to remove warnings because of 64 bit OS
RUN rm -rf $HADOOP_PREFIX/lib/native
RUN cd /tmp/hadoop-2.7.7-src/hadoop-common-project/hadoop-common \
    && mvn compile -Pnative \
    && cp target/native/target/usr/local/lib/libhadoop.a $HADOOP_PREFIX/lib/native \
    && cp target/native/target/usr/local/lib/libhadoop.so.1.0.0 $HADOOP_PREFIX/lib/native
#==========================================================================
# build container-executor binary
RUN cd /tmp/hadoop-2.7.7-src/hadoop-yarn-project/hadoop-yarn/hadoop-yarn-server/hadoop-yarn-server-nodemanager \
    && mvn compile -Pnative \
    && cp target/native/target/usr/local/bin/container-executor $HADOOP_PREFIX/bin/ \
    && chmod 6050 $HADOOP_PREFIX/bin/container-executor
#==========================================================================

ADD config_files/ssh_config /root/.ssh/config
RUN chmod 600 /root/.ssh/config
RUN chown root:root /root/.ssh/config
# 
# --------------------------------------------------
# 
ENV BOOTSTRAP /etc/bootstrap.sh
ADD bootstrap.sh $BOOTSTRAP
RUN chown root:root $BOOTSTRAP
RUN chmod 700 $BOOTSTRAP
# 
# --------------------------------------------------
# working around docker.io build error
RUN ls -la $HADOOP_PREFIX/etc/hadoop/*-env.sh
RUN chmod +x $HADOOP_PREFIX/etc/hadoop/*-env.sh
RUN ls -la $HADOOP_PREFIX/etc/hadoop/*-env.sh
# --------------------------------------------------

# fix the 254 error code
RUN sed  -i "/^[^#]*UsePAM/ s/.*/#&/"  /etc/ssh/sshd_config
RUN echo "UsePAM no" >> /etc/ssh/sshd_config
RUN echo "Port 2122" >> /etc/ssh/sshd_config

RUN service sshd start && $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh && $HADOOP_PREFIX/sbin/start-dfs.sh && $HADOOP_PREFIX/bin/hdfs dfs -mkdir -p /user/root
RUN service sshd start && $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh && $HADOOP_PREFIX/sbin/start-dfs.sh && $HADOOP_PREFIX/bin/hdfs dfs -put $HADOOP_PREFIX/etc/hadoop/ input

CMD ["/etc/bootstrap.sh", "-d"]

#====================================================================================================================================================
# HDFS ports
EXPOSE 50010 50020 50070 50075 50090 8020 9000
# Mapred ports
EXPOSE 10020 19888
# Yarn ports
EXPOSE 8030 8031 8032 8033 8040 8042 8088
# SSHD port
EXPOSE 2122
# Other ports
EXPOSE 49707
#####################################################################################################################################################