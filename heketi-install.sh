set -o nounset
set -e

###################################################################################################################
##
## heketi安装，这里默认使用ssh模式（三种模式，mock、ssh、kubernetes，详细见官方说明）
## 官方配置详细说明：https://github.com/heketi/heketi/blob/e6b8c449d7551ae5d0abaad518e9ce24b2ea2554/docs/admin/server.md
## 
## 注意，heketi不支持自定义日志目录，默认输出在了systemd的日志输出中，查看日志使用journalctl -u heketi命令查看
## heketi的挂载目录/var/lib/heketi/mounts也不能修改，不过这个无所谓，卸载的时候只需要umount就行了
## 
## 本脚本说明：所有glusterfs集群的机器都应该具有同样的ssh用户名、ssh密码、ssh端口号；最终生成的heketi会认为所有gluster
## 节点都是同一个集群、同一个容灾区的，不会对这个划分；
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


###################################################################################################################
##
## 配置
##
###################################################################################################################


# glusterfs集群服务器
GLUSTERFS_IP_ADDS=(192.168.56.114 192.168.56.115)
# glusterfs集群中可用的磁盘，与GLUSTERFS_IP_ADDS对应，必须是没有任何文件系统的（用之前可以用wipefs清理下），注意，后续会强制执行wipefs清除一下文件系统
# 如果某个ip对应的有多个设备，例如/dev/sdb和/dev/sdc，那么这个应该用双引号包围并且使用空格分开，如："/dev/sdb /dev/sdc"
GLUSTERFS_DEV=("/dev/sdb" "/dev/sdb")
# glusterfs集群机器的账号，所有的glusterfs机器应该具有一样的账号密码，如果不是root，该用户必须有无需输入密码执行sudo的权限，同时该用户需要和上边的私钥对应的用户一致；
GLUSTERFS_SSH_USER=root
# heketi ssh登录glusterfs时指定的glusterfs服务器的端口号，如果glusterfs服务器的ssh端口号不是22请修改，并且保证glusterfs集群的ssh端口号一致；
GLUSTERFS_SSH_PORT=22
# glusterfs集群机器的密码，所有glusterfs机器应该具有同样的密码
GLUSTERFS_SSH_PASSWD=123

# heketi安装ip
HEKETI_IP=192.168.56.114
# heketi安装机器ssh用户名
HEKETI_SSH_USER=root
# heketi安装机器ssh端口号
HEKETI_SSH_PORT=22
# heketi安装机器ssh密码
HEKETI_SSH_PASSWD=123


# 是否开启heketi的鉴权
HEKETI_USE_AUTH=true
# 如果开启了heketi鉴权，那么这个TOKEN就是后续访问heketi的时候admin用户用的，admin用户可以访问所有API；
HEKETI_ADMIN_TOKEN=123456
# 如果开启了heketi鉴权，那么这个TOKEN就是后续访问heketi的时候user用户用的，user用户只能访问卷创建删除等API；
HEKETI_USER_TOKEN=123456


# heketi监听端口号
HEKETI_PORT=8080
# heketi的工作目录
HEKETI_WORK_DIR=/data/k8s/heketi
# heketi的私钥，用来ssh登录glusterfs服务器用的，owner和group要是heketi；
HEKETI_KEY_FILE=${HEKETI_WORK_DIR}/heketi_key
# fstab文件，一般不用改
FSTAB=/etc/fstab
# heketi的db文件
HEKETI_DB=${HEKETI_WORK_DIR}/heketi.db
# heketi的配置文件
HEKETI_JSON=${HEKETI_WORK_DIR}/heketi.json
# glusterfs集群定义
HEKETI_TOPOLOGY_JSON=${HEKETI_WORK_DIR}/topology.json
# heketi的日志级别，分为none, critical, error, warning, info, debug
HEKETI_LOG_LEVEL=warning



# 工作目录
GLUSTERD_WORK_DIR=/data/k8s/gluster
# 日志存储目录
GLUSTERD_LOG_DIR=${GLUSTERD_WORK_DIR}/log
# 日志级别：DEBUG, INFO,WARNING, ERROR, CRITICAL, TRACE and NONE 
GLUSTERD_LOG_LEVEL=WARNING



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
set time 30

