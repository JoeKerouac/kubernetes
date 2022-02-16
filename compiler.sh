set -o nounset
set -e


###################################################################################################################
##
## 编译生成K8S各个组件的安装包，编译完毕后在需要安装K8S组件的机器执行安装包即可，注意，需要将安装包放在TARGET_BASE_DIR目录下（默认/data/k8s）
## 需要一个参数：ca证书密码
##
###################################################################################################################


CA_CERT_PASSWORD=$1
UPSTREAMNAMESERVER=$2


# 如果指定目录不存在则创建
mkdirIfAbsent() {
	if [ ! -d $1 ]; then
	echo "目录[$1]不存在，创建..."
	mkdir -p $1
	fi
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
## 需修改的配置
##
###################################################################################################################







###################################################################################################################
##
## 一般无需修改的配置
##
###################################################################################################################


# apiserver监听的端口号，HTTPS端口
APISERVER_SECURE_PORT=6443
# controller-manager监听的端口号
CONTROLLER_MANAGER_PORT=10257
# scheduler监听端口号
SCHEDULER_PORT=10259
KUBELET_PORT=10250


# K8S在目标机器的安装根路径
TARGET_BASE_DIR=/data/k8s
# 网络配置（K8S使用），注意，不要和VIP_RANGE，不要冲突了
CLUSTER_CIDR=193.0.0.0/8
# apiserver在etcd中存储的数据的前缀
APISERVER_ETCD_PREFIX=/k8s/data
# service ip范围，注意，子网掩码不能比12小
VIP_RANGE=194.10.0.0/16
# 集群DNS地址,注意，service IP必须符合集群定义，集群的第一个IP（194.10.0.1）肯定是apiserver占用了，所以这里用2
CLUSTER_DNS_IP=194.10.0.2
# 集群域名后缀，用于生成/etc/resolve.conf解析DNS用
CLUSTER_DOMAIN=cluster.local
PAUSE_POD=registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.1
CGROUP=systemd
# kubelet同步configmap（configmap可以作为volume挂载到容器中，挂载后kubelet会定时将configmap的变更更新到pod中）的时间间隔，默认1m，时间越小kubelet资源消耗越高
SYNC_FREQUENCY=1m



# 组件安装通用文件头
COMPONENT_INSTALL_HEADER=${NOW_DIR}/shell/componentInstallHeader.sh
# K8S安装版本，目前是固定的
K8S_VERSION=v1.20.0

###################################################################################################################
##
## 通用函数定义
##
###################################################################################################################

# ssh相关函数自动输入密码，使用示例：execSSHWithoutPasswd 'ssh root@192.168.56.1 "df -h"' 123456，注意，这里命令只能执行一行
function execSSHWithoutPasswd() {
# 函数依赖于expect
yum install -q -y expect

expect << EOF
# 设置超时时间，单位秒
set time 100

spawn $1
expect {
"*yes/no*" { send "yes\r"; exp_continue }
"*password:" { send "$2\r" }
}
expect eof
EOF
} >/dev/null 2>&1


# 在远程机器上执行一条指令，需要六个参数（最后一个可以不传），远程机器端口、执行用户、远程机器IP、密码、要执行的指令、日志输出前需要增加的内容
function execRemote() {
# 这里第6个参数可以不设置，所以使用${xxx:-}这种形式，如果没有设置不会报错而是给个空串
echo -e "${6:-}在机器[${3}]上使用用户[${2}]执行指令[${5}]"
execSSHWithoutPasswd "ssh -p ${1} ${2}@${3} \"${5}\"" ${4}
}


###################################################################################################################
##
## 生成安装文件通用部分
##
###################################################################################################################


# 注意，下面几个参数在componentInstallHeader.sh中也有使用
# CA证书过期时间，默认100年
CA_CRT_EXPIRE=${CA_CRT_EXPIRE}
# 公司名
ENTERPRISE_NAME=${ENTERPRISE_NAME}
# admin用户的名字
ADMIN_USER=${ADMIN_USER}
# admin用户所属的组
ADMIN_USER_GROUP=${ADMIN_USER_GROUP}
# 申请证书所属部门
ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}
# 公司所属城市
STATE=${STATE}


# 安装文件目标目录创建
TARGET_DIR=${NOW_DIR}/target
# 先清空目录
rm -rf ${TARGET_DIR}
mkdirIfAbsent ${TARGET_DIR}

# 存放生成的各种安装文件的目录
INSTALLER_DIR=${TARGET_DIR}/installer
# 通用脚本部分
mkdirIfAbsent ${INSTALLER_DIR}


# 存放生成的K8S各项组件的安装文件的目录定义
APISERVER_INSTALLER_DIR=${INSTALLER_DIR}/kube-apiserver
mkdirIfAbsent ${APISERVER_INSTALLER_DIR}
mkdirIfAbsent ${APISERVER_INSTALLER_DIR}/secure
mkdirIfAbsent ${APISERVER_INSTALLER_DIR}/config
mkdirIfAbsent ${APISERVER_INSTALLER_DIR}/bin

