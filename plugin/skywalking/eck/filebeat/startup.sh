# 切换到安装目录
cd /filebeat/filebeat-7.13.3-linux-x86_64


# 传入文件名，将文件中的变量替换
function replace() {
  FILE_NAME=$1
  echo "cat << EOF > ${FILE_NAME}" > replace.sh
  echo "DATE=`+%Y-%m-%d_%H:%M:%S`" >> replace.sh
  cat ${FILE_NAME} >> replace.sh
  echo "EOF" >> replace.sh
  sh replace.sh
  rm -rf replace.sh
}

# 将replace.info中定义的文件列表中的变量使用环境变量替换
cat /filebeat/replace.info | xargs -I {} replace {}

# 开启elasticsearch模块
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat modules enable elasticsearch
# 启动前配置
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat setup

# 前台启动，日志打印到标准输出中
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat -e
