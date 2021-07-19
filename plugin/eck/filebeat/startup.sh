# 切换到安装目录
cd /filebeat/filebeat-7.13.3-linux-x86_64
# 开启elasticsearch模块
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat modules enable elasticsearch
# 启动前配置
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat setup

# 前台启动，日志打印到标准输出中
/filebeat/filebeat-7.13.3-linux-x86_64/filebeat -e