spawn $1
expect {
"*yes/no" { send "yes\r"; exp_continue }
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


# 如果指定目录不存在则创建
mkdirIfAbsent() {
	if [ ! -d $1 ]; then
	echo "目录[$1]不存在，创建..."
	mkdir -p $1
	fi
}


###################################################################################################################
##
## heketi安装相关函数
##
###################################################################################################################

# 将用户指定的远程磁盘全部使用wipefs清除
function wipefsRemote() {
# 将ssh key分发到集群服务器，过程中将会让我们输入密码，分发这个主要是为了让heketi免密登录glusterfs集群的机器
for ((i=0; i < ${#GLUSTERFS_IP_ADDS[*]}; i++))
do
    # 执行ssh-copy-id将公钥分发到各个机器上
    echo "清除机器${GLUSTERFS_IP_ADDS[${i}]}上${GLUSTERFS_DEV[${i}]}磁盘的文件系统"
    execRemote ${GLUSTERFS_SSH_PORT} ${GLUSTERFS_SSH_USER} ${GLUSTERFS_IP_ADDS[${i}]} ${GLUSTERFS_SSH_PASSWD} "wipefs -a -f ${GLUSTERFS_DEV[${i}]}"
done
}

# 生成heketi.json文件
function generateHeketiJson(){
echo "生成heketi.json文件"
cat << EOF > ${HEKETI_JSON}
{
  "port": "${HEKETI_PORT}",
  "use_auth": ${HEKETI_USE_AUTH},
  "jwt": {
    "admin": {
      "key": "${HEKETI_ADMIN_TOKEN}"
    },
    "user": {
      "key": "${HEKETI_USER_TOKEN}"
    }
  },

  "_glusterfs_comment": "GlusterFS Configuration",
  "glusterfs": {
    "executor": "ssh",
    "sshexec": {
      "keyfile": "${HEKETI_KEY_FILE}",
      "user": "${GLUSTERFS_SSH_USER}",
      "port": "${GLUSTERFS_SSH_PORT}",
      "fstab": "${FSTAB}"
    },
    "db": "${HEKETI_DB}",
    "loglevel" : "${HEKETI_LOG_LEVEL}"
  }
}
EOF
}
# heketi.json文件生成完毕


# 生成topology.json
function generateTopologyJson() {
# 先写入开头
cat << EOF > ${HEKETI_TOPOLOGY_JSON}
{
  "clusters": [
    {
      "nodes": [
EOF

# 然后写入节点
for ((i=0; i < ${#GLUSTERFS_IP_ADDS[*]}; i++))
do

# 将GLUSTERFS_DEV数组按照json格式的字符串拼接
DEVS=(${GLUSTERFS_DEV[${i}]})
DEVICES="\"${DEVS[0]}\""

# 如果数组长度大于1，从第二个开始拼接，主要是为了不多拼接逗号
if [ 1 -lt ${#DEVS[*]} ] ;then
    for ((j=1; j < ${#DEVS[*]}; j++))
    do
        DEVICES=${DEVICES},"\"${DEVS[${j}]}\""
    done
fi




cat << EOF >> ${HEKETI_TOPOLOGY_JSON}
        {"node": {
            "hostnames": {
              "manage": [
                "${GLUSTERFS_IP_ADDS[${i}]}"
              ],
              "storage": [
                "${GLUSTERFS_IP_ADDS[${i}]}"
              ]
            },
            "zone": 1
          },
          "devices": [
            ${DEVICES}
          ]
EOF

# 最后一个元素不能输出逗号了
if [ ${#GLUSTERFS_IP_ADDS[*]} -gt $((${i}+1)) ];then
  echo "        }," >> ${HEKETI_TOPOLOGY_JSON}
else
  echo "        }" >> ${HEKETI_TOPOLOGY_JSON}
fi
done

# 最后写入结尾
cat << EOF >> ${HEKETI_TOPOLOGY_JSON}
      ]
    }
  ]
}
EOF
}
# topology.json文件生成完毕

# 生成并分发SSH key，用于后续heketi对glusterfs集群机器的访问
function generateSSHKey() {
# 生成heketi的sshkey，heketi配置需要
ssh-keygen -f ${HEKETI_KEY_FILE} -t rsa -N ''
# 将密钥权限修改为heketi所有
chown heketi:heketi ${HEKETI_KEY_FILE}*

# 将ssh key分发到集群服务器，过程中将会让我们输入密码，分发这个主要是为了让heketi免密登录glusterfs集群的机器
for ((i=0; i < ${#GLUSTERFS_IP_ADDS[*]}; i++))
do
    # 执行ssh-copy-id将公钥分发到各个机器上
    echo "将SSH KEY分发到${GLUSTERFS_IP_ADDS[${i}]}上"
    execSSHWithoutPasswd "ssh-copy-id -p ${GLUSTERFS_SSH_PORT} -i ${HEKETI_KEY_FILE}.pub ${GLUSTERFS_SSH_USER}@${GLUSTERFS_IP_ADDS[${i}]}" ${GLUSTERFS_SSH_PASSWD}
done
}
# SSH KEY生成并分发完毕

# 安装heketi
function installHeketi() {
echo "开始安装heketi"
mkdirIfAbsent ${HEKETI_WORK_DIR}

# 先安装glusterfs源，glusterfs源中包含heketi的安装包，然后按爪给你heketi、heketi-client
echo "安装centos-release-gluster"
yum install -q -y centos-release-gluster
yum install -q -y heketi heketi-client
echo "heketi安装完成，准备配置heketi"


# 写入service（已经有了，这个会覆盖）
cat << EOF > /usr/lib/systemd/system/heketi.service
Description=Heketi Server

[Service]
Type=simple
WorkingDirectory=${HEKETI_WORK_DIR}
ExecStart=/usr/bin/heketi --config=${HEKETI_JSON}
Restart=on-failure
StandardOutput=syslog
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF

# 生成heketi的两个配置文件
generateHeketiJson
generateTopologyJson
# 生成、分发SSH KEY
generateSSHKey
# 清空远程文件系统
wipefsRemote

echo "heketi配置完成，准备启动"
# 启动heketi
systemctl enable heketi || echo "heketi设置开机启动失败"
systemctl start heketi || echo "heketi启动失败"

echo "heketi启动完毕"
# 等几秒，不能立即调用，不然可能服务还没启动起来
sleep 5
# 加载glusterfs集群
heketi-cli topology load --user admin --secret ${HEKETI_ADMIN_TOKEN} --json=${HEKETI_TOPOLOGY_JSON}
}
# heketi安装完成



###################################################################################################################
##
## 安装gluster
##
###################################################################################################################


# 安装gluster
function installGluster() {
mkdirIfAbsent ${GLUSTERD_WORK_DIR}
mkdirIfAbsent ${GLUSTERD_LOG_DIR}

# 安装gluster的源，其中也包含了heketi
yum install -q -y centos-release-gluster
# 安装glusterfs服务
yum install -q -y glusterfs-server

# 修改glusterfs服务的定义
cat << EOF > /usr/lib/systemd/system/glusterd.service
[Unit]
Description=GlusterFS, a clustered file-system server
Documentation=man:glusterd(8)
Requires=
After=network.target 
Before=network-online.target

[Service]
Type=forking
PIDFile=/var/run/glusterd.pid
LimitNOFILE=65536
ExecStart=/usr/sbin/glusterd -p /var/run/glusterd.pid --log-level=${GLUSTERD_LOG_LEVEL}
KillMode=process
SuccessExitStatus=15

[Install]
WantedBy=multi-user.target
EOF


echo "将gluster的log重定向到目录[${GLUSTERD_LOG_DIR}]"
# 先删除老的文件
rm -rf /var/log/glusterfs
# 创建软链接（因为找不到修改日志路径的参数配置，所以只能这么做了）
ln -s ${GLUSTERD_LOG_DIR} /var/log/glusterfs

systemctl enable glusterd
systemctl start glusterd
}

# 以下开始copy本行（注释行）以上的内容
COPY_END=$((LINENO-2))
# gluster和heketi的安装文件定义一致，最终调用不一样，动态生成
sed -n "1,${COPY_END}p" ${0} > gluster.install.sh
sed -n "1,${COPY_END}p" ${0} > heketi.install.sh


# 写入安装gluster
cat << EOF >> gluster.install.sh
installGluster
EOF

# 写入安装heketi
cat << EOF >> heketi.install.sh
# heketi安装先sleep一会儿，防止gluster没有安装完毕
sleep 60s
installHeketi
EOF

echo -e "\n\n"
echo "开始分发安装gluster任务"
# 将glusterfs安装文件分发出去
for ((i=0; i < ${#GLUSTERFS_IP_ADDS[*]}; i++))
do
    echo -e "\t在机器${GLUSTERFS_IP_ADDS[${i}]}上安装gluster"
    # 执行远程安装，注意要先创建目录，后边执行的时候会用
    execRemote ${GLUSTERFS_SSH_PORT} ${GLUSTERFS_SSH_USER} ${GLUSTERFS_IP_ADDS[${i}]} ${GLUSTERFS_SSH_PASSWD} "mkdir -p ${GLUSTERD_WORK_DIR}" "\t"
    execRemote ${GLUSTERFS_SSH_PORT} ${GLUSTERFS_SSH_USER} ${GLUSTERFS_IP_ADDS[${i}]} ${GLUSTERFS_SSH_PASSWD} "systemctl stop firewalld && systemctl disable firewalld" "\t"
    execSSHWithoutPasswd "scp -P ${GLUSTERFS_SSH_PORT} gluster.install.sh ${GLUSTERFS_SSH_USER}@${GLUSTERFS_IP_ADDS[${i}]}:${GLUSTERD_WORK_DIR}" ${GLUSTERFS_SSH_PASSWD}
    execRemote ${GLUSTERFS_SSH_PORT} ${GLUSTERFS_SSH_USER} ${GLUSTERFS_IP_ADDS[${i}]} ${GLUSTERFS_SSH_PASSWD} "nohup sh ${GLUSTERD_WORK_DIR}/gluster.install.sh >${GLUSTERD_WORK_DIR}/gluster.install.log &" "\t"
    echo -e "\t----------------------------------------"
done
# 本地这个可以删除了
rm -rf gluster.install.sh
echo "gluster集群安装任务分发完毕"


echo -e "\n\n\n"
echo "在机器${HEKETI_IP}上分发安装heketi的任务"
# 执行远程安装，注意要先创建目录，后边执行的时候会用
execRemote ${HEKETI_SSH_PORT} ${HEKETI_SSH_USER} ${HEKETI_IP} ${HEKETI_SSH_PASSWD} "mkdir -p ${HEKETI_WORK_DIR}" "\t"
execRemote ${HEKETI_SSH_PORT} ${HEKETI_SSH_USER} ${HEKETI_IP} ${HEKETI_SSH_PASSWD} "systemctl stop firewalld && systemctl disable firewalld" "\t"
# 将heketi安装文件分发出去
execSSHWithoutPasswd "scp -P ${HEKETI_SSH_PORT} heketi.install.sh ${HEKETI_SSH_USER}@${HEKETI_IP}:${HEKETI_WORK_DIR}" ${HEKETI_SSH_PASSWD}
execRemote ${HEKETI_SSH_PORT} ${HEKETI_SSH_USER} ${HEKETI_IP} ${HEKETI_SSH_PASSWD} "nohup sh ${HEKETI_WORK_DIR}/heketi.install.sh >${HEKETI_WORK_DIR}/heketi.install.log &" "\t"
# 本地这个可以删除了
rm -rf heketi.install.sh
echo "heketi安装任务分发完毕"


echo "安装将在稍后完成，请您登录机器查看实际安装情况"
