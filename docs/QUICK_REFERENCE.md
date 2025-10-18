# Kubernetes 集群部署快速参考

本文档提供快速命令参考和常见场景配置。

## 🚀 快速部署命令

### 单 Master 集群（最常用）

**所有节点执行：**
```bash
# 1. 系统准备
sudo ./prep-system.sh --hostname $(hostname) \
  --add-host "192.168.1.10 k8s-master-01" \
  --add-host "192.168.1.11 k8s-worker-01" \
  --add-host "192.168.1.12 k8s-worker-02"

# 如需要，重启系统
sudo reboot

# 2. 安装 Docker 和 Kubernetes
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime containerd \
  --use-mirror
```

**Master 节点执行：**
```bash
# 3. 初始化 Master（使用 Calico）
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --pod-network-cidr 192.168.0.0/16 \
  --network-plugin calico

# 或使用 Flannel
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --pod-network-cidr 10.244.0.0/16 \
  --network-plugin flannel
```

**Worker 节点执行：**
```bash
# 4. 加入集群
sudo ./join-worker.sh --master-ssh root@192.168.1.10
```

### 高可用（HA）集群

**准备负载均衡器（例如：HAProxy 或 Nginx）**

**第一个 Master 节点：**
```bash
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --control-plane-endpoint "k8s-lb.example.com:6443" \
  --pod-network-cidr 192.168.0.0/16 \
  --network-plugin calico \
  --upload-certs
```

**其他 Master 节点：**
```bash
# 从第一个 Master 获取加入命令
kubeadm join k8s-lb.example.com:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <certificate-key>
```

**Worker 节点：**
```bash
sudo ./join-worker.sh \
  --master k8s-lb.example.com:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

## 📋 脚本参数速查

### prep-system.sh

```bash
# 完整参数
sudo ./prep-system.sh \
  --hostname <主机名> \
  --add-host "<IP> <主机名>" \
  --skip-chrony \
  --skip-reboot-check

# 最小化运行
sudo ./prep-system.sh

# 配置主机名和hosts
sudo ./prep-system.sh \
  --hostname k8s-node-01 \
  --add-host "192.168.1.10 k8s-master-01"
```

### install-docker-k8s.sh

```bash
# 完整参数
sudo ./install-docker-k8s.sh \
  --k8s-version <版本> \
  --runtime <docker|containerd> \
  --use-mirror \
  --skip-pull-images \
  --docker-version <版本>

# containerd + 镜像加速（推荐）
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime containerd \
  --use-mirror

# Docker + 不预拉取镜像
sudo ./install-docker-k8s.sh \
  --runtime docker \
  --skip-pull-images
```

### init-master.sh

```bash
# 完整参数
sudo ./init-master.sh \
  --apiserver-advertise-address <IP> \
  --pod-network-cidr <CIDR> \
  --service-cidr <CIDR> \
  --network-plugin <calico|flannel> \
  --k8s-version <版本> \
  --control-plane-endpoint <端点> \
  --upload-certs \
  --skip-network-plugin

# Calico 网络（推荐）
sudo ./init-master.sh \
  --network-plugin calico

# Flannel 网络
sudo ./init-master.sh \
  --network-plugin flannel \
  --pod-network-cidr 10.244.0.0/16

# HA 模式
sudo ./init-master.sh \
  --control-plane-endpoint "lb.example.com:6443" \
  --upload-certs
```

### join-worker.sh

```bash
# 完整参数
sudo ./join-worker.sh \
  --master <IP:端口> \
  --token <令牌> \
  --discovery-token-ca-cert-hash <哈希> \
  --join-command "<完整命令>" \
  --master-ssh <用户@主机> \
  --node-label "<键=值>" \
  --skip-verify

# SSH 自动获取（最简单）
sudo ./join-worker.sh --master-ssh root@192.168.1.10

# 手动指定参数
sudo ./join-worker.sh \
  --master 192.168.1.10:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:xxx

