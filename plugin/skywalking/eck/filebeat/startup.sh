INIT_SCRIPT_DIR=/filebeat/init-script

# 如果初始化脚本目录存在，那么执行里边的初始化脚本
if [ -d "${INIT_SCRIPT_DIR}" ]; then
  cd ${INIT_SCRIPT_DIR}
  ls ${INIT_SCRIPT_DIR} | xargs -I {} sh ${INIT_SCRIPT_DIR}/{}
fi

# 上边的脚本执行完毕后需要重新切换
cd /filebeat/filebeat-7.13.3-linux-x86_64

# 前台启动，日志打印到标准输出中
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat -e
