# 切换到安装目录
cd /filebeat/filebeat-7.13.3-linux-x86_64

INIT_SCRIPT_DIR=/filebeat/init-script

# 如果初始化脚本目录存在，那么执行里边的初始化脚本
if [ -d "${INIT_SCRIPT_DIR}" ]; then
  cd ${INIT_SCRIPT_DIR}
  ls ${INIT_SCRIPT_DIR} | xargs -I {} sh ${INIT_SCRIPT_DIR}/{}
fi

# 开启elasticsearch模块
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat modules enable elasticsearch
# 启动前配置
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat setup

# 前台启动，日志打印到标准输出中
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat -e
