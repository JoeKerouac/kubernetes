set -o nounset
set -e

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
# 存放安装文件的目录
MASTER_INSTALL_BIN_DIR=/data/installer/server


# 为了方便，所有的kube节点都要有相同的ssh端口号、用户名、密码
SLAVE_IPS=()
SLAVE_SSH_PORT=22
SLAVE_SSH_USER=root
SLAVE_SSH_PASSWD=
# 存放安装文件的目录
SLAVE_INSTALL_BIN_DIR=/data/installer/client


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



# CA证书过期时间，默认100年
CA_CRT_EXPIRE=36500
# 公司名
ENTERPRISE_NAME="JoeKerouac"
# admin用户的名字
ADMIN_USER=admin
# admin用户所属的组
ADMIN_USER_GROUP=system:masters



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



# 安装文件目标目录创建
TARGET_DIR=${NOW_DIR}/target
# 先清空目录
rm -rf ${TARGET_DIR}
mkdirIfAbsent ${TARGET_DIR}

INSTALLER_DIR=${TARGET_DIR}/installer
# 通用脚本部分
mkdirIfAbsent ${INSTALLER_DIR}

# 客户端安装文件目录
SERVER_INSTALLER_DIR=${INSTALLER_DIR}/server
mkdirIfAbsent ${SERVER_INSTALLER_DIR}

# 服务端安装文件目录
CLIENT_INSTALLER_DIR=${INSTALLER_DIR}/client
mkdirIfAbsent ${CLIENT_INSTALLER_DIR}


# 安全文件生成目录
K8S_SECURE_TEMP_DIR=${TARGET_DIR}/secure
# 创建这个目录
mkdirIfAbsent ${K8S_SECURE_TEMP_DIR}


echo "准备生成相关证书（CA证书、admin用户证书）"

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
# 生成admin用户的证书
openssl x509 -req -in ${K8S_SECURE_TEMP_DIR}/admin.csr -CA ${K8S_SECURE_TEMP_DIR}/ca.crt -CAkey ${K8S_SECURE_TEMP_DIR}/ca.key -passin pass:${CA_CERT_PASSWORD} -CAcreateserial -out ${K8S_SECURE_TEMP_DIR}/admin.crt -days ${CA_CRT_EXPIRE} -extensions v3_ext >/dev/null  2>&1
echo "使用ca证书签名的admin用户证书生成完毕"

openssl genrsa -out ${K8S_SECURE_TEMP_DIR}/serviceAccount.key >/dev/null 2>&1



# 移动证书文件到客户端、服务器的安装目录
mkdirIfAbsent ${SERVER_INSTALLER_DIR}/secure
mkdirIfAbsent ${CLIENT_INSTALLER_DIR}/secure
for KEY in ca.crt ca.key admin.crt admin.key serviceAccount.key
do
	cp ${K8S_SECURE_TEMP_DIR}/${KEY} ${SERVER_INSTALLER_DIR}/secure/
	cp ${K8S_SECURE_TEMP_DIR}/${KEY} ${CLIENT_INSTALLER_DIR}/secure/
done
echo "相关证书生成完毕，当前证书存放在：${K8S_SECURE_TEMP_DIR}"


###################################################################################################################
##
## 服务端安装、卸载文件生成
##
###################################################################################################################
echo "准备生成服务端安装文件"

# 创建服务端安装bin目录，后续安装文件都放在这里
mkdirIfAbsent ${SERVER_INSTALLER_DIR}/bin
# 将二进制文件移动到指定目录
for LIB in kube-apiserver kube-controller-manager kube-scheduler kubectl kube-proxy
do
	cp ${NOW_DIR}/release/v1.20.0/${LIB} ${SERVER_INSTALLER_DIR}/bin
done


# 生成安装脚本
cat << EOF >> ${SERVER_INSTALLER_DIR}/install.sh
TYPE=server
INSTALL=install
EOF
cat core.sh >> ${SERVER_INSTALLER_DIR}/install.sh


# 生成卸载脚本
cat << EOF >> ${SERVER_INSTALLER_DIR}/uninstall.sh
TYPE=server
INSTALL=uninstall
EOF
cat core.sh >> ${SERVER_INSTALLER_DIR}/uninstall.sh