# 添加节点标签
sudo ./join-worker.sh \
  --master-ssh root@192.168.1.10 \
  --node-label "node-role.kubernetes.io/worker=" \
  --node-label "env=production"
```

## 🌐 网络配置速查

### Calico 配置

```bash
# 默认配置
Pod CIDR: 192.168.0.0/16
Service CIDR: 10.96.0.0/12

# 初始化命令
sudo ./init-master.sh \
  --pod-network-cidr 192.168.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --network-plugin calico

# 自定义 IP 池
sudo ./init-master.sh \
  --pod-network-cidr 172.16.0.0/16 \
  --network-plugin calico
```

### Flannel 配置

```bash
# 默认配置
Pod CIDR: 10.244.0.0/16
Service CIDR: 10.96.0.0/12

# 初始化命令
sudo ./init-master.sh \
  --pod-network-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --network-plugin flannel

# 自定义 CIDR
sudo ./init-master.sh \
  --pod-network-cidr 10.100.0.0/16 \
  --network-plugin flannel
```

### 网络规划示例

**小型集群（< 50 节点）**
```
Node 网络: 192.168.1.0/24
Pod 网络: 10.244.0.0/16
Service 网络: 10.96.0.0/12
```

**中型集群（50-200 节点）**
```
Node 网络: 10.0.0.0/16
Pod 网络: 172.16.0.0/12
Service 网络: 10.96.0.0/12
```

**大型集群（> 200 节点）**
```
Node 网络: 10.0.0.0/8
Pod 网络: 172.16.0.0/12
Service 网络: 192.168.0.0/16
```

## 🔍 验证和调试命令

### 集群状态检查

```bash
# 查看节点
kubectl get nodes
kubectl get nodes -o wide

# 查看所有 Pod
kubectl get pods -A
kubectl get pods -A -o wide

# 查看特定命名空间
kubectl get pods -n kube-system

# 查看集群信息
kubectl cluster-info
kubectl cluster-info dump

# 查看组件状态（Kubernetes 1.19 之前）
kubectl get cs
```

### 节点诊断

```bash
# 查看节点详情
kubectl describe node <节点名>

# 查看节点资源使用
kubectl top nodes

# 查看节点标签
kubectl get nodes --show-labels

# 查看节点污点
kubectl describe node <节点名> | grep Taints

# 查看节点分配的 Pod
kubectl get pods -A --field-selector spec.nodeName=<节点名>
```

### Pod 诊断

```bash
# 查看 Pod 详情
kubectl describe pod <pod名> -n <命名空间>

# 查看 Pod 日志
kubectl logs <pod名> -n <命名空间>
kubectl logs <pod名> -n <命名空间> -f
kubectl logs <pod名> -c <容器名> -n <命名空间>

# 查看之前的日志（崩溃的容器）
kubectl logs <pod名> -n <命名空间> --previous

# 进入 Pod
kubectl exec -it <pod名> -n <命名空间> -- /bin/sh
```

### 网络诊断

```bash
# 测试 Pod 间通信
kubectl run test-pod --image=busybox --rm -it -- /bin/sh
# 在 Pod 中执行：
ping <目标 Pod IP>
wget <目标 Service>

# 查看 Service
kubectl get svc -A

# 查看 Endpoints
kubectl get endpoints -A

# 查看网络插件 Pod
kubectl get pods -n kube-system | grep -E "calico|flannel"

# 测试 DNS
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default
```

### 组件日志

```bash
# kubelet 日志
journalctl -u kubelet -f
journalctl -u kubelet --since "1 hour ago"
journalctl -u kubelet -n 100

# containerd 日志
journalctl -u containerd -f

# Docker 日志
journalctl -u docker -f

# 查看容器日志
crictl logs <容器ID>
docker logs <容器ID>

# 查看运行的容器
crictl ps
docker ps
```

## 🛠️ 常用维护命令

### 令牌管理

```bash
# 生成新的加入令牌
kubeadm token create --print-join-command

