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
## 将当前K8S集群中所有PVC挂载到本地，同时以pod name作为目录名方便查询；
##
## 挂载脚本，需要当前环境具有kubectl命令和gluster命令，同时本脚本同级目录不能包含要挂载的文件夹的名字（否则会认为
## 已经挂载过了）、不能包含temp.sh（本文件会临时写出）、不能包含volume.info文件（本文件临时写出）；
##
## 最终存储会被挂载在脚本的同级目录中；
##
## 取消mount（注意将当前的挂载目录替换为脚本所在的目录）：
## mount | grep 当前的挂载目录 | awk '{print $1}' | xargs -I {} umount {}
##
###################################################################################################################


kubectl get pv > /dev/null 2>&1 || (echo "kubectl命令不存在或者配置有问题，请检查；" && exit 1)
gluster volume list > /dev/null 2>&1 || (echo "gluster命令不存在或者配置有问题，请检查；" && exit 1)

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
# 排除不是K8S集群中的volume
# 文件正常格式每行都是：test-glusterfs-questionbank-0 vol_9d6eb69ac8bf596c912d40ea6a668e62 192.168.10.209
# 如果不是K8S集群中的volume，那么每行格式为：vol_9d6eb69ac8bf596c912d40ea6a668e62 192.168.10.209
sed -i -r "/^vol_.*/d" volume.info


# 开始挂载
cat << \EOF > temp.sh
if [ ! -d $3 ]; then
    mkdir $3
    mount -t glusterfs $1:$2 $3
else
    echo "$1:$2 $3已经挂载，跳过"
fi
EOF

cat volume.info | awk '{cmd="sh temp.sh "$3" "$2" "$1; system(cmd)}'

rm -rf temp.sh
