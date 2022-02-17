# K8S集群安装脚本使用方式
修改 `deploy.sh` 脚本中的参数，主要是集群主节点IP、密码、安装目录以及node节点的IP、密码；其他的变量如果没有特殊需求无需更改；

`deploy.sh`执行需要一个参数：证书密码，用于作为生成ca的密码，后续如果要使用该ca签署证书时需要该密码；


执行完`deploy.sh`确定集群部署起来后，可以找到`target/installer/plugin`目录中的`install-plugins.sh`文件，执行该命令可以安装常用plugin，该命令需要两个参数，第一个是etcd server，例如192.168.1.1:2379，第二个是kuboard域名，例如kuboard.kube.com（用于配置ingress规则）；