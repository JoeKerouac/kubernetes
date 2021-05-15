set -o nounset
set -e

###################################################################################################################
##
## 服务端、客户端安装脚本(注意，服务端和客户端不要安装在同一台机器，不然有冲突，flannel在客户端和服务端都有安装)
##
###################################################################################################################

# 只有安装才需要设置变量
if [ ${INSTALL} == 'install' ]; then
    echo "当前是安装"
    LOCAL_IP=$1
    APISERVER_IP=$2
    CA_CERT_PASSWORD=$3
    echo "当前执行安装脚本指定的本地ip是：${LOCAL_IP}，当前指定的apiserver ip是：${APISERVER_IP}"
elif [ ${INSTALL} == 'uninstall' ]; then
    echo "当前是卸载"
    LOCAL_IP=0.0.0.0
    APISERVER_IP=0.0.0.0
    CA_CERT_PASSWORD=1
else
    echo "未知安装类型"
    exit
fi


# 如果指定目录不存在则创建
mkdirIfAbsent() {
	if [ ! -d $1 ]; then
	echo "目录[$1]不存在，创建..."
	mkdir -p $1
	fi
}

# 删除文件夹
rmDirIfAbsent() {
	if [ -d $1 ]; then
	echo "目录[$1]存在，删除..."
	rm -rf $1  || echo "${DIRS[$i]} 目录删除失败，您可以在稍后自己删除"
	fi
}


yumInstall() {
yum install -y $1 >/dev/null 2>&1
}

yumRemove() {
yum remove -y $1 >/dev/null 2>&1 || echo "卸载应用$1失败，请自行检查（可能是应用并不存在）"
}


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




###################################################################################################################
##
## 建议可以手动调整的变量
##
###################################################################################################################

# K8S集群安装文件、数据文件等根目录（etcd、docker等工作目录都会定义在这里边）
K8S_BASE_DIR=/data/k8s
# 日志根目录
LOG_ROOT_DIR=${K8S_BASE_DIR}/logs

# 证书过期时间，默认100年
CA_CRT_EXPIRE=36500
# 集群中admin用户的名字
ADMIN_USER=admin
# 公司所属城市
STATE="北京"
# 公司名
ENTERPRISE_NAME="JoeKerouac"
# 申请证书所属部门
ORGANIZATIONAL_UNIT="架构组"


# 默认ETCD和apiserver装在一起
ETCDHOST=${APISERVER_IP}
# 使用默认端口号
ETCDPORT=2379
# etcd实例名称
ETCD_NAME=default

# apiserver使用的端口号
APISERVER_SECURE_PORT=6443
# controller-manager提供HTTPS服务的端口号
CONTROLLER_MANAGER_PORT=10257
# HTTPS服务的端口
SCHEDULER_PORT=10259
# kubelet监听的端口号
KUBELET_PORT=10250


# flannel网络配置（K8S使用），注意，core.sh中有一个VIP_RANGE，不要冲突了
FLANNEL_IP=193.0.0.0/8
# flannel子网掩码长度
SUBNET_LEN=24

# service ip范围，注意，子网掩码不能比12小
VIP_RANGE=194.10.0.0/16
# apiserver的service ip，肯定是VIP_RANGE中的第一个IP
MASTER_IP=194.10.0.1


# docker仓库代理，使用自己的nexus仓库代理
DOCKER_REGISTRY_MIRRORS='"https://uyah70su.mirror.aliyuncs.com"'
# docker仓库私服，如果有自己的私服请配置到这里
DOCKER_INSECURE_REGISTRIES='""'


# 使用阿里云的pause pod镜像
PAUSE_POD=registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.1


# core-dns配置
# core-dns官方文档：https://github.com/coredns/deployment/tree/master/kubernetes
# 注意，service IP必须符合集群定义，集群的第一个IP（194.10.0.1）肯定是apiserver占用了，所以这里用2
CLUSTER_DNS_IP=194.10.0.2
# domain配置，保持kubelet和core-dns一致；
CLUSTER_DOMAIN=cluster.local
UPSTREAMNAMESERVER=/etc/resolv.conf
# coreDNS的指标会以Prometheus标准暴漏出去，这里指定暴漏的时候端口号是9153
PROMETHEUS_PORT=9153
# 设置TTL为300秒，只有服务名不变、ip变化才会受TTL影响；
DNS_TTL=300


# kuboard面板的host
KUBOARD_HOST=kuboard.kube.com



###################################################################################################################
##
## 默认配置，如果没有特殊需求不用更改
##
###################################################################################################################


