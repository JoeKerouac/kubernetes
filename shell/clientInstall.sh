set -o nounset
set -e

###################################################################################################################
##
## 客户端安装
##
###################################################################################################################

###################################################################################################################
##
## 常量定义
##
###################################################################################################################


# 本地IP
LOCAL_IP=$1
# apiserver的域名，如果有自己的DNS或者申请的有域名，这里可以挂域名而不是IP，这样做集群时就无需修改了
# 注意，这个需要是带协议和端口号的，例如https://apiserver.com:6443
APISERVER_DOMAIN=$2
# 证书密码
CA_CERT_PASSWORD=$3
# K8S安装路径
INSTALL_TARGET_DIR=$4
# ETCD监听端口号
ETCDPORT=$5
# etcd host，可以是IP，也可以是域名
ETCDHOST=$6
# docker的私服仓库
DOCKER_REGISTRY_MIRRORS=$7
# docker的非安全仓库（如果自建仓库不是使用SSL连接的需要配置，docker默认使用安全的SSL仓库，使用这个可以指定使用非SSL连接的仓库）
DOCKER_INSECURE_REGISTRIES=$8




# docker工作目录
DOCKER_WORK_DIR=${INSTALL_TARGET_DIR}/docker
# docker使用的cgroup，与compiler中保持一致
CGROUP=systemd






###################################################################################################################
##
## 通用函数定义
##
###################################################################################################################

PRG="$0"
# -h表示判断文件是否是软链接
# 下面这个用于获取真实路径
while [ -h "$PRG" ]; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done

# 这里获取到的就是当前的目录（如果是sh执行就是相对路径，如果是exec就是绝对路径）
NOW_DIR=`dirname "$PRG"`

# 如果指定目录不存在则创建
mkdirIfAbsent() {
	if [ ! -d $1 ]; then
	echo "目录[$1]不存在，创建..."
	mkdir -p $1
	fi
}

yumInstall() {
yum install -y $1 >/dev/null 2>&1
}


# 安装docker函数开始，除了入参无其他额外变量依赖
installDocker() {
DOCKER_WORK_DIR=$1
CGROUP=$2
DOCKER_REGISTRY_MIRRORS=$3
DOCKER_INSECURE_REGISTRIES=$4


echo "开始安装docker-ce"

# 添加docker-ce的yum源（http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo）
cat << "EOF" > /etc/yum.repos.d/docker-ce.repo
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-stable-debuginfo]
name=Docker CE Stable - Debuginfo $basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/debug-$basearch/stable
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-stable-source]
name=Docker CE Stable - Sources
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/source/stable
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-edge]
name=Docker CE Edge - $basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/$basearch/edge
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-edge-debuginfo]
name=Docker CE Edge - Debuginfo $basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/debug-$basearch/edge
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-edge-source]
name=Docker CE Edge - Sources
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/source/edge
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-test]
name=Docker CE Test - $basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/$basearch/test
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-test-debuginfo]
name=Docker CE Test - Debuginfo $basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/debug-$basearch/test
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-test-source]
name=Docker CE Test - Sources
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/source/test
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-nightly]
name=Docker CE Nightly - $basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/$basearch/nightly
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-nightly-debuginfo]
name=Docker CE Nightly - Debuginfo $basearch
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/debug-$basearch/nightly
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg

[docker-ce-nightly-source]
name=Docker CE Nightly - Sources
baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/7/source/nightly
enabled=0
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/docker-ce/linux/centos/gpg
EOF

yumInstall docker-ce
# 目录要我们自己创建
mkdirIfAbsent /etc/docker
# daemon.json配置详情参考官方文档：https://docs.docker.com/engine/reference/commandline/dockerd/
cat << EOF > /etc/docker/daemon.json
{
  "data-root": "${DOCKER_WORK_DIR}",
  "exec-opts": ["native.cgroupdriver=${CGROUP}"],
  "log-driver": "json-file",
  "log-level": "warn",
  "max-concurrent-downloads": 5,
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "registry-mirrors": [${DOCKER_REGISTRY_MIRRORS}],
  "insecure-registries":[${DOCKER_INSECURE_REGISTRIES}],
  "live-restore": true
}
EOF