# 列出所有令牌
kubeadm token list

# 删除令牌
kubeadm token delete <令牌>

# 创建永久令牌（不推荐）
kubeadm token create --ttl 0
```

### 证书管理

```bash
# 查看证书过期时间
kubeadm certs check-expiration

# 续期所有证书
kubeadm certs renew all

# 续期特定证书
kubeadm certs renew apiserver
```

### 节点管理

```bash
# 标记节点不可调度
kubectl cordon <节点名>

# 驱逐节点上的 Pod
kubectl drain <节点名> --ignore-daemonsets --delete-emptydir-data

# 标记节点可调度
kubectl uncordon <节点名>

# 删除节点
kubectl delete node <节点名>

# 给节点打标签
kubectl label node <节点名> key=value

# 删除节点标签
kubectl label node <节点名> key-

# 给节点添加污点
kubectl taint nodes <节点名> key=value:NoSchedule

# 删除节点污点
kubectl taint nodes <节点名> key:NoSchedule-
```

### 清理和重置

```bash
# 重置节点（在需要重置的节点上执行）
kubeadm reset -f

# 清理网络配置
rm -rf /etc/cni/net.d

# 清理 iptables 规则
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

# 清理 IPVS 规则
ipvsadm --clear

# 清理 Kubernetes 配置
rm -rf $HOME/.kube
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
```

## 📊 资源管理

### 资源查看

```bash
# 查看节点资源
kubectl top nodes

# 查看 Pod 资源
kubectl top pods -A
kubectl top pods -n <命名空间>

# 查看资源配额
kubectl get resourcequota -A

# 查看限制范围
kubectl get limitrange -A
```

### 扩缩容

```bash
# 扩展 Deployment
kubectl scale deployment <名称> --replicas=3 -n <命名空间>

# 自动扩缩容
kubectl autoscale deployment <名称> --min=2 --max=10 --cpu-percent=80
```

## 🔐 安全和权限

```bash
# 创建 ServiceAccount
kubectl create serviceaccount <名称> -n <命名空间>

# 创建 Role
kubectl create role <名称> --verb=get,list --resource=pods -n <命名空间>

# 创建 RoleBinding
kubectl create rolebinding <名称> --role=<角色名> --serviceaccount=<命名空间>:<账号名>

# 查看权限
kubectl auth can-i <动作> <资源> --as=<用户>

# 查看当前上下文
kubectl config current-context

# 切换上下文
kubectl config use-context <上下文名>
```

## 📦 备份和恢复

### etcd 备份

```bash
# 备份 etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 验证备份
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db
```

### etcd 恢复

```bash
# 恢复 etcd
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restore
```

## 📁 重要文件位置

```bash
# Kubernetes 配置
/etc/kubernetes/
  ├── admin.conf          # 管理员配置
  ├── kubelet.conf        # kubelet 配置
  ├── controller-manager.conf
  ├── scheduler.conf
  └── pki/                # 证书目录

# kubelet 配置
/var/lib/kubelet/
  └── config.yaml

# 容器运行时配置
/etc/containerd/config.toml
/etc/docker/daemon.json

# 日志位置
/var/log/k8s-deploy/     # 部署脚本日志
/var/log/pods/           # Pod 日志
journalctl -u kubelet    # kubelet 日志
journalctl -u containerd # containerd 日志

# etcd 数据
/var/lib/etcd/
```

## 🔗 常用 kubectl 别名

添加到 `~/.bashrc` 或 `~/.zshrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgn='kubectl get nodes'
alias kgs='kubectl get svc'
alias kgd='kubectl get deploy'
alias kdp='kubectl describe pod'
alias kdn='kubectl describe node'
alias kl='kubectl logs'
alias kex='kubectl exec -it'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
```

使用示例：
```bash
k get pods -A
kgp -n kube-system
kdp <pod名> -n <命名空间>
kl <pod名> -n <命名空间> -f
```

---

**提示**: 将此文档保存到本地以便快速查阅！
