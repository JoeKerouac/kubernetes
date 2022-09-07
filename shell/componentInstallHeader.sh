set -o nounset
set -e

###################################################################################################################
##
## K8S组件安装shell脚本通用header，定义了三个入参：本地IP（集群间通讯使用）、apiserver的IP（或者域名）、CA证书密码
##
###################################################################################################################

# 本地IP
LOCAL_IP=$1
# apiserver的域名，如果有自己的DNS或者申请的有域名，这里可以挂域名而不是IP，这样做集群时就无需修改了
# 注意，这个需要是带协议和端口号的，例如https://apiserver.com:6443
APISERVER_DOMAIN=$2
# 证书密码
CA_CERT_PASSWORD=$3


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
## 通用函数
##
###################################################################################################################


# 创建证书，需要多个参数：1、CA证书key的位置；2、CA证书的位置；3、CA证书key的密码；4、生成的证书key的位置；5、生成的证书的位置；
createCert() {
# CA证书的key的位置
ADMIN_KEY_FILE=$1
# CA证书位置
CA_FILE=$2

# 生成TLS_PRIVATE_KEY的位置
TLS_PRIVATE_KEY=$3
# 生成的TLS证书的位置
TLS_CERT_FILE=$4
# 文件生成的位置，一些临时文件会生成到临时目录中
GENERATE_CERT_DIR=$5
# apiserver专用，例如IP.1 = 194.10.0.1
ALT_NAME=$6
mkdirIfAbsent ${GENERATE_CERT_DIR}

# CA证书的密码
CA_CERT_PASSWORD=${CA_CERT_PASSWORD}


# 本地IP
LOCAL_IP=${LOCAL_IP}
# 公司所属城市
STATE=${STATE}
# 公司名
ENTERPRISE_NAME=${ENTERPRISE_NAME}
# 申请证书所属部门
ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}
# admin用户名
ADMIN_USER=${ADMIN_USER}
# 证书过期时间，单位天，默认100年
CRT_EXPIRE=${CA_CRT_EXPIRE}

echo "开始生成证书"
# 写入证书配置，注意， LOCAL_IP需要是使用证书的服务器的集群IP
# 注意，keyUsage中必须要包含digitalSignature，否则K8S的Java客户端会报错
cat << EOF > ${GENERATE_CERT_DIR}/common.csr.conf
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
${ALT_NAME}

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
openssl req -new -key ${TLS_PRIVATE_KEY} -out ${GENERATE_CERT_DIR}/tls.csr -config ${GENERATE_CERT_DIR}/common.csr.conf >/dev/null 2>&1
# 生成服务器证书
openssl x509 -req -in ${GENERATE_CERT_DIR}/tls.csr -CA ${CA_FILE} -CAkey ${ADMIN_KEY_FILE} -passin pass:${CA_CERT_PASSWORD} -CAcreateserial -out ${TLS_CERT_FILE} -days ${CRT_EXPIRE} -extensions v3_ext -extfile ${GENERATE_CERT_DIR}/common.csr.conf >/dev/null 2>&1
echo "证书生成完毕"
}


# 创建K8S相关service通用的选项开始
createCommonConfig() {
CONFIG_PATH=$1
# 要连接的服务器的CA，对于apiserver来说是kubelet的ca，对于其他组件来说都是apiserver的ca
CA_FILE=$2
TLS_CERT_FILE=$3
TLS_PRIVATE_KEY=$4
# 通用选项
cat << EOF > ${CONFIG_PATH}
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

# 创建kubeconfig.yaml配置文件
createKubeConfig() {
# kubectl命令的位置
KUBECTL=$1
# apiserver的全路径，例如https://apiserver.com:6443
APISERVER_URL=$2
# 生成的配置文件位置
KUBECONFIG=$3
# 服务端的CA
CA_FILE=$4
# admin用户的key
ADMIN_KEY_FILE=$5
# admin用户的证书位置
ADMIN_CRT_FILE=$6

chmod +x ${KUBECTL}
# 使用kubectl配置一个kubeconfig文件
# kubectl命令说明详见：https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#config
# 设置默认集群，指定apiserver地址、ca证书；
${KUBECTL} config set-cluster default-cluster --kubeconfig=${KUBECONFIG} --server=${APISERVER_URL} --certificate-authority=${CA_FILE} >/dev/null 2>&1
# 指定客户端证书，注意，命令行指定的admin是在kubeconfig中的用户名，该用户关联的证书对应的用户名不一定是admin，这个admin主要为了方便后边引用这个用户配置；
${KUBECTL} config set-credentials admin --kubeconfig=${KUBECONFIG} --certificate-authority=${CA_FILE} --client-key=${ADMIN_KEY_FILE} --client-certificate=${ADMIN_CRT_FILE} >/dev/null 2>&1
# 设置一个环境，指定该环境使用默认集群、admin用户
${KUBECTL} config set-context default-system --kubeconfig=${KUBECONFIG} --cluster=default-cluster --user=admin >/dev/null 2>&1
# 设置当前使用的上下文为上边配置的default-system
${KUBECTL} config use-context default-system --kubeconfig=${KUBECONFIG} >/dev/null 2>&1
}