CM_INSTALLER_DIR=${INSTALLER_DIR}/kube-controller-manager
mkdirIfAbsent ${CM_INSTALLER_DIR}
mkdirIfAbsent ${CM_INSTALLER_DIR}/secure
mkdirIfAbsent ${CM_INSTALLER_DIR}/config
mkdirIfAbsent ${CM_INSTALLER_DIR}/bin

SCHEDULER_INSTALLER_DIR=${INSTALLER_DIR}/kube-scheduler
mkdirIfAbsent ${SCHEDULER_INSTALLER_DIR}
mkdirIfAbsent ${SCHEDULER_INSTALLER_DIR}/secure
mkdirIfAbsent ${SCHEDULER_INSTALLER_DIR}/config
mkdirIfAbsent ${SCHEDULER_INSTALLER_DIR}/bin

KUBELET_INSTALLER_DIR=${INSTALLER_DIR}/kubelet
mkdirIfAbsent ${KUBELET_INSTALLER_DIR}
mkdirIfAbsent ${KUBELET_INSTALLER_DIR}/secure
mkdirIfAbsent ${KUBELET_INSTALLER_DIR}/config
mkdirIfAbsent ${KUBELET_INSTALLER_DIR}/bin

PROXY_INSTALLER_DIR=${INSTALLER_DIR}/kube-proxy
mkdirIfAbsent ${PROXY_INSTALLER_DIR}
mkdirIfAbsent ${PROXY_INSTALLER_DIR}/secure
mkdirIfAbsent ${PROXY_INSTALLER_DIR}/config
mkdirIfAbsent ${PROXY_INSTALLER_DIR}/bin

KUBECTL_INSTALLER_DIR=${INSTALLER_DIR}/kubectl
mkdirIfAbsent ${KUBECTL_INSTALLER_DIR}
mkdirIfAbsent ${KUBECTL_INSTALLER_DIR}/secure
mkdirIfAbsent ${KUBECTL_INSTALLER_DIR}/config
mkdirIfAbsent ${KUBECTL_INSTALLER_DIR}/bin

# 插件安装
PLUGIN_INSTALLER_DIR=${INSTALLER_DIR}/plugin

# 安全文件生成目录
K8S_SECURE_TEMP_DIR=${TARGET_DIR}/secure


# 生成CA，本脚本对于kubelet和apiserver使用同一个ca，所以这里只生成一个ca
echo "准备生成相关证书（CA证书、admin用户证书）"
# 创建这个目录
mkdirIfAbsent ${K8S_SECURE_TEMP_DIR}
# 开始生成证书
# 先生成CA的key
#生成一个2048bit的ca.key，使用aes256加密这个密钥
openssl genrsa -aes256 -out ${K8S_SECURE_TEMP_DIR}/ca.key -passout pass:${CA_CERT_PASSWORD} 2048 >/dev/null  2>&1
echo "ca证书密钥生成完毕"
# 使用CA的key生成一个自签名的CA证书，CA证书必须有一个DN，这里选择O
openssl req -x509 -new -nodes -key ${K8S_SECURE_TEMP_DIR}/ca.key -passin pass:${CA_CERT_PASSWORD} -subj "/O=${ENTERPRISE_NAME}" -days ${CA_CRT_EXPIRE} -out ${K8S_SECURE_TEMP_DIR}/ca.crt >/dev/null  2>&1
echo "ca证书生成完毕"


# 生成一个2048bit的admin用户的key
openssl genrsa -out ${K8S_SECURE_TEMP_DIR}/admin.key 2048 >/dev/null 2>&1
# 使用上边的CSR请求文件生成admin用户证书CSR（证书请求）
openssl req -new -key ${K8S_SECURE_TEMP_DIR}/admin.key -subj "/CN=${ADMIN_USER}/O=${ADMIN_USER_GROUP}" -out ${K8S_SECURE_TEMP_DIR}/admin.csr >/dev/null 2>&1
# 生成admin用户的证书，注意要使用上边生成的ca证书签署
openssl x509 -req -in ${K8S_SECURE_TEMP_DIR}/admin.csr -CA ${K8S_SECURE_TEMP_DIR}/ca.crt -CAkey ${K8S_SECURE_TEMP_DIR}/ca.key -passin pass:${CA_CERT_PASSWORD} -CAcreateserial -out ${K8S_SECURE_TEMP_DIR}/admin.crt -days ${CA_CRT_EXPIRE} -extensions v3_ext >/dev/null  2>&1
echo "使用ca证书签名的admin用户证书生成完毕"

# 生成service-account使用的key
openssl genrsa -out ${K8S_SECURE_TEMP_DIR}/serviceAccount.key >/dev/null 2>&1




# kubectl命令所在位置
KUBECTL=${NOW_DIR}/release/${K8S_VERSION}/kubectl
chmod +x ${KUBECTL}



