set -o nounset
set -e


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
## 生成服务端、客户端安装脚本，需要传一个参数：ca证书密码
##
## 使用说明：请修改MASTER的节点信息和SLAVE的节点信息，执行的时候传入CA证书密码，然后本脚本会自动在MASTER节点和SLAVE
## 节点部署相关服务，同时使用设定的节点IP作为通讯IP；
##
###################################################################################################################

# ca证书密码
CA_CERT_PASSWORD=$1


# 主节点的ip、ssh端口号、用户名、密码
MASTER_IP=
MASTER_SSH_PORT=22
MASTER_SSH_USER=root
MASTER_SSH_PASSWD=
# 目标机器存放安装文件的目录
K8S_INSTALLER_DIR=/data/k8s-installer


# 为了方便，所有的kube节点都要有相同的ssh端口号、用户名、密码，多个IP间使用空格分隔
SLAVE_IPS=()
SLAVE_SSH_PORT=22
SLAVE_SSH_USER=root
SLAVE_SSH_PASSWD=

# dns的upstream，可以是文件，也可以是其他的DNS服务器
UPSTREAMNAMESERVER=/etc/resolv.conf


# docker的私服仓库
DOCKER_REGISTRY_MIRRORS="\\\"https://uyah70su.mirror.aliyuncs.com\\\""
# docker的非安全仓库（如果自建仓库不是使用SSL连接的需要配置，docker默认使用安全的SSL仓库，使用这个可以指定使用非SSL连接的仓库）
DOCKER_INSECURE_REGISTRIES="\\\"harbor.niceloo.com:88\\\",\\\"nexus.niceloo.com:8083\\\", \\\"nexus-prod.niceloo.com:8083\\\""



###################################################################################################################
##
## 常量定义
##
###################################################################################################################

# 注意，下面几个参数在componentInstallHeader.sh中也有使用，使用export导出方便调用compiler.sh的时候compiler.sh脚本使用
# CA证书过期时间，默认100年
export CA_CRT_EXPIRE=36500
# 公司名
export ENTERPRISE_NAME=JoeKerouac
# admin用户的名字
export ADMIN_USER=admin
# admin用户所属的组
export ADMIN_USER_GROUP=system:masters
# 申请证书所属部门
export ORGANIZATIONAL_UNIT=dev
# 公司所属城市
export STATE=北京



# etcd监听端口号
ETCDPORT=2379
# K8S安装目标路径
INSTALL_TARGET_DIR=/data/k8s


# 编译目标目录
COMPILE_TARGET_DIR=${NOW_DIR}/target/installer
APISERVER_COMPILE_TARGET_DIR=${COMPILE_TARGET_DIR}/kube-apiserver
CM_COMPILE_TARGET_DIR=${COMPILE_TARGET_DIR}/kube-controller-manager
SCHEDULER_COMPILE_TARGET_DIR=${COMPILE_TARGET_DIR}/kube-scheduler
PROXY_COMPILE_TARGET_DIR=${COMPILE_TARGET_DIR}/kube-proxy
KUBELET_COMPILE_TARGET_DIR=${COMPILE_TARGET_DIR}/kubelet
KUBECTL_COMPILE_TARGET_DIR=${COMPILE_TARGET_DIR}/kubectl


###################################################################################################################
##
## 通用函数定义
##
###################################################################################################################


# 如果指定目录不存在则创建
mkdirIfAbsent() {
	if [ ! -d $1 ]; then
	echo "目录[$1]不存在，创建..."
	mkdir -p $1
	fi
}


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
## 编译，生成安装包
##
###################################################################################################################

sh compiler.sh ${CA_CERT_PASSWORD} ${UPSTREAMNAMESERVER}


###################################################################################################################
##
## 将安装包上传到远程服务器并安装
##
###################################################################################################################


echo "nohup sh ${K8S_INSTALLER_DIR}/serverInstall.sh ${MASTER_IP} ${MASTER_IP} ${CA_CERT_PASSWORD} ${INSTALL_TARGET_DIR} ${ETCDPORT} > ${K8S_INSTALLER_DIR}/serverInstall.log 2>&1 &" > ${COMPILE_TARGET_DIR}/serverDeploy.sh