# docker-ce没有DOCKER_NETWORK_OPTIONS选项了，这样会导致flannel配置不生效，这里主动添加上
sed -i "s#\(^ExecStart=.*$\)#\1\ \$DOCKER_NETWORK_OPTIONS#g" /usr/lib/systemd/system/docker.service
# docker会将iptable规则设置为DROP（应该是从20版本开始），但是我们必须要设置FORWAD规则为ACCEPT允许转发，否则跨node的pod将无法通讯
sed -r -i "/^ExecStart/iExecStartPost=/sbin/iptables -P FORWARD ACCEPT" /usr/lib/systemd/system/docker.service
echo "docker-ce安装完成"
}


# 安装flannel函数开始，除了入参无其他额外变量依赖
installFlannel() {
ETCDHOST=$1
ETCDPORT=$2
LOCAL_IP=$3


echo "开始安装flannel"
yumInstall flannel

cat << EOF > /usr/lib/systemd/system/flanneld.service
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/flanneld
EnvironmentFile=-/etc/sysconfig/docker-network
ExecStart=/usr/bin/flanneld-start \$FLANNEL_OPTIONS
ExecStartPost=/usr/libexec/flannel/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF

# 配置flannel，flannel安装完开机自启时默认是在docker之前启动的，手动启动的时候需要先启动flannel然后启动docker
# 详细全量配置说明请参考：https://github.com/coreos/flannel/blob/master/Documentation/configuration.md
cat << EOF > /etc/sysconfig/flanneld

FLANNEL_ETCD_ENDPOINTS="http://${ETCDHOST}:${ETCDPORT}"
FLANNEL_ETCD_PREFIX="/atomic.io/network"
FLANNEL_OPTIONS="--public-ip=${LOCAL_IP} --iface=${LOCAL_IP}"

EOF
echo "flannel安装完毕"
}
# 安装flannel函数结束




###################################################################################################################
##
## 安装逻辑
##
###################################################################################################################

systemctl stop firewalld && echo "关闭防火墙"
systemctl disable firewalld && echo "禁用防火墙开机自启"

# 临时开启转发
sysctl -w net.ipv4.ip_forward=1
# 永久开启转发，重启生效
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf


# 安装flannel
installFlannel "${ETCDHOST}" "${ETCDPORT}" "${LOCAL_IP}"

# 安装docker
installDocker "${DOCKER_WORK_DIR}" "${CGROUP}" "${DOCKER_REGISTRY_MIRRORS}" "${DOCKER_INSECURE_REGISTRIES}"


echo "安装K8S服务到目录 ${INSTALL_TARGET_DIR}"
mkdirIfAbsent ${INSTALL_TARGET_DIR}
for SERVICE in kubectl kube-proxy kubelet
do
    echo "安装K8S服务：${SERVICE}"
    cp -r ${NOW_DIR}/${SERVICE} ${INSTALL_TARGET_DIR}
    sh ${INSTALL_TARGET_DIR}/${SERVICE}/install.sh "${LOCAL_IP}" "${APISERVER_DOMAIN}" "${CA_CERT_PASSWORD}"
done
# 启动服务
echo "K8S服务安装完毕，开始启动服务"


# 先重新加载下
systemctl daemon-reload
for SERVICE in flannel docker kube-proxy kubelet
do
    echo "启动服务：${SERVICE}"
    systemctl restart ${SERVICE} >/dev/null 2>&1 || echo "服务${SERVICE}启动疑似失败，请检查"
    systemctl enable ${SERVICE} >/dev/null 2>&1 || echo "服务${SERVICE}设置开机自启失败，请手动设置"
done

iptables -P FORWARD ACCEPT


echo "K8S客户端安装完毕"
