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

###################################################################################################################
##
## 如果K8S集群的存储策略设置的是保留，那么在PV和PVC删除时存储集群内的数据不会被删除，如果此时该存储不需要了那么需要
## 手动清除，因为手动清除比较麻烦，所以加了该脚本，用于快速清除PV、PVC删除了的存储；
##
## 注意：只要存储集群中的存储没有对应的PV，那么只要执行该脚本就会被删除，请谨慎操作；例如存储集群中有一块儿存储是
## 手动创建而不是通过K8S创建的，那么执行该脚本时这块儿存储将会被删除，而这块儿存储实际可能是另有用途的，这会导致
## 数据被误删除，所以请谨慎操作，最好是存储集群只供K8S使用，所有存储通过K8S创建，不去手动创建；
##
###################################################################################################################



kubectl get pv > /dev/null 2>&1 || (echo "kubectl命令不存在或者配置有问题，请检查；" && exit 1)
gluster volume list > /dev/null 2>&1 || (echo "gluster命令不存在或者配置有问题，请检查；" && exit 1)

# heketi命令，注意，如果heketi需要认证，请在这里写上认证信息
HEKETI="heketi-cli -s http://192.168.10.116:8080 "
export HEKETI



# 获取volume的ip
cat << \EOF > temp.sh
ip=`gluster volume info $1 | grep Brick1 | sed -r "s#Brick1:\s*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*#\1#g"`
echo "$1 $ip"
EOF

# 将volume详情写出到volume.info
gluster volume list | xargs -I {} sh temp.sh {} | cat >volume.info

rm -rf temp.sh




# 获取pvc的path和pvc对应关系
cat << \EOF > temp.sh
vol_path=`kubectl describe pv $1 | grep Path | awk '{print $2}'`
echo "$2 $vol_path"
EOF


kubectl get pv | awk '{if (NR>1){cmd="sh temp.sh "$1" "$6; system(cmd)}}' | awk '{cmd="sed -i -r \"s#"$2"#"$1"\\ "$2"#g\" volume.info"; system(cmd)}'
rm -rf temp.sh

sed -i -r "s#/#-#g" volume.info

# 将待删除的volume写出
cat volume.info | grep ^vol_ | cat > wait_clean.volume


# 停止volume函数开始
cat << \FUNCTION > gluster-op.sh
# 函数依赖于expect
yum install -q -y expect

expect << EOF
# 设置超时时间，单位秒
set time 100

spawn $1 $2
expect {
"*y/n*" { send "y\r"; }
}
expect eof
EOF
FUNCTION
# 停止volume函数结束



# 先停止
cat wait_clean.volume | awk '{print $1}' | xargs -I {} sh gluster-op.sh "gluster volume stop" {} >/dev/null
# 删除volume
cat wait_clean.volume | awk '{print $1}' | xargs -I {} sh gluster-op.sh "gluster volume delete" {} >/dev/null


cat wait_clean.volume | awk '{cmd="${HEKETI} volume list | grep "$1; system(cmd)}' | sed -r 's#Id:([0-9a-z]+)\s+.*#\1#g' | xargs -I {} ${HEKETI} volume delete {}

echo "无用volume清理完成"