# K8S相关服务的配置文件目录
CONFIG_DIR=${K8S_BASE_DIR}/config
# 存放证书文件
SECURE_DIR=${K8S_BASE_DIR}/secure
# 存放K8S可执行文件的目录（里边要包含kube-apiserver、controller-manager、kube-scheduler、kubelet、kube-proxy）
BIN_DIR=${K8S_BASE_DIR}/bin
# 工作目录
WORKSPACE_DIR=${K8S_BASE_DIR}/workspace
# docker工作目录，docker镜像等都在这个目录存储
DOCKER_WORK_DIR=${K8S_BASE_DIR}/docker
# etcd的工作目录
ETCD_WORK_DIR=${K8S_BASE_DIR}/etcd
# etcd存储数据的目录
ETCD_DATA_DIR=${K8S_BASE_DIR}/etcd/default.etcd



# apiserver的日志目录
APISERVER_LOG_DIR=${LOG_ROOT_DIR}/apiserver
# controller-manager的日志目录
CONTROLLER_MANAGER_LOG_DIR=${LOG_ROOT_DIR}/controller-manager
# kube-scheduler的日志目录
SCHEDULER_LOG_DIR=${LOG_ROOT_DIR}/scheduler
# kubelet的日志目录
KUBELET_LOG_DIR=${LOG_ROOT_DIR}/kubelet
# kube-proxy的日志目录
KUBE_PROXY_LOG_DIR=${LOG_ROOT_DIR}/kube-proxy


# 目录定义到数组中，后边基于数组进行创建目录
DIRS=(${K8S_BASE_DIR} ${CONFIG_DIR} ${SECURE_DIR} ${BIN_DIR} ${WORKSPACE_DIR} ${DOCKER_WORK_DIR} ${ETCD_WORK_DIR} ${ETCD_DATA_DIR} ${LOG_ROOT_DIR} ${APISERVER_LOG_DIR} ${CONTROLLER_MANAGER_LOG_DIR} ${SCHEDULER_LOG_DIR} ${KUBELET_LOG_DIR} ${KUBE_PROXY_LOG_DIR})



# K8S集群ca文件配置，所有服务公用一个CA
CA_FILE=${SECURE_DIR}/ca.crt
# ca的key
CA_KEY_FILE=${SECURE_DIR}/ca.key
# admin用户的证书
ADMIN_CRT=${SECURE_DIR}/admin.crt
# admin用户的证书对应的key
ADMIN_KEY=${SECURE_DIR}/admin.key
# 服务器证书，用于提供HTTPS服务时使用的证书；注意要使用上边的CA签发；
TLS_CERT_FILE=${SECURE_DIR}/tls.crt
# 服务器证书对应的私钥
TLS_PRIVATE_KEY=${SECURE_DIR}/tls.key
# serviceAccount公钥（私钥也可以）文件，公钥（私钥也可以，这里实际上就是用的私钥），用于验证serviceAccount令牌
SERVICE_ACCOUNT_FILE=${SECURE_DIR}/serviceAccount.key
# serviceAccount私钥文件
SERVICE_ACCOUNT_PRIVATE_FILE=${SECURE_DIR}/serviceAccount.key



# 指定kubelet使用的cgroup与docker一致
CGROUP=systemd



# apiserver监听地址，注意，1.20.0版本的apiserver已经禁用了不安全端口，所以无需指定
APISERVER_BIND_ADDRESS=${LOCAL_IP}
# apiserver存储在etcd中的数据的key的前缀
APISERVER_ETCD_PREFIX=/k8s/registry
# apiserver配置service时使用的envFile
APISERVER_ENV=${CONFIG_DIR}/apiserver.service.env
# apiserver的工作目录
APISERVER_WORK_DIR=${WORKSPACE_DIR}/apiserver
mkdirIfAbsent ${APISERVER_WORK_DIR}




# controller-manager配置service时使用的envFile
CONTROLLER_MANAGER_ENV=${CONFIG_DIR}/controller-manager.service.env
# controller-manager的工作目录
CONTROLLER_MANAGER_WORK_DIR=${WORKSPACE_DIR}/controller-manager
mkdirIfAbsent ${CONTROLLER_MANAGER_WORK_DIR}


# kube-scheduler配置service时使用的envFile
SCHEDULER_ENV=${CONFIG_DIR}/scheduler.service.env
# scheduler配置文件
SCHEDULER_CONFIG=${CONFIG_DIR}/scheduler.config
# scheduler的工作目录
SCHEDULER_WORK_DIR=${WORKSPACE_DIR}/scheduler
mkdirIfAbsent ${SCHEDULER_WORK_DIR}



# kubelet配置文件
KUBELET_CONFIG=${CONFIG_DIR}/kubelet.config
# kubelet配置service时使用的envFile
KUBELET_ENV=${CONFIG_DIR}/kubelet.service.env
# kubelet的工作目录
KUBELET_WORK_DIR=${WORKSPACE_DIR}/kubelet
mkdirIfAbsent ${KUBELET_WORK_DIR}



