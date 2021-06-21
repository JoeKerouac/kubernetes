FROM centos:7
# 维护者信息
MAINTAINER JoeKerouac <1213812243@qq.com>

COPY apache-zookeeper-3.7.0-bin.zip /opt
COPY start-zookeeper.sh /usr/bin

# 安装openjdk1.8
# 安装位置：/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.282.b08-1.el7_9.x86_64
# 或者是软连接：/usr/lib/jvm/java-1.8.0
# 注意，openjdk 16对应的名字和其他两个不太一样，openjdk16的名字是java-latest-openjdk-devel.x86_64
RUN yum update -y \
    && yum install -y epel-release \
    && yum search openjdk | grep 1.8.0 | grep "devel.x86_64" | awk '{print $1}' | xargs -I {} yum install -y {} \
    && yum install -y unzip \
    && echo 'Asia/Shanghai' >/etc/timezone \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && unzip -y /opt/apache-zookeeper-3.7.0-bin.zip \
    && chmod +x /usr/bin/start-zookeeper.sh

ENV JAVA_HOME=/usr/lib/jvm/java-1.8.0
ENV LC_ALL en_US.UTF-8
