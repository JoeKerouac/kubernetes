# 镜像启动的时候需要设置环境变量：APP_NAME（当前应用名）、POD_NAME（当前pod名称）、ENV（当前环境，例如dev、test），startup.sh中会使用；
FROM centos:7
MAINTAINER JoeKerouac <1213812243@qq.com>


# 调整容器的默认编码和时区
ENV LC_ALL en_US.UTF-8
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo 'Asia/Shanghai' >/etc/timezone


RUN mkdir /filebeat \
    && curl https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-7.13.3-linux-x86_64.tar.gz -o /filebeat/filebeat-7.13.3-linux-x86_64.tar.gz \
    && tar -zxvf /filebeat/filebeat-7.13.3-linux-x86_64.tar.gz -C /filebeat \
    && rm -rf /filebeat/filebeat-7.13.3-linux-x86_64.tar.gz \
    && yum install -y gettext

COPY startup.sh /filebeat/

# 启动file beat
CMD /bin/sh /filebeat/startup.sh