###################################################################################################################
##
## apiserver安装文件生成
##
###################################################################################################################

echo "生成 apiserver 安装文件到 ${APISERVER_INSTALLER_DIR}"
# 生成安装必要文件
cp ${NOW_DIR}/release/${K8S_VERSION}/kube-apiserver ${APISERVER_INSTALLER_DIR}/bin
cp ${K8S_SECURE_TEMP_DIR}/serviceAccount.key ${APISERVER_INSTALLER_DIR}/secure/serviceAccount.key
cp ${K8S_SECURE_TEMP_DIR}/ca.crt ${APISERVER_INSTALLER_DIR}/secure/kubelet.ca.crt
cp ${K8S_SECURE_TEMP_DIR}/ca.crt ${APISERVER_INSTALLER_DIR}/secure/apiserver.ca.crt
cp ${K8S_SECURE_TEMP_DIR}/ca.key ${APISERVER_INSTALLER_DIR}/secure/apiserver.ca.key
# 这里的admin.crt是连接kubelet时使用的，需要是apiserver的CA签发的
cp ${K8S_SECURE_TEMP_DIR}/admin.crt ${APISERVER_INSTALLER_DIR}/secure/admin.crt
cp ${K8S_SECURE_TEMP_DIR}/ca.key ${APISERVER_INSTALLER_DIR}/secure/kubelet.ca.key
cp ${K8S_SECURE_TEMP_DIR}/admin.key ${APISERVER_INSTALLER_DIR}/secure/admin.key


###############
# 开始生成安装脚本
###############
cp ${COMPONENT_INSTALL_HEADER} ${APISERVER_INSTALLER_DIR}/install.sh
# 变量定义，从当前环境继承一些变量
cat << EOF >> ${APISERVER_INSTALLER_DIR}/install.sh
# 基础目录
BASE_DIR=${TARGET_BASE_DIR}/kube-apiserver
VIP_RANGE=${VIP_RANGE}
# apiserver监听的端口号，HTTPS端口
APISERVER_SECURE_PORT=${APISERVER_SECURE_PORT}
# etcd的服务地址
APISERVER_ETCD_PREFIX=${APISERVER_ETCD_PREFIX}


# 注意，下面几个参数在componentInstallHeader.sh中也有使用
# CA证书过期时间，默认100年
CA_CRT_EXPIRE=${CA_CRT_EXPIRE}
# 公司名
ENTERPRISE_NAME=${ENTERPRISE_NAME}
# admin用户的名字
ADMIN_USER=${ADMIN_USER}
# admin用户所属的组
ADMIN_USER_GROUP=${ADMIN_USER_GROUP}
# 申请证书所属部门
ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}
# 公司所属城市
STATE=${STATE}
EOF


cat << 'OUTER' >> ${APISERVER_INSTALLER_DIR}/install.sh
# ETCD的服务地址，例如http://192.168.1.1:2379  注意，请尽量使用域名
ETCD_SERVER=$4
echo "开始安装apiserver"
# service的env文件位置，后边脚本会自动生成该文件，生成Linux的service时需要引用该文件
APISERVER_ENV=${BASE_DIR}/config/apiserver.service.env
SERVICE_ACCOUNT_FILE=${BASE_DIR}/secure/serviceAccount.key
SERVICE_ACCOUNT_PRIVATE_FILE=${BASE_DIR}/secure/serviceAccount.key
# kubelet使用的ca证书
KUBELET_CA_FILE=${BASE_DIR}/secure/kubelet.ca.crt
ADMIN_CRT=${BASE_DIR}/secure/admin.crt
ADMIN_KEY=${BASE_DIR}/secure/admin.key
APISERVER_LOG_DIR=${BASE_DIR}/log
APISERVER_WORK_DIR=${BASE_DIR}
KUBE_COMMON_CONFIG=${BASE_DIR}/config/common.config
# apiserver的tls证书
TLS_CERT_FILE=${BASE_DIR}/secure/tls.crt
TLS_PRIVATE_KEY=${BASE_DIR}/secure/tls.key



# 生成一个证书
createCert ${BASE_DIR}/secure/apiserver.ca.key ${BASE_DIR}/secure/apiserver.ca.crt ${TLS_PRIVATE_KEY} ${TLS_CERT_FILE} ${BASE_DIR}/tmp
# 调用通用的创建配置方法，对于apiserver，ca要传kubelet的ca证书
createCommonConfig ${KUBE_COMMON_CONFIG} ${BASE_DIR}/secure/kubelet.ca.crt ${TLS_CERT_FILE} ${TLS_PRIVATE_KEY}



