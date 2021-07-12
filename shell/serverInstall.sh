set -o nounset
set -e

###################################################################################################################
##
## 服务端安装
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


# ETCD安装到本地，HOST就是本地IP
ETCDHOST=${LOCAL_IP}

# etcd工作目录
ETCD_WORK_DIR=${INSTALL_TARGET_DIR}/etcd
# etcd配置文件
ETCD_CONF=${ETCD_WORK_DIR}/config/etcd.conf
# etcd存储数据的路径
ETCD_DATA_DIR=${ETCD_WORK_DIR}/data

# etcd实例名称
ETCD_NAME=k8s-etcd


# flannel网络的cidr
FLANNEL_IP=193.0.0.0/8
# 子网掩码长度
SUBNET_LEN=24




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


# 安装etcd函数开始
installEtcd() {
# 安装etcd
echo "安装etcd..."

# 先创建目录
mkdirIfAbsent ${ETCD_WORK_DIR}
mkdirIfAbsent ${ETCD_WORK_DIR}/config
mkdirIfAbsent ${ETCD_DATA_DIR}

yumInstall etcd

#配置etcd
cat << EOF > ${ETCD_CONF}
ETCD_DATA_DIR="${ETCD_DATA_DIR}"
ETCD_LISTEN_CLIENT_URLS="http://${ETCDHOST}:${ETCDPORT}"
ETCD_NAME="${ETCD_NAME}"
ETCD_ADVERTISE_CLIENT_URLS="http://${ETCDHOST}:${ETCDPORT}"
EOF


# etcd服务定义重写
cat << "EOF" > /usr/lib/systemd/system/etcd.service
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=${ETCD_WORK_DIR}
EnvironmentFile=-${ETCD_CONF}
# set GOMAXPROCS to number of processors
ExecStart=/bin/bash -c "GOMAXPROCS=$(nproc) /usr/bin/etcd --name=\"${ETCD_NAME}\" --data-dir=\"${ETCD_DATA_DIR}\" --listen-client-urls=\"${ETCD_LISTEN_CLIENT_URLS}\""
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

EOF
# 因为上边cat的时候EOF加了双引号，后边内容不会使用当前上下文变量替换，这里单独将workdir替换为实际的
sed -i "s#\${ETCD_WORK_DIR}#${ETCD_WORK_DIR}#g" /usr/lib/systemd/system/etcd.service
sed -i "s#\${ETCD_CONF}#${ETCD_CONF}#g" /usr/lib/systemd/system/etcd.service

echo "etcd安装完毕"

echo "配置etcd监听地址：http://${ETCDHOST}:${ETCDPORT}"
}
# 安装etcd函数结束



# 安装flannel函数开始
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

# 安装etcd
installEtcd
# 安装flannel
installFlannel "${LOCAL_IP}" "${ETCDPORT}"  "${LOCAL_IP}"


echo "安装K8S服务到目录 ${INSTALL_TARGET_DIR}"
mkdirIfAbsent ${INSTALL_TARGET_DIR}
for SERVICE in kubectl kube-apiserver kube-controller-manager kube-scheduler kube-proxy
do
    echo "安装K8S服务：${SERVICE}"
    cp -r ${NOW_DIR}/${SERVICE} ${INSTALL_TARGET_DIR}
    sh ${INSTALL_TARGET_DIR}/${SERVICE}/install.sh "${LOCAL_IP}" "${APISERVER_DOMAIN}" "${CA_CERT_PASSWORD}" "${LOCAL_IP}"
done
# 启动服务
echo "K8S服务安装完毕，开始启动服务"

# 先重新加载下
systemctl daemon-reload
for SERVICE in etcd kube-apiserver kube-controller-manager kube-scheduler kube-proxy
do
    echo "启动服务：${SERVICE}"
    systemctl restart ${SERVICE} >/dev/null 2>&1 || echo "服务${SERVICE}启动疑似失败，请检查"
    echo "设置服务开机自启：${SERVICE}"
    systemctl enable ${SERVICE} >/dev/null 2>&1 || echo "服务${SERVICE}设置开机自启失败，请手动设置"
done



# 设置flannel
echo "服务端所有服务启动完毕，初始化flannel"
# flannel消费的网络配置
etcdctl --endpoints="http://${LOCAL_IP}:${ETCDPORT}" set /atomic.io/network/config "{\"Network\":\"${FLANNEL_IP}\",\"SubnetLen\":${SUBNET_LEN}}" >/dev/null 2>&1
echo "配置flannel使用网络：${FLANNEL_IP}，subnetLen：${SUBNET_LEN}"

# 重启flannel，设置开机自启
systemctl restart flanneld
systemctl enable flanneld

iptables -P FORWARD ACCEPT

echo "KS8服务端安装完毕"

