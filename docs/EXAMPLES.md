# 部署示例和场景

本文档提供各种常见部署场景的完整示例。

## 📋 目录

- [场景 1: 单 Master 三节点集群（Calico）](#场景-1-单-master-三节点集群calico)
- [场景 2: 单 Master 三节点集群（Flannel）](#场景-2-单-master-三节点集群flannel)
- [场景 3: 高可用三 Master 集群](#场景-3-高可用三-master-集群)
- [场景 4: 开发测试单节点集群](#场景-4-开发测试单节点集群)
- [场景 5: 使用 Docker 运行时](#场景-5-使用-docker-运行时)
- [场景 6: 离线环境部署](#场景-6-离线环境部署)

## 场景 1: 单 Master 三节点集群（Calico）

这是最常见的生产环境配置，使用 Calico 网络插件。

### 环境信息

| 角色 | 主机名 | IP 地址 | 配置 |
|-----|--------|---------|-----|
| Master | k8s-master-01 | 192.168.1.10 | 4C8G |
| Worker | k8s-worker-01 | 192.168.1.11 | 4C8G |
| Worker | k8s-worker-02 | 192.168.1.12 | 4C8G |

### 网络规划

```
节点网络: 192.168.1.0/24
Pod 网络: 192.168.0.0/16
Service 网络: 10.96.0.0/12
```

### 部署步骤

#### 所有节点（Master + Worker）

```bash
# 1. 系统准备
sudo ./prep-system.sh \
  --hostname $(hostname) \
  --add-host "192.168.1.10 k8s-master-01" \
  --add-host "192.168.1.11 k8s-worker-01" \
  --add-host "192.168.1.12 k8s-worker-02"

# 根据提示，如果需要重启
sudo reboot

# 2. 安装 containerd 和 Kubernetes
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime containerd \
  --use-mirror
```

#### Master 节点 (192.168.1.10)

```bash
# 3. 初始化集群
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --pod-network-cidr 192.168.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --network-plugin calico

# 4. 验证集群
kubectl get nodes
kubectl get pods -A

# 5. 查看加入命令
cat /var/log/k8s-deploy/kubeadm-join-command.sh
```

#### Worker 节点 (192.168.1.11, 192.168.1.12)

```bash
# 6. 加入集群
sudo ./join-worker.sh --master-ssh root@192.168.1.10

# 或手动方式
sudo ./join-worker.sh \
  --master 192.168.1.10:6443 \
  --token <token-from-master> \
  --discovery-token-ca-cert-hash sha256:<hash-from-master>
```

#### Master 节点验证

```bash
# 等待所有节点就绪
kubectl get nodes

# 应该看到类似输出：
# NAME              STATUS   ROLES           AGE   VERSION
# k8s-master-01     Ready    control-plane   5m    v1.28.0
# k8s-worker-01     Ready    <none>          3m    v1.28.0
# k8s-worker-02     Ready    <none>          2m    v1.28.0

# 检查所有 Pod
kubectl get pods -A

# 测试部署
kubectl create deployment nginx --image=nginx --replicas=3
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get pods,svc
```

## 场景 2: 单 Master 三节点集群（Flannel）

使用 Flannel 网络插件的简化配置，适合小型集群。

### 环境信息

同场景 1

### 网络规划

```
节点网络: 192.168.1.0/24
Pod 网络: 10.244.0.0/16  # Flannel 默认
Service 网络: 10.96.0.0/12
```

### 部署步骤

#### 所有节点

```bash
# 1-2. 系统准备和安装（同场景 1）
sudo ./prep-system.sh --hostname $(hostname) \
  --add-host "192.168.1.10 k8s-master-01" \
  --add-host "192.168.1.11 k8s-worker-01" \
  --add-host "192.168.1.12 k8s-worker-02"

sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime containerd \
  --use-mirror
```

#### Master 节点

```bash
# 3. 初始化集群（使用 Flannel）
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --pod-network-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --network-plugin flannel
```

#### Worker 节点

```bash
# 4. 加入集群（同场景 1）
sudo ./join-worker.sh --master-ssh root@192.168.1.10
```

## 场景 3: 高可用三 Master 集群

生产环境推荐配置，提供控制平面高可用性。

### 环境信息

| 角色 | 主机名 | IP 地址 | 配置 |
|-----|--------|---------|-----|
| Load Balancer | k8s-lb | 192.168.1.8 | 2C4G |
| Master 1 | k8s-master-01 | 192.168.1.10 | 4C8G |
| Master 2 | k8s-master-02 | 192.168.1.11 | 4C8G |
| Master 3 | k8s-master-03 | 192.168.1.12 | 4C8G |
| Worker 1 | k8s-worker-01 | 192.168.1.20 | 4C16G |
| Worker 2 | k8s-worker-02 | 192.168.1.21 | 4C16G |

### 网络规划

```
节点网络: 192.168.1.0/24
Pod 网络: 192.168.0.0/16
Service 网络: 10.96.0.0/12
VIP: k8s-api.example.com (192.168.1.8)
```

### 负载均衡器配置

#### 安装 HAProxy

```bash
# 在 k8s-lb (192.168.1.8) 上
yum install -y haproxy

cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend kubernetes-apiserver
    bind *:6443
    mode tcp
    default_backend kubernetes-master

backend kubernetes-master
    mode tcp
    balance roundrobin
    server k8s-master-01 192.168.1.10:6443 check fall 3 rise 2
    server k8s-master-02 192.168.1.11:6443 check fall 3 rise 2
    server k8s-master-03 192.168.1.12:6443 check fall 3 rise 2
EOF

systemctl enable haproxy
systemctl start haproxy
systemctl status haproxy
```

#### 配置 DNS 或 /etc/hosts

在所有节点上：

```bash
echo "192.168.1.8 k8s-api.example.com" >> /etc/hosts
```

### 部署步骤

#### 所有节点（所有 Master 和 Worker）

```bash
sudo ./prep-system.sh \
  --hostname $(hostname) \
  --add-host "192.168.1.8 k8s-api.example.com" \
  --add-host "192.168.1.10 k8s-master-01" \
  --add-host "192.168.1.11 k8s-master-02" \
  --add-host "192.168.1.12 k8s-master-03" \
  --add-host "192.168.1.20 k8s-worker-01" \
  --add-host "192.168.1.21 k8s-worker-02"

sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime containerd \
  --use-mirror
```

#### 第一个 Master 节点 (192.168.1.10)

```bash
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --control-plane-endpoint "k8s-api.example.com:6443" \
  --pod-network-cidr 192.168.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --network-plugin calico \
  --upload-certs

# 记录输出的两个命令：
# 1. Master 加入命令（包含 --control-plane 和 --certificate-key）
# 2. Worker 加入命令
```

#### 其他 Master 节点 (192.168.1.11, 192.168.1.12)

```bash
# 使用第一个 Master 输出的命令
kubeadm join k8s-api.example.com:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <certificate-key> \
  --apiserver-advertise-address <当前节点IP>

# 配置 kubectl
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

#### Worker 节点 (192.168.1.20, 192.168.1.21)

```bash
sudo ./join-worker.sh \
  --master k8s-api.example.com:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

#### 验证 HA 配置

```bash
# 在任意 Master 节点
kubectl get nodes

# 应该看到 3 个 Master 节点和 2 个 Worker 节点

# 测试高可用性
# 停止一个 Master 节点
# kubectl 命令应该仍然可以工作
```

## 场景 4: 开发测试单节点集群

单节点集群，Master 同时作为 Worker。

### 环境信息

| 角色 | 主机名 | IP 地址 | 配置 |
|-----|--------|---------|-----|
| Master+Worker | k8s-dev | 192.168.1.100 | 4C8G |

### 部署步骤

```bash
# 1. 系统准备
sudo ./prep-system.sh --hostname k8s-dev

# 2. 安装组件
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime containerd

# 3. 初始化集群
sudo ./init-master.sh \
  --pod-network-cidr 10.244.0.0/16 \
  --network-plugin flannel

# 4. 允许 Master 节点调度 Pod
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 5. 验证
kubectl get nodes
kubectl run test-nginx --image=nginx
kubectl get pods
```

## 场景 5: 使用 Docker 运行时

某些场景需要使用 Docker 而不是 containerd。

### 所有节点

```bash
# 1. 系统准备（同其他场景）
sudo ./prep-system.sh --hostname $(hostname)

# 2. 安装 Docker 和 Kubernetes
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime docker \
  --use-mirror
```

### Master 节点

```bash
# 3. 初始化（无需特殊配置）
sudo ./init-master.sh \
  --pod-network-cidr 192.168.0.0/16 \
  --network-plugin calico
```

### 验证 Docker

```bash
# 查看 Docker 容器
docker ps

# 查看 kubelet 配置
cat /etc/sysconfig/kubelet
# 应该看到: KUBELET_EXTRA_ARGS=--container-runtime=docker
```

## 场景 6: 离线环境部署

在没有互联网访问的环境中部署。

### 准备工作（在有网络的环境）

```bash
# 1. 下载必要的镜像
images=(
  "registry.k8s.io/kube-apiserver:v1.28.0"
  "registry.k8s.io/kube-controller-manager:v1.28.0"
  "registry.k8s.io/kube-scheduler:v1.28.0"
  "registry.k8s.io/kube-proxy:v1.28.0"
  "registry.k8s.io/pause:3.9"
  "registry.k8s.io/etcd:3.5.9-0"
  "registry.k8s.io/coredns:v1.10.1"
  "docker.io/calico/cni:v3.26.1"
  "docker.io/calico/node:v3.26.1"
  "docker.io/calico/kube-controllers:v3.26.1"
)

# 拉取镜像
for img in "${images[@]}"; do
  docker pull $img
done

# 保存镜像
docker save "${images[@]}" -o k8s-images.tar

# 2. 下载 RPM 包
mkdir -p offline-packages
cd offline-packages

# 下载 Kubernetes RPM
yumdownloader --resolve kubeadm-1.28.0 kubelet-1.28.0 kubectl-1.28.0

# 下载 containerd RPM
yumdownloader --resolve containerd.io

# 下载依赖
yumdownloader --resolve socat conntrack ipset ipvsadm

# 打包
cd ..
tar czf offline-packages.tar.gz offline-packages/

# 3. 复制脚本和包到离线环境
```

### 离线环境部署

```bash
# 1. 解压包
tar xzf offline-packages.tar.gz

# 2. 安装 RPM 包
cd offline-packages
yum localinstall -y *.rpm
cd ..

# 3. 加载镜像
ctr -n k8s.io image import k8s-images.tar

# 4. 运行脚本（跳过镜像拉取）
sudo ./prep-system.sh --hostname $(hostname)

sudo ./install-docker-k8s.sh \
  --runtime containerd \
  --skip-pull-images

sudo ./init-master.sh \
  --network-plugin calico \
  --skip-network-plugin  # 手动安装网络插件

# 5. 手动安装网络插件
# 提前下载 calico.yaml 并应用
kubectl apply -f calico.yaml
```

## 🧪 测试和验证

### 基本功能测试

```bash
# 1. 部署测试应用
kubectl create deployment test-nginx --image=nginx --replicas=3

# 2. 暴露服务
kubectl expose deployment test-nginx --port=80 --type=NodePort

# 3. 查看状态
kubectl get deployments
kubectl get pods -o wide
kubectl get svc

# 4. 测试访问
NODE_PORT=$(kubectl get svc test-nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl http://192.168.1.11:${NODE_PORT}

# 5. 测试扩缩容
kubectl scale deployment test-nginx --replicas=5
kubectl get pods

# 6. 清理
kubectl delete deployment test-nginx
kubectl delete svc test-nginx
```

### 网络功能测试

```bash
# 1. 创建测试 Pod
kubectl run test1 --image=busybox --command -- sleep 3600
kubectl run test2 --image=busybox --command -- sleep 3600

# 2. 测试 Pod 间通信
POD1_IP=$(kubectl get pod test1 -o jsonpath='{.status.podIP}')
kubectl exec test2 -- ping -c 4 ${POD1_IP}

# 3. 测试 Service
kubectl create deployment test-svc --image=nginx
kubectl expose deployment test-svc --port=80
kubectl exec test1 -- wget -O- http://test-svc

# 4. 测试 DNS
kubectl exec test1 -- nslookup kubernetes.default

# 5. 清理
kubectl delete pod test1 test2
kubectl delete deployment test-svc
kubectl delete svc test-svc
```

### 存储功能测试

```bash
# 1. 创建 PV
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: test-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /mnt/data
EOF

# 2. 创建 PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# 3. 使用 PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-storage
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# 4. 验证
kubectl exec test-storage -- df -h | grep /data
kubectl exec test-storage -- sh -c "echo 'test' > /data/test.txt"
kubectl exec test-storage -- cat /data/test.txt

# 5. 清理
kubectl delete pod test-storage
kubectl delete pvc test-pvc
kubectl delete pv test-pv
```

## 📊 性能测试

### 负载测试

```bash
# 部署高负载应用
kubectl create deployment load-test --image=nginx --replicas=10
kubectl expose deployment load-test --port=80 --type=NodePort

# 查看资源使用
kubectl top nodes
kubectl top pods

# 清理
kubectl delete deployment load-test
kubectl delete svc load-test
```

## 🔄 迁移场景

### 从 Docker 迁移到 containerd

```bash
# 1. 在 Worker 节点上驱逐 Pod
kubectl drain <worker-node> --ignore-daemonsets --delete-emptydir-data

# 2. 在 Worker 节点上重置
kubeadm reset -f
systemctl stop docker
systemctl disable docker

# 3. 重新安装
sudo ./install-docker-k8s.sh --runtime containerd

# 4. 重新加入
sudo ./join-worker.sh --master-ssh root@<master-ip>

# 5. 在 Master 上恢复调度
kubectl uncordon <worker-node>
```

---

**更多示例和场景，请参考项目 Wiki 或联系技术支持。**