# apiserver配置
cat << EOF > ${APISERVER_ENV}
# 不允许特权容器
KUBE_ALLOW_PRIV=--allow-privileged=false
# apiserver监听地址
KUBE_API_ADDRESS=--bind-address=${LOCAL_IP}
# apiserver监听的HTTPS端口号
KUBE_API_SECURE_PORT=--secure-port=${APISERVER_SECURE_PORT}
# 准入控制器，详情参考：https://kubernetes.io/zh/docs/reference/access-authn-authz/admission-controllers/
KUBE_ADMISSION_CONTROL=--enable-admission-plugins=NamespaceLifecycle,NamespaceExists,LimitRanger,ServiceAccount,ResourceQuota
# 禁止匿名用户
KUBE_DISABLE_ANONYMOUS=--anonymous-auth=false
# apiserver的HTTPS端口鉴权规则
KUBE_AUTH=--authorization-mode=RBAC
# etcd的服务器地址
KUBE_ETCD_SERVERS=--etcd-servers=${ETCD_SERVER}
# k8s在etcd中的前缀
KUBE_ETCD_PREFIX=--etcd-prefix=${APISERVER_ETCD_PREFIX}
# nodePort可用的范围，设置所有端口可用
KUBE_SERVICE_NODE_PORT_RANGE=--service-node-port-range=1-65535


# 详细说明参考：https://kubernetes.io/zh/docs/tasks/configure-pod-container/configure-service-account/#service-account-token-volume-projection
SERVICE_ACCOUNT_ISSUER=--service-account-issuer=${APISERVER_DOMAIN}/auth/realms/master/.well-known/openid-configuration
# serviceAccount相关密钥
SERVICE_ACCOUNT_FILE=--service-account-key-file=${SERVICE_ACCOUNT_FILE}
SERVICE_ACCOUNT_PRIVATE_FILE=--service-account-signing-key-file=${SERVICE_ACCOUNT_PRIVATE_FILE}

# kubelet使用的CA，这里统一使用一个CA
KUBELET_CA_FILE=--kubelet-certificate-authority=${KUBELET_CA_FILE}
# 用于连接kubelet时做认证的证书，只要是CA签署的即可，这里全局使用同一个证书
KUBELET_CRT_FILE=--kubelet-client-certificate=${ADMIN_CRT}
# 连接kubelet时认证证书的key
KUBELET_KEY_FILE=--kubelet-client-key=${ADMIN_KEY}
LOG_DIR=--log-dir=${APISERVER_LOG_DIR}
# service ip范围，注意不要跟任何pod ip和主机ip冲突
VIP_RANGE=--service-cluster-ip-range=${VIP_RANGE}

# 聚合层相关参数
AGGREGATION=--requestheader-client-ca-file=${KUBELET_CA_FILE} --proxy-client-cert-file=${ADMIN_CRT} --proxy-client-key-file=${ADMIN_KEY} --requestheader-extra-headers-prefix=X-Remote-Extra- --requestheader-group-headers=X-Remote-Group --requestheader-username-headers=X-Remote-User
EOF


chmod +x ${BASE_DIR}/bin/kube-apiserver
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
ExecStart=${BASE_DIR}/bin/kube-apiserver \
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
OUTER


###################################################################################################################
##
## controller-manager安装文件生成
##
###################################################################################################################


echo "生成 controller-manager 安装文件到 ${CM_INSTALLER_DIR}"
cp ${NOW_DIR}/release/${K8S_VERSION}/kube-controller-manager ${CM_INSTALLER_DIR}/bin
cp ${K8S_SECURE_TEMP_DIR}/serviceAccount.key ${CM_INSTALLER_DIR}/secure/serviceAccount.key
cp ${K8S_SECURE_TEMP_DIR}/ca.crt ${CM_INSTALLER_DIR}/secure/apiserver.ca.crt
cp ${K8S_SECURE_TEMP_DIR}/ca.key ${CM_INSTALLER_DIR}/secure/apiserver.ca.key
cp ${K8S_SECURE_TEMP_DIR}/admin.crt ${CM_INSTALLER_DIR}/secure/admin.crt
cp ${K8S_SECURE_TEMP_DIR}/admin.key ${CM_INSTALLER_DIR}/secure/admin.key

CM_BASE_DIR=${TARGET_BASE_DIR}/kube-controller-manager


###############
# 开始生成安装脚本
##############
cp ${COMPONENT_INSTALL_HEADER} ${CM_INSTALLER_DIR}/install.sh

cat << EOF >> ${CM_INSTALLER_DIR}/install.sh
# 基础目录
BASE_DIR=${CM_BASE_DIR}
APISERVER_DOMAIN=${APISERVER_DOMAIN}
APISERVER_SECURE_PORT=${APISERVER_SECURE_PORT}

CONTROLLER_MANAGER_PORT=${CONTROLLER_MANAGER_PORT}

# 注意，下面几个参数在componentInstallHeader.sh中也有使用
# CA证书过期时间，默认100年
CA_CRT_EXPIRE=${CA_CRT_EXPIRE}
# 公司名
ENTERPRISE_NAME=${ENTERPRISE_NAME}
# admin用户的名字
ADMIN_USER=${ADMIN_USER}
# admin用户所属的组
ADMIN_USER_GROUP=${ADMIN_USER_GROUP}
# 申请证书所属部门
ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}
# 公司所属城市
STATE=${STATE}

