# 部署流程
> 官方文档参考：https://www.elastic.co/cn/elastic-cloud-kubernetes

- 部署ECK（定义在all-in-one.yaml中），注意将其中的 `docker.elastic.co` 替换为自己的仓库，同时将 `docker.elastic.co/eck/eck-operator:1.6.0`
  替换为自己的镜像（因为这个仓库在国内无法访问）；
- 部署elasticsearch，执行 `kubectl apply -f elasticsearch.yaml` 部署，部署前注意 `elasticsearch.yaml` 中声明的注意事项；
- 部署完成可以使用 `kubectl get es` （或者 `kubectl get elasticsearch`） 来查看elasticsearch的部署状态；
- 使用 `PASSWORD=$(kubectl get secret eck-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')` 来获取es的密码；
- 使用 `curl -u "elastic:$PASSWORD" -k "https://eck-es-http:9200"` 来请求es，注意将域名替换为ip或者自己映射的域名；


需要以下镜像，请提前准备（版本号根据自己选择更改）：
- docker.elastic.co/eck/eck-operator:1.6.0
- docker.elastic.co/elasticsearch/elasticsearch:7.13.3