# 将K8S服务安装模板copy到安装路径
cp template/* ${SERVER_INSTALLER_DIR}/

echo "服务器安装文件生成完毕，位置：${SERVER_INSTALLER_DIR}"



###################################################################################################################
##
## 客户端安装、卸载文件生成
##
###################################################################################################################
echo "准备生成客户端安装文件"

# 创建目录，后续安装文件都放在这里
mkdirIfAbsent ${CLIENT_INSTALLER_DIR}/bin


# 将二进制文件移动到指定目录
for LIB in kubectl kube-proxy kubelet
do
	cp ${NOW_DIR}/release/v1.20.0/${LIB} ${CLIENT_INSTALLER_DIR}/bin
done


# 生成安装脚本
cat << EOF >> ${CLIENT_INSTALLER_DIR}/install.sh
TYPE=client
INSTALL=install
EOF
cat core.sh >> ${CLIENT_INSTALLER_DIR}/install.sh



# 生成卸载脚本
cat << EOF >> ${CLIENT_INSTALLER_DIR}/uninstall.sh
TYPE=client
INSTALL=uninstall
EOF
cat core.sh >> ${CLIENT_INSTALLER_DIR}/uninstall.sh


echo "客户端安装文件生成完毕，位置：${CLIENT_INSTALLER_DIR}"


###################################################################################################################
##
## 将安装包上传到远程服务器并安装
##
###################################################################################################################


echo "在机器${MASTER_IP}上安装K8S server"
# 将target/installer/server目录递归复制到远程，注意要先创建目录
execRemote ${MASTER_SSH_PORT} ${MASTER_SSH_USER} ${MASTER_IP} ${MASTER_SSH_PASSWD} "mkdir -p ${MASTER_INSTALL_BIN_DIR}"
# 注意，源目录后边加了斜杠和点，表示只把目录中的内容copy过去，不copy目录本身
execSSHWithoutPasswd "scp -r -P ${MASTER_SSH_PORT} ${SERVER_INSTALLER_DIR}/. ${MASTER_SSH_USER}@${MASTER_IP}:${MASTER_INSTALL_BIN_DIR}" ${MASTER_SSH_PASSWD}
# 远程执行安装server
execRemote ${MASTER_SSH_PORT} ${MASTER_SSH_USER} ${MASTER_IP} ${MASTER_SSH_PASSWD} "nohup sh ${MASTER_INSTALL_BIN_DIR}/install.sh ${MASTER_IP} ${MASTER_IP} ${CA_CERT_PASSWORD} > ${MASTER_INSTALL_BIN_DIR}/install.log &"
echo "在机器${MASTER_IP}上安装K8S server任务已经分发完毕，请登录机器查看安装状态"



echo "准备安装K8S client集群"
for ((i=0; i < ${#SLAVE_IPS[*]}; i++))
do
    echo -e "\t将K8S client安装任务分发到机器${SLAVE_IPS[${i}]}上"
    # 执行远程安装，注意要先创建目录，后边执行的时候会用
    execRemote ${SLAVE_SSH_PORT} ${SLAVE_SSH_USER} ${SLAVE_IPS[${i}]} ${SLAVE_SSH_PASSWD} "mkdir -p ${SLAVE_INSTALL_BIN_DIR}"  "\t"
    execSSHWithoutPasswd "scp -r -P ${SLAVE_SSH_PORT} ${CLIENT_INSTALLER_DIR}/. ${SLAVE_SSH_USER}@${SLAVE_IPS[${i}]}:${SLAVE_INSTALL_BIN_DIR}" ${SLAVE_SSH_PASSWD}
    execRemote ${SLAVE_SSH_PORT} ${SLAVE_SSH_USER} ${SLAVE_IPS[${i}]} ${SLAVE_SSH_PASSWD} "nohup sh ${SLAVE_INSTALL_BIN_DIR}/install.sh ${SLAVE_IPS[${i}]} ${MASTER_IP} ${CA_CERT_PASSWORD} > ${SLAVE_INSTALL_BIN_DIR}/install.log &"  "\t"
    echo -e "\t----------------------------------------"
done
echo "K8S client集群安装任务下发完毕，请登录机器查看安装状态"