EOF

cat << 'OUTER' >> ${CM_INSTALLER_DIR}/install.sh
createKubeConfig /usr/bin/kubectl "${APISERVER_DOMAIN}:${APISERVER_SECURE_PORT}" ${BASE_DIR}/config/kubeconfig.yaml ${BASE_DIR}/secure/apiserver.ca.crt ${BASE_DIR}/secure/admin.key ${BASE_DIR}/secure/admin.crt

CONTROLLER_MANAGER_ENV=${BASE_DIR}/config/controller-manager.service.env
SERVICE_ACCOUNT_PRIVATE_FILE=${BASE_DIR}/secure/serviceAccount.key
CONTROLLER_MANAGER_LOG_DIR=${BASE_DIR}/log
KUBECONFIG=${BASE_DIR}/config/kubeconfig.yaml
CA_FILE=${BASE_DIR}/secure/apiserver.ca.crt
KUBE_COMMON_CONFIG=${BASE_DIR}/config/common.config
TLS_CERT_FILE=${BASE_DIR}/secure/tls.crt
TLS_PRIVATE_KEY=${BASE_DIR}/secure/tls.key



echo "开始安装controller-manager"

# 生成证书
createCert ${BASE_DIR}/secure/apiserver.ca.key ${BASE_DIR}/secure/apiserver.ca.crt ${TLS_PRIVATE_KEY} ${TLS_CERT_FILE} ${BASE_DIR}/tmp
# 生成配置
createCommonConfig ${KUBE_COMMON_CONFIG} ${BASE_DIR}/secure/apiserver.ca.crt ${TLS_CERT_FILE} ${TLS_PRIVATE_KEY}


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
# 指定CA证书，将会包含在service account的secret中
ROOT_CA_FILE=--root-ca-file=${CA_FILE}
EOF



chmod +x ${BASE_DIR}/bin/kube-controller-manager
#controller-manager服务
cat << EOF > /usr/lib/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=${BASE_DIR}
EnvironmentFile=${KUBE_COMMON_CONFIG}
EnvironmentFile=${CONTROLLER_MANAGER_ENV}
ExecStart=${BASE_DIR}/bin/kube-controller-manager \
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

OUTER



###################################################################################################################
##
## kube-scheduler安装文件生成
##
###################################################################################################################



echo "生成 kube-scheduler 安装文件到 ${SCHEDULER_INSTALLER_DIR}"
cp ${NOW_DIR}/release/${K8S_VERSION}/kube-scheduler ${SCHEDULER_INSTALLER_DIR}/bin
cp ${K8S_SECURE_TEMP_DIR}/ca.crt ${SCHEDULER_INSTALLER_DIR}/secure/apiserver.ca.crt
cp ${K8S_SECURE_TEMP_DIR}/ca.key ${SCHEDULER_INSTALLER_DIR}/secure/apiserver.ca.key
cp ${K8S_SECURE_TEMP_DIR}/admin.crt ${SCHEDULER_INSTALLER_DIR}/secure/admin.crt
cp ${K8S_SECURE_TEMP_DIR}/admin.key ${SCHEDULER_INSTALLER_DIR}/secure/admin.key


SCHEDULER_BASE_DIR=${TARGET_BASE_DIR}/kube-scheduler


###############
# 开始生成安装脚本
##############
cp ${COMPONENT_INSTALL_HEADER} ${SCHEDULER_INSTALLER_DIR}/install.sh

cat << EOF >> ${SCHEDULER_INSTALLER_DIR}/install.sh
# 基础目录
BASE_DIR=${SCHEDULER_BASE_DIR}
APISERVER_DOMAIN=${APISERVER_DOMAIN}
APISERVER_SECURE_PORT=${APISERVER_SECURE_PORT}
SCHEDULER_PORT=${SCHEDULER_PORT}


# 注意，下面几个参数在componentInstallHeader.sh中也有使用
# CA证书过期时间，默认100年
CA_CRT_EXPIRE=${CA_CRT_EXPIRE}
# 公司名
ENTERPRISE_NAME=${ENTERPRISE_NAME}
# admin用户的名字
ADMIN_USER=${ADMIN_USER}
# admin用户所属的组
ADMIN_USER_GROUP=${ADMIN_USER_GROUP}
# 申请证书所属部门
ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}
# 公司所属城市
STATE=${STATE}

EOF

cat << 'OUTER' >> ${SCHEDULER_INSTALLER_DIR}/install.sh
createKubeConfig /usr/bin/kubectl "${APISERVER_DOMAIN}:${APISERVER_SECURE_PORT}" ${BASE_DIR}/config/kubeconfig.yaml ${BASE_DIR}/secure/apiserver.ca.crt ${BASE_DIR}/secure/admin.key ${BASE_DIR}/secure/admin.crt

