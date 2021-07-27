#!/usr/bin/env bash
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



# 如果指定目录不存在则创建
mkdirIfAbsent() {
	if [ ! -d $1 ]; then
	echo "目录[$1]不存在，创建..."
	mkdir -p $1
	fi
}


##########################################
##
## 部署检查，检查部署是否成功
##
##########################################

function checkPod() {
echo "容器部署检查"

# 检查超时时间，单位秒
timeout=600
# 当前检查时间
now=0

# 线下环境超时检查设置为10分钟
echo "当前部署成功检查超时时间设置为${timeout}秒"


ENV=$1
APP_NAME=$2
REP=$3
while [ $now -le $timeout ]; do
    sleep 1
    now=`expr ${now} + 1`

    # 获取运行中的pod数量，注意，不但要根据appName过滤，还要根据版本号过滤，注意，如果当前一个都没有这个命令会返回0，但是exit code不是0，也就是
    # 本脚本不能set -e，不然这里就会退出
    # 2/2是包含一个sidecar的场景
    podRunningCount=`/usr/bin/kubectl get pod -n ${NAMESPACE} | grep ${APP_NAME} | grep 1/1 | grep -ci "Running"`

    # 部署成功
    if [ "$podRunningCount" == "${REP}" ];then
        echo -e "the application ${APP_NAME} successfully deployed "
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        /usr/bin/kubectl get pod -o wide -n ${ENV} |grep ${APP_NAME}
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        return
    fi
done


echo -e "the application ${APP_NAME} deploy failed "
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        /usr/bin/kubectl get pod -o wide -n ${ENV}|grep ${APP_NAME}
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
}



# 本次要部署的namespace
NAMESPACE=$1
# 域名后缀，例如kube.com、local等，注意不要以.开头
DOMAIN=$2

DELOY_DIR=${NOW_DIR}/${NAMESPACE}

echo "部署skywalking、eck到 ${NAMESPACE}，使用域名后缀为：${DOMAIN}"

mkdirIfAbsent ${DELOY_DIR}
rm -rf ${DELOY_DIR}/*

cp eck/all-in-one.yml ${DELOY_DIR}/all-in-one.yml.${NAMESPACE}
cp eck/es.yml ${DELOY_DIR}/es.yml.${NAMESPACE}
cp eck/kibana.yml ${DELOY_DIR}/kibana.yml.${NAMESPACE}
cp eck/filebeat.yml ${DELOY_DIR}/filebeat.yml.${NAMESPACE}
cp skywalking-oap.yml ${DELOY_DIR}/skywalking-oap.yml.${NAMESPACE}



sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/all-in-one.yml.${NAMESPACE}
sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/es.yml.${NAMESPACE}
sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/kibana.yml.${NAMESPACE}
sed -i "s/\${DOMAIN}/${DOMAIN}/g" ${DELOY_DIR}/kibana.yml.${NAMESPACE}
sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/filebeat.yml.${NAMESPACE}
sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/skywalking-oap.yml.${NAMESPACE}
sed -i "s/\${DOMAIN}/${DOMAIN}/g" ${DELOY_DIR}/skywalking-oap.yml.${NAMESPACE}




kubectl apply -f ${DELOY_DIR}/all-in-one.yml.${NAMESPACE}
checkPod ${NAMESPACE} elastic-operator 1
kubectl apply -f ${DELOY_DIR}/es.yml.${NAMESPACE}
kubectl apply -f ${DELOY_DIR}/kibana.yml.${NAMESPACE}
kubectl apply -f ${DELOY_DIR}/filebeat.yml.${NAMESPACE}
kubectl apply -f ${DELOY_DIR}/skywalking-oap.yml.${NAMESPACE}




