# kube-proxy配置service时使用的envFile
KUBE_PROXY_ENV=${CONFIG_DIR}/kube-proxy.service.env
# kube-proxy的工作目录
KUBE_PROXY_WORK_DIR=${WORKSPACE_DIR}/kube-proxy
mkdirIfAbsent ${KUBE_PROXY_WORK_DIR}




# 通用配置
KUBE_COMMON_CONFIG=${CONFIG_DIR}/common.config
# kubeconfig配置文件，定义了集群相关配置，例如连接的集群名、证书、apiserver地址等；
KUBECONFIG=${CONFIG_DIR}/kubeconfig.yaml





###################################################################################################################
##
## 通用函数
##
###################################################################################################################


# 创建K8S相关service通用的选项开始
createCommonConfig() {
# 通用选项
cat << EOF > ${KUBE_COMMON_CONFIG}
# 日志等级
KUBE_LOG_LEVEL=--v=0
# 证书
TLS_CERT_FILE=--tls-cert-file=${TLS_CERT_FILE}
# 证书私钥
TLS_PRIVATE_KEY=--tls-private-key-file=${TLS_PRIVATE_KEY}
# TLS最小版本号，指定1.2
TLS_MIN_VERSION=--tls-min-version=VersionTLS12
# 加密套件，写死几个
TLS_CIPHER_SUITES=--tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
# 指定ca证书，开启证书认证
CLIENT_CA=--client-ca-file=${CA_FILE}
# 输出日志到文件,注意要将logtostderr更改为false，默认是true，日志将会输出到stderr（标准错误输出流）而不是日志文件
LOGTOSTDERR=--logtostderr=false
EOF
}
# 创建K8S相关service通用的选项结束