SCHEDULER_LOG_DIR=${BASE_DIR}/log
SCHEDULER_ENV=${BASE_DIR}/config/scheduler.service.env
# 配置文件，参考：https://kubernetes.io/zh/docs/reference/scheduling/config/
SCHEDULER_CONFIG=${BASE_DIR}/config/scheduler.config
KUBECONFIG=${BASE_DIR}/config/kubeconfig.yaml
KUBE_COMMON_CONFIG=${BASE_DIR}/config/common.config
TLS_CERT_FILE=${BASE_DIR}/secure/tls.crt
TLS_PRIVATE_KEY=${BASE_DIR}/secure/tls.key


echo "开始安装kube-scheduler"

# 生成证书
createCert ${BASE_DIR}/secure/apiserver.ca.key ${BASE_DIR}/secure/apiserver.ca.crt ${TLS_PRIVATE_KEY} ${TLS_CERT_FILE} ${BASE_DIR}/tmp
# 生成配置
createCommonConfig ${KUBE_COMMON_CONFIG} ${BASE_DIR}/secure/apiserver.ca.crt ${TLS_CERT_FILE} ${TLS_PRIVATE_KEY}

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

chmod +x ${BASE_DIR}/bin/kube-scheduler
#scheduler服务
cat << EOF > /usr/lib/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler Plugin
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=${BASE_DIR}
EnvironmentFile=${KUBE_COMMON_CONFIG}
EnvironmentFile=${SCHEDULER_ENV}
ExecStart=${BASE_DIR}/bin/kube-scheduler \
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
OUTER



###################################################################################################################
##
## kubelet安装文件生成
##
###################################################################################################################



echo "生成 kubelet 安装文件到 ${KUBELET_INSTALLER_DIR}"
cp ${NOW_DIR}/release/${K8S_VERSION}/kubelet ${KUBELET_INSTALLER_DIR}/bin
cp ${K8S_SECURE_TEMP_DIR}/ca.crt ${KUBELET_INSTALLER_DIR}/secure/apiserver.ca.crt
cp ${K8S_SECURE_TEMP_DIR}/ca.key ${KUBELET_INSTALLER_DIR}/secure/apiserver.ca.key
cp ${K8S_SECURE_TEMP_DIR}/admin.crt ${KUBELET_INSTALLER_DIR}/secure/admin.crt
cp ${K8S_SECURE_TEMP_DIR}/admin.key ${KUBELET_INSTALLER_DIR}/secure/admin.key

KUBELET_BASE_DIR=${TARGET_BASE_DIR}/kubelet



###############
# 开始生成安装脚本
##############
cp ${COMPONENT_INSTALL_HEADER} ${KUBELET_INSTALLER_DIR}/install.sh

cat << EOF >> ${KUBELET_INSTALLER_DIR}/install.sh
# 基础目录
BASE_DIR=${KUBELET_BASE_DIR}
APISERVER_DOMAIN=${APISERVER_DOMAIN}
APISERVER_SECURE_PORT=${APISERVER_SECURE_PORT}

KUBELET_PORT=${KUBELET_PORT}
CGROUP=${CGROUP}
SYNC_FREQUENCY=${SYNC_FREQUENCY}
CLUSTER_DNS_IP=${CLUSTER_DNS_IP}
CLUSTER_DOMAIN=${CLUSTER_DOMAIN}
PAUSE_POD=${PAUSE_POD}

# 注意，下面几个参数在componentInstallHeader.sh中也有使用
# CA证书过期时间，默认100年
CA_CRT_EXPIRE=${CA_CRT_EXPIRE}
# 公司名
ENTERPRISE_NAME=${ENTERPRISE_NAME}
# admin用户的名字
ADMIN_USER=${ADMIN_USER}
# admin用户所属的组
ADMIN_USER_GROUP=${ADMIN_USER_GROUP}
# 申请证书所属部门
ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}
# 公司所属城市
STATE=${STATE}

EOF

cat << 'OUTER' >> ${KUBELET_INSTALLER_DIR}/install.sh
createKubeConfig /usr/bin/kubectl "${APISERVER_DOMAIN}:${APISERVER_SECURE_PORT}" ${BASE_DIR}/config/kubeconfig.yaml ${BASE_DIR}/secure/apiserver.ca.crt ${BASE_DIR}/secure/admin.key ${BASE_DIR}/secure/admin.crt

KUBELET_LOG_DIR=${BASE_DIR}/log
KUBELET_ENV=${BASE_DIR}/config/kubelet.service.env
KUBELET_CONFIG=${BASE_DIR}/config/kubelet.config
KUBECONFIG=${BASE_DIR}/config/kubeconfig.yaml
KUBE_COMMON_CONFIG=${BASE_DIR}/config/common.config
TLS_CERT_FILE=${BASE_DIR}/secure/tls.crt
TLS_PRIVATE_KEY=${BASE_DIR}/secure/tls.key

echo "开始安装kubelet"

