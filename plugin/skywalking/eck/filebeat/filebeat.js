/////////////////////////////////////////////////////////////
//
// 用于为集群中已经部署起来的应用添加filebeat而不用重新发布（直接操作K8S）
// 注意：依赖js-yaml库
//
////////////////////////////////////////////////////////////

const fs = require('fs');
// 这里使用相对路径（js-yaml）加载不出来，暂时先用绝对路径代替
const yaml = require("/usr/lib/node_modules/js-yaml")
// 命令行
const exec = require('child_process').exec;

const filebeatImage = "nexus-prod.niceloo.com:8083/youlu/filebeat:7.13.3";

// 固定的，splice 2 获取命令行参数数组
let args = process.argv.splice(2);
let namespace = args[0];
let command = args[1];
let statefuleSetName = args[2];


if (isBlank(namespace) || isBlank(command) || isBlank(statefuleSetName)) {
    console.log("参数错误");
    help();
    process.exit(1);
}

if (command !== "add" && command !== "remove") {
    console.log("不支持的操作：" + command)
    process.exit(1);
}

console.log("准备为[" + statefuleSetName + "] " + command + " filebeat");

/**
 * 判断字符串为空
 * @param param 字符串
 * @returns {boolean} 返回true表示字符串是空，否则表示字符串不是空
 */
function isBlank(param) {
    if (param === undefined || param === null || param.trim().length === 0) {
        return true;
    } else {
        return false;
    }
}

function help() {
    console.log("使用方法：node filebeat.js [namespace] [command] [stateful set name]，例如node filebeat.js uat add usercenter")
    console.log("\tadd: 为指定应用添加file beat")
    console.log("\tremove： 移除指定应用的file beat")
}

/**
 * 调用shell命令
 * @param cmd 命令
 * @param callback 执行成功回调，会将输出传入
 */
function execute(cmd, callback) {
    exec(cmd, function (error, stdout, stderr) {
        if (error) {
            console.error(error);
            process.exit(1);
        } else {
            callback(stdout);
        }
    });
}

function writeYaml(yamlFilePath, yamlObj, append) {
    try {
        // 如果不是append就清空文件
        if (!append) {
            fs.writeFileSync(yamlFilePath, "", 'utf8');
        }
        fs.appendFileSync(yamlFilePath, "---\n", 'utf8');
        let yamlStr = yaml.dump(yamlObj);
        fs.appendFileSync(yamlFilePath, yamlStr + "\n", 'utf8');
    } catch (e) {
        console.log(e);
        process.exit(5);
    }
}


// 执行
execute("kubectl get statefulset " + statefuleSetName + " -n " + namespace + " -o json", function (out) {
    var statefulSet = JSON.parse(out);

    if (command === "add") {
        var volumes = statefulSet.spec.template.spec.volumes;
        if (volumes === undefined || volumes === null) {
            volumes = [];
            statefulSet.spec.template.spec.volumes = volumes;
        }

        volumes.push({
                name: "filebeat",
                configMap: {
                    name: "filebeat",
                    items: [
                        {
                            key: "filebeat.yml",
                            path: "filebeat.yml"
                        }
                    ]
                }
            }, {
                name: "init",
                configMap: {
                    name: "filebeat",
                    items: [
                        {
                            key: "init.sh",
                            path: "init.sh"
                        }
                    ]
                }
            }, {
                name: "k8s-index-template",
                configMap: {
                    name: "filebeat",
                    items: [
                        {
                            key: "k8s-index-template.json",
                            path: "k8s-index-template.json"
                        }
                    ]
                }
            }
        );

        statefulSet.spec.template.spec.containers.push({
            name: "filebeat",
            image: filebeatImage,
            imagePullPolicy: "Always",
            env: [
                {
                    name: "ENV",
                    valueFrom: {
                        fieldRef: {
                            fieldPath: "metadata.namespace",
                        }
                    }
                },
                {
                    name: "APP_NAME",
                    valueFrom: {
                        fieldRef: {
                            fieldPath: "metadata.labels['app']",
                        }
                    }
                },
                {
                    name: "POD_NAME",
                    valueFrom: {
                        fieldRef: {
                            fieldPath: "metadata.name",
                        }
                    }
                },
                {
                    name: "ES_PASSWORD",
                    valueFrom: {
                        secretKeyRef: {
                            name: "eck-es-elastic-user",
                            key: "elastic",
                        }
                    }
                },
            ],
            resources: {
                limits: {
                    cpu: "300m",
                    memory: "300Mi",
                },
                requests: {
                    cpu: "50m",
                    memory: "100Mi",
                }
            },
            volumeMounts: [
                {
                    mountPath: "/data/glusterfs",
                    name: "glusterfs",
                    readOnly: false,
                },
                {
                    mountPath: "/filebeat/filebeat-7.13.3-linux-x86_64/filebeat.yml",
                    subPath: "filebeat.yml",
                    name: "filebeat",
                    readOnly: false
                },
                {
                    mountPath: "/filebeat/init-script/init.sh",
                    subPath: "init.sh",
                    name: "init",
                    readOnly: false
                },
                {
                    mountPath: "/filebeat/filebeat-7.13.3-linux-x86_64/k8s-index-template.json",
                    subPath: "k8s-index-template.json",
                    name: "k8s-index-template",
                    readOnly: false
                }
            ]
        });

        writeYaml("yaml/" + statefuleSetName + ".yml", statefulSet, false);
    } else if (command === "remove") {
        let isFileBeat = false;

        // 去除filebeat的sidecar
        for (let i = 0; i < statefulSet.spec.template.spec.containers.length; i++) {
            if (statefulSet.spec.template.spec.containers[i].name === "filebeat") {
                isFileBeat = true;
                statefulSet.spec.template.spec.containers.splice(i, 1);
                i--;
            }
        }

        if (!isFileBeat) {
            console.log("当前stateful set " + statefuleSetName + " 中不包含file beat sidecar，不处理")
            process.exit(0);
        }

        // 去除挂载
        for (let i = 0; i < statefulSet.spec.template.spec.volumes.length; i++) {
            if (statefulSet.spec.template.spec.volumes[i].name === "filebeat" ||
                statefulSet.spec.template.spec.volumes[i].name === "init" ||
                statefulSet.spec.template.spec.volumes[i].name === "k8s-index-template.json") {
                statefulSet.spec.template.spec.volumes.splice(i, 1);
                break;
            }
        }

        writeYaml("yaml/" + statefuleSetName + ".yml", statefulSet, false);
    }
});