echo "在机器${MASTER_IP}上安装K8S server"
# 将target/installer/server目录递归复制到远程，注意要先创建目录
execRemote ${MASTER_SSH_PORT} ${MASTER_SSH_USER} ${MASTER_IP} ${MASTER_SSH_PASSWD} "mkdir -p ${K8S_INSTALLER_DIR}"
echo "将二进制文件分发到 ${MASTER_IP}"
# 注意，源目录后边加了斜杠和点，表示只把目录中的内容copy过去，不copy目录本身，不加表示将目录也copy过去
execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${APISERVER_COMPILE_TARGET_DIR} ${MASTER_SSH_USER}@${MASTER_IP}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${CM_COMPILE_TARGET_DIR} ${MASTER_SSH_USER}@${MASTER_IP}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${SCHEDULER_COMPILE_TARGET_DIR} ${MASTER_SSH_USER}@${MASTER_IP}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${PROXY_COMPILE_TARGET_DIR} ${MASTER_SSH_USER}@${MASTER_IP}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${KUBECTL_COMPILE_TARGET_DIR} ${MASTER_SSH_USER}@${MASTER_IP}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
execSSHWithoutPasswd "scp -P ${MASTER_SSH_PORT} ${NOW_DIR}/shell/serverInstall.sh ${MASTER_SSH_USER}@${MASTER_IP}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
execSSHWithoutPasswd "scp -P ${MASTER_SSH_PORT} ${COMPILE_TARGET_DIR}/serverDeploy.sh ${MASTER_SSH_USER}@${MASTER_IP}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
echo "二进制文件分发完毕"

# 远程执行安装server
execRemote ${MASTER_SSH_PORT} ${MASTER_SSH_USER} ${MASTER_IP} ${MASTER_SSH_PASSWD} "sh ${K8S_INSTALLER_DIR}/serverDeploy.sh"
echo "在机器${MASTER_IP}上安装K8S server任务已经分发完毕，请登录机器查看安装状态"


cat << EOF > ${COMPILE_TARGET_DIR}/clientDeploy.sh
LOCAL_IP=\$1
nohup sh ${K8S_INSTALLER_DIR}/clientInstall.sh \${LOCAL_IP} ${MASTER_IP} ${CA_CERT_PASSWORD} ${INSTALL_TARGET_DIR} ${ETCDPORT} ${MASTER_IP} "${DOCKER_REGISTRY_MIRRORS}" "${DOCKER_INSECURE_REGISTRIES}" > ${K8S_INSTALLER_DIR}/clientInstall.log &
EOF

echo "准备安装K8S client集群"
for ((i=0; i < ${#SLAVE_IPS[*]}; i++))
do
    echo -e "\t将K8S client安装任务分发到机器${SLAVE_IPS[${i}]}上"
    # 执行远程安装，注意要先创建目录，后边执行的时候会用
    execRemote ${MASTER_SSH_PORT} ${MASTER_SSH_USER} ${SLAVE_IPS[${i}]} ${MASTER_SSH_PASSWD} "mkdir -p ${K8S_INSTALLER_DIR}"
    echo "将二进制文件分发到 ${SLAVE_IPS[${i}]}"
    # 注意，源目录后边加了斜杠和点，表示只把目录中的内容copy过去，不copy目录本身，不加表示将目录也copy过去
    execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${KUBELET_COMPILE_TARGET_DIR} ${MASTER_SSH_USER}@${SLAVE_IPS[${i}]}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
    execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${PROXY_COMPILE_TARGET_DIR} ${MASTER_SSH_USER}@${SLAVE_IPS[${i}]}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
    execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${KUBECTL_COMPILE_TARGET_DIR} ${MASTER_SSH_USER}@${SLAVE_IPS[${i}]}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
    execSSHWithoutPasswd "scp -P ${MASTER_SSH_PORT} ${NOW_DIR}/shell/clientInstall.sh ${MASTER_SSH_USER}@${SLAVE_IPS[${i}]}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
    execSSHWithoutPasswd "scp -P ${MASTER_SSH_PORT} ${COMPILE_TARGET_DIR}/clientDeploy.sh ${MASTER_SSH_USER}@${SLAVE_IPS[${i}]}:${K8S_INSTALLER_DIR}" ${MASTER_SSH_PASSWD}
    echo "二进制文件分发完毕"

    execRemote ${SLAVE_SSH_PORT} ${SLAVE_SSH_USER} ${SLAVE_IPS[${i}]} ${SLAVE_SSH_PASSWD} "sh ${K8S_INSTALLER_DIR}/clientDeploy.sh ${SLAVE_IPS[${i}]} "
    echo -e "\t----------------------------------------"
done
echo "K8S client集群安装任务下发完毕，请登录机器查看安装状态"