# 创建证书开始（server和client通用）
createCert() {
echo "开始生成证书"
# 写入证书配置（注意， 其中alt_names中的IP是必须的，指向证书使用者的IP，注意，对于apiserver来说，MASTER_IP也是必须的，因为集群内部是通过apiserver的service ip访问的）
# 注意，keyUsage中必须要包含digitalSignature，否则K8S的Java客户端会报错
cat << EOF > ${SECURE_DIR}/common.csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
    
[ dn ]
C = CN
ST = ${STATE}
L = ${STATE}
O = ${ENTERPRISE_NAME}
OU = ${ORGANIZATIONAL_UNIT}
CN = ${ADMIN_USER}
    
[ req_ext ]
subjectAltName = @alt_names
    
[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster
DNS.5 = kubernetes.default.svc.cluster.local
IP.1 = ${LOCAL_IP}
IP.2 = ${MASTER_IP}
    
[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

# 生成一个2048bit的server.key
openssl genrsa -out ${TLS_PRIVATE_KEY} 2048 >/dev/null 2>&1
# 使用上边的CSR请求文件生成服务器证书CSR（证书请求）
openssl req -new -key ${TLS_PRIVATE_KEY} -out ${SECURE_DIR}/tls.csr -config ${SECURE_DIR}/common.csr.conf >/dev/null 2>&1
# 生成服务器证书
openssl x509 -req -in ${SECURE_DIR}/tls.csr -CA ${CA_FILE} -CAkey ${CA_KEY_FILE} -passin pass:${CA_CERT_PASSWORD} -CAcreateserial -out ${TLS_CERT_FILE} -days ${CA_CRT_EXPIRE} -extensions v3_ext -extfile ${SECURE_DIR}/common.csr.conf >/dev/null 2>&1
echo "证书生成完毕"
}
# 创建证书结束


# 安装kubectl开始
installKubectl() {
chmod +x ${BIN_DIR}/kubectl
# 放入本地库
cp ${BIN_DIR}/kubectl /usr/bin
# 使用kubectl配置一个kubeconfig文件
# kubectl命令说明详见：https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#config
# 设置默认集群，指定apiserver地址、ca证书；
${BIN_DIR}/kubectl config set-cluster default-cluster --kubeconfig=${KUBECONFIG} --server=https://${APISERVER_IP}:${APISERVER_SECURE_PORT} --certificate-authority=${CA_FILE} >/dev/null 2>&1
# 指定客户端证书，注意，命令行指定的admin是在kubeconfig中的用户名，该用户关联的证书对应的用户名不一定是admin，这个admin主要为了方便后边引用这个用户配置；
${BIN_DIR}/kubectl config set-credentials admin --kubeconfig=${KUBECONFIG} --certificate-authority=${CA_FILE} --client-key=${ADMIN_KEY} --client-certificate=${ADMIN_CRT} >/dev/null 2>&1
# 设置一个环境，指定该环境使用默认集群、admin用户
${BIN_DIR}/kubectl config set-context default-system --kubeconfig=${KUBECONFIG} --cluster=default-cluster --user=admin >/dev/null 2>&1
# 设置当前使用的上下文为上边配置的default-system
${BIN_DIR}/kubectl config use-context default-system --kubeconfig=${KUBECONFIG} >/dev/null 2>&1
# 为当前用户创建kubectl的配置目录，并将配置放入进去，方便后续kubectl操作
mkdirIfAbsent ~/.kube
cp ${KUBECONFIG} ~/.kube/config
}
# 安装kubectl结束






###################################################################################################################
##
## 服务端相关函数
##
###################################################################################################################



# 安装etcd函数开始
installEtcd() {
# 安装etcd
echo "安装etcd..."
yum install -y etcd >/dev/null 2>&1

#配置etcd
cat << EOF > /etc/etcd/etcd.conf
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
EnvironmentFile=-/etc/etcd/etcd.conf
# set GOMAXPROCS to number of processors
ExecStart=/bin/bash -c "GOMAXPROCS=$(nproc) /usr/bin/etcd --name=\"${ETCD_NAME}\" --data-dir=\"${ETCD_DATA_DIR}\" --listen-client-urls=\"${ETCD_LISTEN_CLIENT_URLS}\""
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

EOF
# 因为上边cat的时候EOF加了双引号，后边内容不会使用当前上下文变量替换，这里单独将workdir替换为实际的
sed -i "s#\${ETCD_WORK_DIR}#${ETCD_WORK_DIR}#g" /usr/lib/systemd/system/etcd.service

echo "etcd安装完毕"

echo "配置etcd监听地址：http://${ETCDHOST}:${ETCDPORT}"
}
# 安装etcd函数结束



# 安装apiserver
# installApiserver函数开始
installApiserver() {
echo "开始安装apiserver"
# apiserver配置
cat << EOF > ${APISERVER_ENV}
# 不允许特权容器
KUBE_ALLOW_PRIV=--allow-privileged=false
# apiserver监听地址
KUBE_API_ADDRESS=--bind-address=${APISERVER_IP}
# apiserver监听的HTTPS端口号
KUBE_API_SECURE_PORT=--secure-port=${APISERVER_SECURE_PORT}
# 准入控制器，详情参考：https://kubernetes.io/zh/docs/reference/access-authn-authz/admission-controllers/
KUBE_ADMISSION_CONTROL=--enable-admission-plugins=NamespaceLifecycle,NamespaceExists,LimitRanger,ServiceAccount,ResourceQuota
# 禁止匿名用户
KUBE_DISABLE_ANONYMOUS=--anonymous-auth=false
# apiserver的HTTPS端口鉴权规则
KUBE_AUTH=--authorization-mode=RBAC
# etcd的服务器地址
KUBE_ETCD_SERVERS=--etcd-servers=http://${ETCDHOST}:${ETCDPORT}
# k8s在etcd中的前缀
KUBE_ETCD_PREFIX=--etcd-prefix=${APISERVER_ETCD_PREFIX}
# nodePort可用的范围，设置所有端口可用
KUBE_SERVICE_NODE_PORT_RANGE=--service-node-port-range=1-65535


# 详细说明参考：https://kubernetes.io/zh/docs/tasks/configure-pod-container/configure-service-account/#service-account-token-volume-projection
SERVICE_ACCOUNT_ISSUER=--service-account-issuer=https://${APISERVER_IP}:${APISERVER_SECURE_PORT}/auth/realms/master/.well-known/openid-configuration
# serviceAccount相关密钥
SERVICE_ACCOUNT_FILE=--service-account-key-file=${SERVICE_ACCOUNT_FILE}
SERVICE_ACCOUNT_PRIVATE_FILE=--service-account-signing-key-file=${SERVICE_ACCOUNT_PRIVATE_FILE}

# kubelet使用的CA，这里统一使用一个CA
KUBELET_CA_FILE=--kubelet-certificate-authority=${CA_FILE}
# 用于连接kubelet时做认证的证书，只要是CA签署的即可，这里全局使用同一个证书
KUBELET_CRT_FILE=--kubelet-client-certificate=${ADMIN_CRT}
# 连接kubelet时认证证书的key
KUBELET_KEY_FILE=--kubelet-client-key=${ADMIN_KEY}
LOG_DIR=--log-dir=${APISERVER_LOG_DIR}
# service ip范围，注意不要跟任何pod ip和主机ip冲突
VIP_RANGE=--service-cluster-ip-range=${VIP_RANGE}

# 聚合层相关参数
AGGREGATION=--requestheader-client-ca-file=${CA_FILE} --proxy-client-cert-file=${ADMIN_CRT} --proxy-client-key-file=${ADMIN_KEY} --requestheader-extra-headers-prefix=X-Remote-Extra- --requestheader-group-headers=X-Remote-Group --requestheader-username-headers=X-Remote-User
EOF


chmod +x ${BIN_DIR}/kube-apiserver
#api-server服务
cat << EOF > /usr/lib/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
After=etcd.service

[Service]
WorkingDirectory=${APISERVER_WORK_DIR}
EnvironmentFile=${KUBE_COMMON_CONFIG}
EnvironmentFile=${APISERVER_ENV}
ExecStart=${BIN_DIR}/kube-apiserver \
		\$KUBE_LOG_LEVEL \
		\$TLS_CERT_FILE \
		\$TLS_PRIVATE_KEY \
		\$TLS_MIN_VERSION \
		\$TLS_CIPHER_SUITES \
		\$CLIENT_CA \
        \$LOGTOSTDERR \
		\$KUBE_ALLOW_PRIV \
		\$KUBE_API_ADDRESS \
		\$KUBE_API_SECURE_PORT \
		\$KUBE_ADMISSION_CONTROL \
		\$KUBE_DISABLE_ANONYMOUS \
		\$KUBE_AUTH \
		\$KUBE_ETCD_SERVERS \
	    \$KUBE_ETCD_PREFIX \
		\$SERVICE_ACCOUNT_ISSUER \
		\$SERVICE_ACCOUNT_FILE \
		\$SERVICE_ACCOUNT_PRIVATE_FILE \
		\$KUBELET_CA_FILE \
		\$KUBELET_CRT_FILE \
		\$KUBELET_KEY_FILE \
		\$LOG_DIR \
		\$VIP_RANGE \
        \$AGGREGATION \
        \$KUBE_SERVICE_NODE_PORT_RANGE
Restart=on-failure
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
echo "apiserver安装完成"
}
# installApiserver函数结束



# 安装controller-manager
# installControllerManager函数开始
installControllerManager() {
echo "开始安装controller-manager"
# 配置文件
cat << EOF > ${CONTROLLER_MANAGER_ENV}
# 绑定本地监听地址
BIND_ADDRESS=--bind-address=${LOCAL_IP}
# 监听的端口
CONTROLLER_MANAGER_PORT=--secure-port=${CONTROLLER_MANAGER_PORT}
# 对serviceAccount令牌签名的私钥
SERVICE_ACCOUNT_PRIVATE_FILE=--service-account-private-key-file=${SERVICE_ACCOUNT_PRIVATE_FILE}
# kubelet日志目录
KUBELET_LOG_DIR=--log-dir=${CONTROLLER_MANAGER_LOG_DIR}
# 指定kubeconfig
KUBECONFIG=--kubeconfig=${KUBECONFIG}
# 节点的子网掩码长度
CIDR_MASK=--node-cidr-mask-size-ipv4=16
# 指定CA证书，将会包含在service account的secret中，没有该选项安装coredns、dashboard等插件时会报错
ROOT_CA_FILE=--root-ca-file=${CA_FILE}
EOF



chmod +x ${BIN_DIR}/kube-controller-manager
#controller-manager服务
cat << EOF > /usr/lib/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=${CONTROLLER_MANAGER_WORK_DIR}
EnvironmentFile=${KUBE_COMMON_CONFIG}
EnvironmentFile=${CONTROLLER_MANAGER_ENV}
ExecStart=${BIN_DIR}/kube-controller-manager \
	    \$KUBE_LOG_LEVEL \
		\$TLS_CERT_FILE \
		\$TLS_PRIVATE_KEY \
		\$TLS_MIN_VERSION \
		\$TLS_CIPHER_SUITES \
		\$CLIENT_CA \
        \$LOGTOSTDERR \
		\$BIND_ADDRESS \
		\$CONTROLLER_MANAGER_PORT \
		\$SERVICE_ACCOUNT_PRIVATE_FILE \
		\$KUBELET_LOG_DIR \
		\$KUBECONFIG \
		\$CIDR_MASK \
        \$ROOT_CA_FILE
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
echo "controller-manager安装完成"
}
# installControllerManager函数结束



# 安装kube-scheduler
# installKubeScheduler函数开始
installKubeScheduler() {
echo "开始安装kube-scheduler"
# 生成kube-scheduler的配置文件，kubelet通过--config命令引用
cat << EOF > ${SCHEDULER_CONFIG}
apiVersion: kubescheduler.config.k8s.io/v1beta1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: ${KUBECONFIG}
EOF


# 配置文件
cat << EOF > ${SCHEDULER_ENV}
# 日志目录
LOG_DIR=--log-dir=${SCHEDULER_LOG_DIR}
# 绑定本地监听地址
BIND_ADDRESS=--bind-address=${LOCAL_IP}
# 禁用不安全的服务
DISABLE_INSECURE=--port=0
# HTTPS服务的端口
PORT=--secure-port=${SCHEDULER_PORT}
# 配置文件，参考：https://kubernetes.io/zh/docs/reference/scheduling/config/
CONFIG=--config=${SCHEDULER_CONFIG}
EOF



chmod +x ${BIN_DIR}/kube-scheduler
#scheduler服务
cat << EOF > /usr/lib/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler Plugin
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=${SCHEDULER_WORK_DIR}
EnvironmentFile=${KUBE_COMMON_CONFIG}
EnvironmentFile=${SCHEDULER_ENV}
ExecStart=${BIN_DIR}/kube-scheduler \
		\$KUBE_LOG_LEVEL \
		\$TLS_CERT_FILE \
		\$TLS_PRIVATE_KEY \
		\$TLS_MIN_VERSION \
		\$TLS_CIPHER_SUITES \
		\$CLIENT_CA \
        \$LOGTOSTDERR \
		\$LOG_DIR \
		\$BIND_ADDRESS \
		\$DISABLE_INSECURE \
		\$PORT \
		\$CONFIG
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "kube-scheduler安装完成"
}
# installKubeScheduler函数结束



# 安装core-dns函数开始
installCoreDns() {
# 将dns安装文件copy到config目录中
cp ${NOW_DIR}/core-dns.yml ${CONFIG_DIR}/core-dns.yml

# 替换dns中的动态参数
sed -i "s#\${CLUSTER_DOMAIN}#${CLUSTER_DOMAIN}#g" ${CONFIG_DIR}/core-dns.yml
sed -i "s#\${DNS_TTL}#${DNS_TTL}#g" ${CONFIG_DIR}/core-dns.yml
sed -i "s#\${PROMETHEUS_PORT}#${PROMETHEUS_PORT}#g" ${CONFIG_DIR}/core-dns.yml
sed -i "s#\${UPSTREAMNAMESERVER}#${UPSTREAMNAMESERVER}#g" ${CONFIG_DIR}/core-dns.yml
sed -i "s#\${CLUSTER_DNS_IP}#${CLUSTER_DNS_IP}#g" ${CONFIG_DIR}/core-dns.yml


echo "安装core-dns"
kubectl apply -f ${CONFIG_DIR}/core-dns.yml >/dev/null 2>&1
echo "core-dns安装成功"
}
# 安装core-dns函数结束


# 安装ingress函数开始
installIngress() {
# 复制ingress安装文件到config目录
cp ${NOW_DIR}/ingress-traefik.yml ${CONFIG_DIR}/ingress-traefik.yml

echo "安装traefik ingress"
kubectl apply -f ${CONFIG_DIR}/ingress-traefik.yml >/dev/null 2>&1
echo "traefik ingress安装成功"
}
# 安装ingress函数结束

# 安装kuboard函数开始
installKuboard() {
cp ${NOW_DIR}/kuboard.yml ${CONFIG_DIR}/kuboard.yml

# 变量替换
sed -i "s#\${etcdAddr}#http://${ETCDHOST}:${ETCDPORT}#g" ${CONFIG_DIR}/kuboard.yml
sed -i "s#\${kuboardHost}#${KUBOARD_HOST}#g" ${CONFIG_DIR}/kuboard.yml

echo "安装kuboard"
kubectl apply -f ${CONFIG_DIR}/kuboard.yml >/dev/null 2>&1
echo "kuboard安装成功"
}
# 安装kuboard函数结束


# 安装metrics-server函数开始
installMetricsServer() {
cp ${NOW_DIR}/metrics-server.yml ${CONFIG_DIR}/metrics-server.yml

echo "安装metrics-server"
kubectl apply -f ${CONFIG_DIR}/metrics-server.yml >/dev/null 2>&1
echo "metrics-server安装成功"
}
# 安装metrics-server函数结束

###################################################################################################################
##
## 客户端相关函数
##
###################################################################################################################


# 安装docker函数开始
installDocker() {
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
# docker会将iptable规则设置为DROP，但是我们必须要设置FORWAD规则为ACCEPT允许转发，否则跨node的pod将无法通讯
sed -r -i "/^ExecStart/iExecStartPost=/sbin/iptables -P FORWARD ACCEPT" /usr/lib/systemd/system/docker.service
echo "docker-ce安装完成"
}
# 安装docker函数结束


# 安装flannel函数开始
installFlannel() {
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



# installKubelet函数开始
installKubelet() {
echo "开始安装kubelet"

# 生成kubelet的配置文件，kubelet通过--config命令引用
cat << EOF > ${KUBELET_CONFIG}
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: "${LOCAL_IP}"
port: ${KUBELET_PORT}
# 鉴权模式，通过认证的所有用户都允许操作
authorization:
    mode: "AlwaysAllow"

EOF

# 配置文件
cat << EOF > ${KUBELET_ENV}
# 禁止匿名用户
KUBE_DISABLE_ANONYMOUS=--anonymous-auth=false
# 指定config文件，上边会输出
KUBE_CONFIG=--config=${KUBELET_CONFIG}
# kubelet日志目录
KUBELET_LOG_DIR=--log-dir=${KUBELET_LOG_DIR}
# 指定kubeconfig
KUBECONFIG=--kubeconfig=${KUBECONFIG}
# 指定cgroup，要保证和docker的一致
CGROUP=--cgroup-driver=${CGROUP}
# 替换默认的pause pod
PAUSE_POD=--pod-infra-container-image=${PAUSE_POD}
# 使用本地IP作为host name，默认使用主机名，使用主机名有个问题就是apiserver访问kubelet的时候会有问题，因为主机名解析不出来IP
HOST_NAME=--hostname-override=${LOCAL_IP}
# kubelet工作目录
WORK_DIR=--root-dir=${KUBELET_WORK_DIR}
# 集群内的DNS地址
CLUSTER_DNS=--cluster-dns=${CLUSTER_DNS_IP}
# 集群的域名，DNS使用
CLUSTER_DOMAIN=--cluster-domain=${CLUSTER_DOMAIN}
EOF



chmod +x ${BIN_DIR}/kubelet
yumInstall which
SWAPOFF=`which swapoff`
#kubelet服务
cat << EOF > /usr/lib/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=${KUBELET_WORK_DIR}
EnvironmentFile=${KUBE_COMMON_CONFIG}
EnvironmentFile=${KUBELET_ENV}
# kubelet要禁用swap
ExecStartPre=${SWAPOFF} -a
ExecStart=${BIN_DIR}/kubelet \
	    \$KUBE_LOG_LEVEL \
		\$TLS_CERT_FILE \
		\$TLS_PRIVATE_KEY \
		\$TLS_MIN_VERSION \
		\$TLS_CIPHER_SUITES \
		\$CLIENT_CA \
        \$LOGTOSTDERR \
	    \$KUBE_DISABLE_ANONYMOUS \
	    \$KUBE_CONFIG \
		\$KUBELET_LOG_DIR \
	    \$KUBECONFIG \
		\$CGROUP \
		\$PAUSE_POD \
		\$HOST_NAME \
		\$WORK_DIR \
        \$CLUSTER_DNS \
        \$CLUSTER_DOMAIN
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
echo "kubelet安装完毕"
}
# installKubelet函数结束



# installKubeProxy函数开始
installKubeProxy() {
echo "开始安装kube-proxy"
# 配置文件
cat << EOF > ${KUBE_PROXY_ENV}
# 绑定本地监听地址
BIND_ADDRESS=--bind-address=${LOCAL_IP}
# kubelet日志目录
KUBE_PROXY_LOG_DIR=--log-dir=${KUBE_PROXY_LOG_DIR}
# 指定kubeconfig
KUBECONFIG=--kubeconfig=${KUBECONFIG}
HOST_NAME=--hostname-override=${LOCAL_IP}
# 指定pod网络段
NETWORK=--cluster-cidr=${FLANNEL_IP}
EOF

# kube-proxy依赖
yumInstall conntrack

chmod +x ${BIN_DIR}/kube-proxy
#kube-proxy服务，注意，kube-proxy没有公共参数
cat << EOF > /usr/lib/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=${KUBE_PROXY_WORK_DIR}
EnvironmentFile=${KUBE_PROXY_ENV}
ExecStart=${BIN_DIR}/kube-proxy \
		\$BIND_ADDRESS \
		\$KUBE_PROXY_LOG_DIR \
		\$KUBECONFIG \
		\$HOST_NAME \
        \$NETWORK
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
echo "kube-proxy安装完毕"
}
# installKubeProxy函数结束




###################################################################################################################
##
## 安装、卸载函数
##
###################################################################################################################


# 安装函数开始
install() {
# 创建相关目录，后边所有函数都依赖这里的目录初始化
for ((i=0; i < ${#DIRS[*]}; i++))
do
    mkdirIfAbsent ${DIRS[$i]}
done


# 将安装包中证书文件、二进制文件移动到本地安装目录
cp -r ${NOW_DIR}/secure/* ${SECURE_DIR}
cp -r ${NOW_DIR}/bin/* ${BIN_DIR}


# 创建证书、安装service通用参数、安装kubectl
createCert
createCommonConfig
installKubectl


systemctl stop firewalld && echo "关闭防火墙"
systemctl disable firewalld


# 根据类型安装不同的服务
if [ ${TYPE} == 'server' ]; then
    # 临时开启转发
    sysctl -w net.ipv4.ip_forward=1
    # 永久开启转发，重启生效
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "当前安装类型是server"
    installEtcd
    installFlannel
    installApiserver
    installControllerManager
    installKubeScheduler
    installKubeProxy
    
    # 启动服务
    echo "服务安装完毕，开始启动服务"
    # 先重新加载下
    systemctl daemon-reload
    for SERVICE in etcd kube-apiserver kube-controller-manager kube-scheduler kube-proxy
    do
        echo "启动服务：${SERVICE}"
        systemctl restart ${SERVICE} >/dev/null 2>&1
        systemctl enable ${SERVICE} >/dev/null 2>&1
    done
    
    echo "服务端所有服务启动完毕"
    # flannel消费的网络配置
    etcdctl --endpoints="http://${ETCDHOST}:${ETCDPORT}" set /atomic.io/network/config "{\"Network\":\"${FLANNEL_IP}\",\"SubnetLen\":${SUBNET_LEN}}" >/dev/null 2>&1
    echo "配置flannel使用网络：${FLANNEL_IP}，subnetLen：${SUBNET_LEN}"
    
    
    installCoreDns
    installIngress
    installKuboard
    installMetricsServer
    
    systemctl restart flanneld
    systemctl enable flanneld
    
    echo "服务端安装完成！！！"
elif [ ${TYPE} == 'client' ]; then
	echo "当前安装类型是client"
    installFlannel
    installDocker
    installKubelet
    installKubeProxy
    
    # 启动服务，注意启动顺序
    echo "服务安装完毕，开始启动服务"
    # 先重新加载下
    systemctl daemon-reload
    for SERVICE in flanneld docker kubelet kube-proxy
    do
        echo "启动服务：${SERVICE}"
        systemctl restart ${SERVICE} >/dev/null 2>&1
        systemctl enable ${SERVICE} >/dev/null 2>&1
    done
    echo "客户端所有服务启动完毕"
    
    echo "客户端安装完成！！！"
else
    echo "当前安装类型[${TYPE}]未知"
    exit
fi

# 最后要设置FORWAD规则为ACCEPT允许转发，否则跨node的pod将无法通讯
iptables -P FORWARD ACCEPT
}
# 安装函数结束


# 卸载函数开始
uninstall() {

# kubectl卸载
rm -rf ~/.kube/config
rm -rf /usr/bin/kubectl


# 根据类型卸载不同的服务
if [ ${TYPE} == 'server' ]; then
    for SERVICE in flanneld etcd kube-apiserver kube-controller-manager kube-scheduler kube-proxy
    do
        echo "停止服务：${SERVICE}"
        # 因为脚本加了-e，所以如果命令执行失败是会退出了，在结尾加上||避免退出
        systemctl stop ${SERVICE} >/dev/null 2>&1 || echo "" > /dev/null
        systemctl disable ${SERVICE} >/dev/null 2>&1 || echo "" > /dev/null
    done
    
    # 手动卸载K8S服务
    for SERVICE in flanneld kube-apiserver kube-controller-manager kube-scheduler kube-proxy
    do
        echo "卸载服务：${SERVICE}"
        rm -rf /usr/lib/systemd/system/${SERVICE}.service || echo "" > /dev/null
    done
    
    
    echo "卸载服务：etcd"
    yumRemove etcd
    yumRemove flannel
elif [ ${TYPE} == 'client' ]; then
    # 必须安装glusterfs-fuse，否则挂载gluster的volume会失败
    yumInstall glusterfs-fuse
    for SERVICE in kubelet kube-proxy flannel docker
    do
        echo "停止服务：${SERVICE}"
        systemctl stop ${SERVICE} >/dev/null 2>&1 || echo "" > /dev/null
        systemctl disable ${SERVICE} >/dev/null 2>&1 || echo "" > /dev/null
    done
    
    # 手动卸载K8S服务
    for SERVICE in kubelet kube-proxy
    do
        echo "卸载服务：${SERVICE}"
        rm -rf /usr/lib/systemd/system/${SERVICE}.service || echo "" > /dev/null
    done
    
    # yum管理的使用yum卸载
    for SERVICE in flannel docker-ce
    do
        echo "卸载服务：${SERVICE}"
        yumRemove ${SERVICE}
    done
else
    echo "当前安装类型[${TYPE}]未知"
    exit
fi

# 最后删除相关目录（K8S、etcd、docker等数据目录都在这里删除），因为文件可能会被挂载，这里先给取消挂载后边才能删除
df -h | awk '{print $6}' | grep '^${K8S_BASE_DIR}' | xargs -I {} umount {} > /dev/null 2>&1
for ((i=0; i < ${#DIRS[*]}; i++))
do
    rmDirIfAbsent ${DIRS[$i]}
done

echo "卸载完成"
}
# 卸载函数结束



###################################################################################################################
##
## 本脚本实际执行逻辑
##
###################################################################################################################

# 只有安装才需要设置变量
if [ ${INSTALL} == 'install' ]; then
    install
elif [ ${INSTALL} == 'uninstall' ]; then
    uninstall
fi