# 生成证书
createCert ${BASE_DIR}/secure/apiserver.ca.key ${BASE_DIR}/secure/apiserver.ca.crt ${TLS_PRIVATE_KEY} ${TLS_CERT_FILE} ${BASE_DIR}/tmp
# 生成配置
createCommonConfig ${KUBE_COMMON_CONFIG} ${BASE_DIR}/secure/apiserver.ca.crt ${TLS_CERT_FILE} ${TLS_PRIVATE_KEY}

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
WORK_DIR=--root-dir=${BASE_DIR}
# 集群内的DNS地址
CLUSTER_DNS=--cluster-dns=${CLUSTER_DNS_IP}
# 集群的域名，DNS使用
CLUSTER_DOMAIN=--cluster-domain=${CLUSTER_DOMAIN}
# kubelet同步configmap的时间间隔，默认1m，时间越小kubelet资源消耗越高
SYNC_FREQUENCY=--sync-frequency=${SYNC_FREQUENCY}
EOF

chmod +x ${BASE_DIR}/bin/kubelet
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
WorkingDirectory=${BASE_DIR}
EnvironmentFile=${KUBE_COMMON_CONFIG}
EnvironmentFile=${KUBELET_ENV}
# kubelet要禁用swap
ExecStartPre=${SWAPOFF} -a
ExecStart=${BASE_DIR}/bin/kubelet \
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

OUTER



###################################################################################################################
##
## kube-proxy安装文件生成
##
###################################################################################################################


echo "生成 kube-proxy 安装文件到 ${PROXY_INSTALLER_DIR}"
cp ${NOW_DIR}/release/${K8S_VERSION}/kube-proxy ${PROXY_INSTALLER_DIR}/bin
cp ${K8S_SECURE_TEMP_DIR}/ca.crt ${PROXY_INSTALLER_DIR}/secure/apiserver.ca.crt
cp ${K8S_SECURE_TEMP_DIR}/admin.crt ${PROXY_INSTALLER_DIR}/secure/admin.crt
cp ${K8S_SECURE_TEMP_DIR}/admin.key ${PROXY_INSTALLER_DIR}/secure/admin.key


PROXY_BASE_DIR=${TARGET_BASE_DIR}/kube-proxy


###############
# 开始生成安装脚本
##############
cp ${COMPONENT_INSTALL_HEADER} ${PROXY_INSTALLER_DIR}/install.sh

cat << EOF >> ${PROXY_INSTALLER_DIR}/install.sh
# 基础目录
BASE_DIR=${PROXY_BASE_DIR}
APISERVER_DOMAIN=${APISERVER_DOMAIN}
APISERVER_SECURE_PORT=${APISERVER_SECURE_PORT}

KUBELET_PORT=${KUBELET_PORT}
CLUSTER_CIDR=${CLUSTER_CIDR}
APISERVER_SECURE_PORT=${APISERVER_SECURE_PORT}

EOF

cat << 'OUTER' >> ${PROXY_INSTALLER_DIR}/install.sh
createKubeConfig /usr/bin/kubectl "${APISERVER_DOMAIN}:${APISERVER_SECURE_PORT}" ${BASE_DIR}/config/kubeconfig.yaml ${BASE_DIR}/secure/apiserver.ca.crt ${BASE_DIR}/secure/admin.key ${BASE_DIR}/secure/admin.crt

KUBE_PROXY_LOG_DIR=${BASE_DIR}/log
KUBE_PROXY_ENV=${BASE_DIR}/config/kube-proxy.service.env
KUBELET_CONFIG=${BASE_DIR}/config/kube-proxy.config
KUBECONFIG=${BASE_DIR}/config/kubeconfig.yaml

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
NETWORK=--cluster-cidr=${CLUSTER_CIDR}
EOF

# kube-proxy依赖
yumInstall conntrack

chmod +x ${BASE_DIR}/bin/kube-proxy
#kube-proxy服务，注意，kube-proxy没有公共参数
cat << EOF > /usr/lib/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=${BASE_DIR}
EnvironmentFile=${KUBE_PROXY_ENV}
ExecStart=${BASE_DIR}/bin/kube-proxy \
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

OUTER




###################################################################################################################
##
## kubectl安装文件生成
##
###################################################################################################################


echo "生成 kubectl 安装文件到 ${KUBECTL_INSTALLER_DIR}"
cp ${NOW_DIR}/release/${K8S_VERSION}/kubectl ${KUBECTL_INSTALLER_DIR}/bin
cp ${K8S_SECURE_TEMP_DIR}/ca.crt ${KUBECTL_INSTALLER_DIR}/secure/apiserver.ca.crt
cp ${K8S_SECURE_TEMP_DIR}/admin.crt ${KUBECTL_INSTALLER_DIR}/secure/admin.crt
cp ${K8S_SECURE_TEMP_DIR}/admin.key ${KUBECTL_INSTALLER_DIR}/secure/admin.key


KUBECTL_BASE_DIR=${TARGET_BASE_DIR}/kubectl


