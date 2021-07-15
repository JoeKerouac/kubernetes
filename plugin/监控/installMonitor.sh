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


cd $NOW_DIR


# 注意，下面的变量需要根据不通环境来修改
storageClassName=glusterfs-storage
grafanaStorage=10Gi
grafanaAdminUserName=admin
grafanaAdminUserPassword=123456
grafanaEnableAnonymous=true
grafanaHost=grafana.kube.com
prometheusRetentionTime=15d
prometheusStorage=50Gi
prometheusHost=prometheus.kube.com



/bin/cp monitor.yaml monitor.yaml.apply
sed -i "s/\${storageClassName}/${storageClassName}/g" monitor.yaml.apply
sed -i "s/\${grafanaStorage}/${grafanaStorage}/g" monitor.yaml.apply
sed -i "s/\${grafanaAdminUserName}/${grafanaAdminUserName}/g" monitor.yaml.apply
sed -i "s/\${grafanaAdminUserPassword}/${grafanaAdminUserPassword}/g" monitor.yaml.apply
sed -i "s/\${grafanaEnableAnonymous}/${grafanaEnableAnonymous}/g" monitor.yaml.apply
sed -i "s/\${grafanaHost}/${grafanaHost}/g" monitor.yaml.apply
sed -i "s/\${prometheusRetentionTime}/${prometheusRetentionTime}/g" monitor.yaml.apply
sed -i "s/\${prometheusStorage}/${prometheusStorage}/g" monitor.yaml.apply
sed -i "s/\${prometheusHost}/${prometheusHost}/g" monitor.yaml.apply

kubectl apply -f monitor.yaml.apply
