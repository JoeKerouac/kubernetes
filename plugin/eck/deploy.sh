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




NAMESPACE=$1
DELOY_DIR=${NOW_DIR}/${NAMESPACE}

echo "部署eck到${NAMESPACE}"

mkdirIfAbsent ${DELOY_DIR}
rm -rf ${DELOY_DIR}/*

cp all-in-one.yml ${DELOY_DIR}/all-in-one.yml.${NAMESPACE}
cp es.yml ${DELOY_DIR}/es.yml.${NAMESPACE}
cp kibana.yml ${DELOY_DIR}/kibana.yml.${NAMESPACE}
cp filebeat.yml ${DELOY_DIR}/filebeat.yml.${NAMESPACE}



sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/all-in-one.yml.${NAMESPACE}
sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/es.yml.${NAMESPACE}
sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/kibana.yml.${NAMESPACE}
sed -i "s/\${NAMESPACE}/${NAMESPACE}/g" ${DELOY_DIR}/filebeat.yml.${NAMESPACE}



kubectl apply -f ${DELOY_DIR}/all-in-one.yml.${NAMESPACE}
kubectl apply -f ${DELOY_DIR}/es.yml.${NAMESPACE}
kubectl apply -f ${DELOY_DIR}/kibana.yml.${NAMESPACE}
kubectl apply -f ${DELOY_DIR}/filebeat.yml.${NAMESPACE}