###############
# 开始生成安装脚本
##############
cp ${COMPONENT_INSTALL_HEADER} ${KUBECTL_INSTALLER_DIR}/install.sh

cat << EOF >> ${KUBECTL_INSTALLER_DIR}/install.sh
# 基础目录
BASE_DIR=${KUBECTL_BASE_DIR}
APISERVER_DOMAIN=${APISERVER_DOMAIN}
APISERVER_SECURE_PORT=${APISERVER_SECURE_PORT}
EOF

cat << 'OUTER' >> ${KUBECTL_INSTALLER_DIR}/install.sh
KUBECONFIG=${BASE_DIR}/config/kubeconfig.yaml

echo "开始安装kubectl"

chmod +x ${BASE_DIR}/bin/kubectl
# 放入本地库
cp ${BASE_DIR}/bin/kubectl /usr/bin

createKubeConfig ${BASE_DIR}/bin/kubectl "${APISERVER_DOMAIN}:${APISERVER_SECURE_PORT}" ${BASE_DIR}/config/kubeconfig.yaml ${BASE_DIR}/secure/apiserver.ca.crt ${BASE_DIR}/secure/admin.key ${BASE_DIR}/secure/admin.crt

# 为当前用户创建kubectl的配置目录，并将配置放入进去，方便后续kubectl操作
mkdirIfAbsent ~/.kube
cp ${KUBECONFIG} ~/.kube/config

echo "kubectl安装完成"
OUTER


###################################################################################################################
##
## 插件安装文件生成，注意，请在K8S集群安装完毕后再安装插件
##
###################################################################################################################

# 创建目录
mkdirIfAbsent ${PLUGIN_INSTALLER_DIR}

cp ${NOW_DIR}/template/core-dns.yml ${PLUGIN_INSTALLER_DIR}
cp ${NOW_DIR}/template/ingress-traefik.yml ${PLUGIN_INSTALLER_DIR}
cp ${NOW_DIR}/template/metrics-server.yml ${PLUGIN_INSTALLER_DIR}
cp ${NOW_DIR}/template/kuboard.yml ${PLUGIN_INSTALLER_DIR}


cat << 'EOF' > install-plugins.sh
set -o nounset
set -e


# 如果指定目录不存在则创建
mkdirIfAbsent() {
	if [ ! -d $1 ]; then
	echo "目录[$1]不存在，创建..."
	mkdir -p $1
	fi
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


# etcd地址，例如192.168.1.6:2379
ETCD_SERVER=$1
# kuboard的域名，例如kuboard.kube.com（用于配置ingress规则）
KUBOARD_HOST=$2

EOF


cat << EOF >> install-plugins.sh

###################################################################################################################
##
## core-dns 安装
##
###################################################################################################################


# K8S的service ip的范围，例如194.10.0.0/16
sed -i "s/\${VIP_CIDR}/${VIP_RANGE}/g" ${NOW_DIR}/core-dns.yml
# pod的ip范围，例如193.0.0.0/8
sed -i "s/\${POD_CIDR}/${CLUSTER_CIDR}/g" ${NOW_DIR}/core-dns.yml
# K8S集群的域名后缀，注意，这个域名只会使用K8S解析，不会转发到其他地方；
sed -i "s/\${CLUSTER_DOMAIN}/${CLUSTER_DOMAIN}/g" ${NOW_DIR}/core-dns.yml
# 响应给dns查询客户端的ttl
sed -i "s/\${DNS_TTL}/30/g" ${NOW_DIR}/core-dns.yml
# Prometheus的端口号
sed -i "s/\${PROMETHEUS_PORT}/9153/g" ${NOW_DIR}/core-dns.yml
# 域名服务器（也可以是文件，例如/etc/resolv.conf），对于coredns无法解析的域名转发到该服务器解析；
sed -i "s/\${UPSTREAMNAMESERVER}/${UPSTREAMNAMESERVER}/g" ${NOW_DIR}/core-dns.yml
# dns在集群中的service ip
sed -i "s/\${CLUSTER_DNS_IP}/${CLUSTER_DNS_IP}/g" ${NOW_DIR}/core-dns.yml

kubectl apply -f ${NOW_DIR}/core-dns.yml



###################################################################################################################
##
## ingress-traefik 安装
##
###################################################################################################################

kubectl apply -f ${NOW_DIR}/ingress-traefik.yml

###################################################################################################################
##
## metrics-server 安装
##
###################################################################################################################

kubectl apply -f ${NOW_DIR}/metrics-server.yml


EOF

cat << 'EOF' >> install-plugins.sh
###################################################################################################################
##
## kuboard 安装，依赖 traefik-server
##
###################################################################################################################

sed -i "s/\${etcdAddr}/${ETCD_SERVER}/g" ${NOW_DIR}/kuboard.yml
sed -i "s/\${kuboardHost}/${KUBOARD_HOST}/g" ${NOW_DIR}/kuboard.yml

kubectl apply -f ${NOW_DIR}/kuboard.yml

EOF
