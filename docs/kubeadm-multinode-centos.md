# Kubeadm 多节点集群部署教程（CentOS 7/8）

本教程将指导您使用 kubeadm 在 CentOS 7/8 系统上从零开始搭建一个生产级的 Kubernetes 多节点集群。

## 目录

- [环境准备](#环境准备)
- [系统要求](#系统要求)
- [前置配置](#前置配置)
- [安装容器运行时（Docker）](#安装容器运行时docker)
- [安装 Kubernetes 组件](#安装-kubernetes-组件)
- [初始化 Master 节点](#初始化-master-节点)
- [配置网络插件](#配置网络插件)
  - [方案一：Calico](#方案一calico)
  - [方案二：Flannel](#方案二flannel)
- [添加 Worker 节点](#添加-worker-节点)
- [集群验证](#集群验证)
- [部署示例应用](#部署示例应用)
- [故障排查](#故障排查)
- [最佳实践](#最佳实践)

## 环境准备

### 系统要求

- **操作系统**: CentOS 7.x 或 CentOS 8.x
- **最低硬件配置**:
  - Master 节点: 2 CPU, 4GB RAM, 20GB 磁盘空间
  - Worker 节点: 2 CPU, 2GB RAM, 20GB 磁盘空间
- **网络要求**: 所有节点之间网络互通
- **必需端口**:
  - Master 节点:
    - 6443: Kubernetes API Server
    - 2379-2380: etcd
    - 10250: Kubelet API
    - 10251: kube-scheduler
    - 10252: kube-controller-manager
  - Worker 节点:
    - 10250: Kubelet API
    - 30000-32767: NodePort 服务

### 集群拓扑示例

本教程假设以下节点配置：

```
master01: 192.168.1.10
worker01: 192.168.1.11
worker02: 192.168.1.12
```

请根据您的实际环境修改 IP 地址。

## 前置配置

以下步骤需要在**所有节点**上执行。

### 1. 设置主机名

```bash
# 在 master 节点上
sudo hostnamectl set-hostname master01

# 在 worker 节点上
sudo hostnamectl set-hostname worker01  # 或 worker02
```

### 2. 配置 hosts 文件

编辑 `/etc/hosts` 文件，添加所有节点的主机名和 IP 映射：

```bash
sudo tee -a /etc/hosts <<EOF
192.168.1.10 master01
192.168.1.11 worker01
192.168.1.12 worker02
EOF
```

### 3. 关闭防火墙（或配置必要规则）

```bash
# 方式一：关闭防火墙（测试环境）
sudo systemctl stop firewalld
sudo systemctl disable firewalld

# 方式二：配置防火墙规则（生产环境推荐）
# Master 节点
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=10251/tcp
sudo firewall-cmd --permanent --add-port=10252/tcp
sudo firewall-cmd --reload

# Worker 节点
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --reload
```

### 4. 关闭 SELinux

```bash
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
```

### 5. 禁用 swap

Kubernetes 要求禁用 swap：

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### 6. 配置内核参数

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 7. 验证配置

```bash
# 验证模块是否加载
lsmod | grep br_netfilter
lsmod | grep overlay

# 验证内核参数
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

## 安装容器运行时（Docker）

在**所有节点**上安装 Docker：

### CentOS 7

```bash
# 安装依赖
sudo yum install -y yum-utils device-mapper-persistent-data lvm2

# 添加 Docker 仓库
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 安装 Docker
sudo yum install -y docker-ce docker-ce-cli containerd.io

# 配置 Docker daemon
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# 启动 Docker
sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl start docker

# 验证安装
sudo docker --version
```

### CentOS 8

```bash
# 安装依赖
sudo dnf install -y yum-utils device-mapper-persistent-data lvm2

# 添加 Docker 仓库
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 安装 Docker
sudo dnf install -y docker-ce docker-ce-cli containerd.io

# 配置 Docker daemon（与 CentOS 7 相同）
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# 启动 Docker
sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl start docker

# 验证安装
sudo docker --version
```

### 配置 cgroup 驱动

确保 Docker 和 kubelet 使用相同的 cgroup 驱动（systemd）：

```bash
# 验证 Docker cgroup 驱动
sudo docker info | grep -i cgroup
```

输出应该显示 `Cgroup Driver: systemd`。

## 安装 Kubernetes 组件

在**所有节点**上安装 kubeadm、kubelet 和 kubectl。

### 1. 添加 Kubernetes 仓库

```bash
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
```

**注意**: 如果无法访问 Google 服务器，可以使用国内镜像源：

```bash
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
```

### 2. 安装 Kubernetes 组件

```bash
# CentOS 7
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# CentOS 8
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# 启动 kubelet
sudo systemctl enable --now kubelet
```

### 3. 验证安装

```bash
kubeadm version
kubelet --version
kubectl version --client
```

## 初始化 Master 节点

**仅在 Master 节点上执行以下步骤。**

### 1. 预拉取镜像（可选但推荐）

```bash
sudo kubeadm config images pull
```

如果无法访问 Google 镜像仓库，使用国内镜像：

```bash
sudo kubeadm config images pull --image-repository registry.aliyuncs.com/google_containers
```

### 2. 初始化集群

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=192.168.1.10 \
  --image-repository registry.aliyuncs.com/google_containers
```

**参数说明**:
- `--pod-network-cidr`: Pod 网络的 CIDR 范围（Flannel 默认使用 10.244.0.0/16，Calico 可以使用 192.168.0.0/16）
- `--apiserver-advertise-address`: Master 节点的 IP 地址
- `--image-repository`: 镜像仓库地址（使用国内镜像）

初始化成功后，您会看到类似以下的输出：

```
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.1.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

**重要**: 保存 `kubeadm join` 命令，稍后将用于添加 Worker 节点。

### 3. 配置 kubectl

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 4. 验证 Master 节点

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

此时 Master 节点状态为 `NotReady`，因为还没有安装网络插件。

## 配置网络插件

选择以下两种网络方案之一。

### 方案一：Calico

Calico 是一个高性能的网络和网络策略解决方案。

```bash
# 下载 Calico 配置文件
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml -O

# 如果需要修改 Pod CIDR，编辑 calico.yaml 并取消注释以下行：
# - name: CALICO_IPV4POOL_CIDR
#   value: "192.168.0.0/16"

# 应用 Calico
kubectl apply -f calico.yaml
```

**国内环境**: 如果无法访问 GitHub，可以使用以下命令：

```bash
kubectl apply -f https://gitee.com/mirrors/calico/raw/v3.26.1/manifests/calico.yaml
```

### 方案二：Flannel

Flannel 是一个简单易用的网络解决方案。

```bash
# 应用 Flannel
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

**国内环境**: 如果无法访问 GitHub，可以手动下载并应用：

```bash
wget https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f kube-flannel.yml
```

### 验证网络插件

```bash
# 等待所有 Pod 运行
kubectl get pods -n kube-system

# 检查节点状态
kubectl get nodes
```

Master 节点状态应该变为 `Ready`。

## 添加 Worker 节点

**在每个 Worker 节点上执行以下步骤。**

### 1. 加入集群

使用之前保存的 `kubeadm join` 命令：

```bash
sudo kubeadm join 192.168.1.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

### 2. 如果 token 过期

如果忘记保存 token 或 token 已过期（24 小时后），在 Master 节点上生成新的 token：

```bash
# 生成新 token
kubeadm token create --print-join-command
```

这将输出完整的 `kubeadm join` 命令。

### 3. 验证 Worker 节点

在 Master 节点上检查：

```bash
kubectl get nodes
```

所有节点应该显示为 `Ready` 状态。

## 集群验证

### 1. 检查节点状态

```bash
kubectl get nodes -o wide
```

输出示例：

```
NAME       STATUS   ROLES           AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION           CONTAINER-RUNTIME
master01   Ready    control-plane   10m   v1.28.0   192.168.1.10   <none>        CentOS Linux 7 (Core)   3.10.0-1160.el7.x86_64   docker://24.0.5
worker01   Ready    <none>          5m    v1.28.0   192.168.1.11   <none>        CentOS Linux 7 (Core)   3.10.0-1160.el7.x86_64   docker://24.0.5
worker02   Ready    <none>          5m    v1.28.0   192.168.1.12   <none>        CentOS Linux 7 (Core)   3.10.0-1160.el7.x86_64   docker://24.0.5
```

### 2. 检查系统 Pod

```bash
kubectl get pods -n kube-system
```

所有 Pod 应该处于 `Running` 状态。

### 3. 检查集群信息

```bash
kubectl cluster-info
kubectl get componentstatuses
```

## 部署示例应用

### 1. 部署 Nginx 应用

创建一个简单的 Nginx 部署：

```bash
# 创建 Deployment
kubectl create deployment nginx --image=nginx:latest --replicas=3

# 查看 Deployment
kubectl get deployment

# 查看 Pod
kubectl get pods -o wide
```

### 2. 暴露服务

```bash
# 创建 Service（NodePort 类型）
kubectl expose deployment nginx --port=80 --type=NodePort

# 查看 Service
kubectl get svc nginx
```

### 3. 访问应用

```bash
# 获取 NodePort
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
echo "Nginx is accessible at: http://<任意节点IP>:$NODE_PORT"

# 测试访问
curl http://192.168.1.11:$NODE_PORT
```

### 4. 部署完整示例应用

创建一个包含 Deployment 和 Service 的示例应用：

```yaml
# 保存为 webapp.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  labels:
    app: webapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: webapp
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: webapp-service
spec:
  type: NodePort
  selector:
    app: webapp
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30080
```

部署应用：

```bash
kubectl apply -f webapp.yaml

# 验证部署
kubectl get deployment webapp
kubectl get pods -l app=webapp
kubectl get svc webapp-service

# 访问应用
curl http://192.168.1.11:30080
```

### 5. 测试跨节点通信

```bash
# 创建测试 Pod
kubectl run test-pod --image=busybox --rm -it --restart=Never -- sh

# 在 Pod 内测试网络
wget -O- http://webapp-service
nslookup webapp-service
```

## 故障排查

### 常见问题

#### 1. 节点状态 NotReady

**检查步骤**:

```bash
# 查看节点详情
kubectl describe node <node-name>

# 检查 kubelet 日志
sudo journalctl -u kubelet -f

# 检查网络插件 Pod
kubectl get pods -n kube-system | grep -E 'calico|flannel'
```

**可能原因**:
- 网络插件未正确安装
- Docker 服务未运行
- 防火墙阻止了必要的端口

#### 2. Pod 无法启动

```bash
# 查看 Pod 详情
kubectl describe pod <pod-name>

# 查看 Pod 日志
kubectl logs <pod-name>

# 查看 Pod 事件
kubectl get events --sort-by=.metadata.creationTimestamp
```

**常见原因**:
- 镜像拉取失败
- 资源不足
- 权限问题

#### 3. 无法拉取镜像

如果遇到镜像拉取失败，配置镜像加速器：

```bash
# 编辑 Docker daemon 配置
sudo tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://registry.docker-cn.com"
  ]
}
EOF

# 重启 Docker
sudo systemctl daemon-reload
sudo systemctl restart docker
```

#### 4. Worker 节点无法加入集群

**检查网络连接**:

```bash
# 在 Worker 节点上测试与 Master 的连接
telnet 192.168.1.10 6443

# 检查防火墙
sudo iptables -L -n | grep 6443
```

**重置节点并重新加入**:

```bash
# 在 Worker 节点上
sudo kubeadm reset
sudo rm -rf /etc/cni/net.d
sudo systemctl restart kubelet

# 重新执行 join 命令
sudo kubeadm join ...
```

#### 5. DNS 解析问题

```bash
# 检查 CoreDNS Pod
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 测试 DNS 解析
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default

# 查看 CoreDNS 日志
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### 诊断命令汇总

```bash
# 节点诊断
kubectl get nodes -o wide
kubectl describe node <node-name>

# Pod 诊断
kubectl get pods --all-namespaces
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# 服务诊断
kubectl get svc --all-namespaces
kubectl describe svc <service-name> -n <namespace>

# 网络诊断
kubectl get pods -n kube-system -o wide
kubectl exec -it <pod-name> -- sh

# 系统日志
sudo journalctl -u kubelet -f
sudo journalctl -u docker -f

# 集群配置
kubectl config view
kubectl cluster-info dump
```

## 最佳实践

### 1. 高可用配置

对于生产环境，建议使用多个 Master 节点：

- 至少 3 个 Master 节点
- 使用外部 etcd 集群
- 配置负载均衡器（HAProxy 或 Nginx）

### 2. 资源管理

为 Pod 设置合理的资源请求和限制：

```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "250m"
  limits:
    memory: "128Mi"
    cpu: "500m"
```

### 3. 节点标签和污点

合理使用节点标签和污点来控制 Pod 调度：

```bash
# 添加节点标签
kubectl label nodes worker01 node-role.kubernetes.io/worker=worker

# 添加污点（例如，专用节点）
kubectl taint nodes worker01 dedicated=special:NoSchedule
```

### 4. 监控和日志

部署监控和日志收集系统：

- **监控**: Prometheus + Grafana
- **日志**: ELK Stack (Elasticsearch, Logstash, Kibana) 或 EFK (Fluentd 替代 Logstash)

### 5. 备份策略

定期备份 etcd 数据：

```bash
# 备份 etcd
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db
```

### 6. 安全加固

- **启用 RBAC**: Kubernetes 默认启用，确保正确配置角色和绑定
- **网络策略**: 使用 NetworkPolicy 限制 Pod 间通信
- **Pod 安全策略**: 限制 Pod 的安全上下文
- **定期更新**: 保持 Kubernetes 和组件版本更新

```bash
# 检查 RBAC 是否启用
kubectl cluster-info dump | grep authorization-mode
```

### 7. 升级策略

定期升级 Kubernetes 版本：

```bash
# 升级 kubeadm
sudo yum update kubeadm --disableexcludes=kubernetes

# 查看升级计划
sudo kubeadm upgrade plan

# 升级集群
sudo kubeadm upgrade apply v1.28.x

# 升级 kubelet 和 kubectl
sudo yum update kubelet kubectl --disableexcludes=kubernetes
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### 8. 性能优化

- **etcd 优化**: 将 etcd 数据存储在 SSD 上
- **节点规格**: 根据工作负载选择合适的节点规格
- **Pod QoS**: 合理设置 Pod 的 QoS 等级
- **网络优化**: 根据需求选择合适的 CNI 插件

### 9. 运维工具推荐

- **kubectl**: 命令行工具
- **Helm**: 包管理器
- **Lens**: Kubernetes IDE
- **k9s**: 终端 UI 工具
- **kubectl-tree**: 查看资源依赖树

### 10. 文档和配置管理

- 使用 Git 管理所有 Kubernetes 配置文件
- 采用 GitOps 实践（如 Flux 或 ArgoCD）
- 维护详细的集群配置文档
- 记录所有重要的运维操作

## 总结

本教程涵盖了从零开始在 CentOS 7/8 上部署 Kubernetes 多节点集群的完整流程，包括：

1. ✅ 系统准备和前置配置
2. ✅ Docker 和 Kubernetes 组件安装
3. ✅ Master 节点初始化
4. ✅ 网络插件配置（Calico/Flannel）
5. ✅ Worker 节点加入
6. ✅ 集群验证和示例应用部署
7. ✅ 故障排查指南
8. ✅ 生产环境最佳实践

现在您已经拥有一个功能完整的 Kubernetes 集群！继续探索 Kubernetes 的强大功能，部署更多应用吧！

## 参考资源

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [kubeadm 文档](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Calico 文档](https://docs.projectcalico.org/)
- [Flannel 文档](https://github.com/flannel-io/flannel)
- [Docker 文档](https://docs.docker.com/)

## 贡献

如果您在使用本教程时发现任何问题或有改进建议，欢迎提交 Issue 或 Pull Request。

---

**版本**: v1.0  
**更新日期**: 2025-10-18  
**适用版本**: Kubernetes v1.28+, CentOS 7/8
