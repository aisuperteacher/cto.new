# Kubernetes 集群故障排查指南

本文档提供详细的故障排查步骤和解决方案。

## 📋 目录

- [日志查看](#日志查看)
- [常见问题](#常见问题)
  - [系统准备阶段](#系统准备阶段)
  - [安装阶段](#安装阶段)
  - [集群初始化阶段](#集群初始化阶段)
  - [节点加入阶段](#节点加入阶段)
  - [网络问题](#网络问题)
  - [存储问题](#存储问题)
- [诊断工具](#诊断工具)
- [恢复步骤](#恢复步骤)

## 📝 日志查看

### 部署脚本日志

所有脚本日志保存在 `/var/log/k8s-deploy/` 目录：

```bash
# 查看最新日志文件
ls -lht /var/log/k8s-deploy/ | head

# 查看系统准备日志
cat /var/log/k8s-deploy/prep-system-*.log

# 查看安装日志
cat /var/log/k8s-deploy/install-docker-k8s-*.log

# 查看 Master 初始化日志
cat /var/log/k8s-deploy/init-master-*.log

# 查看 Worker 加入日志
cat /var/log/k8s-deploy/join-worker-*.log

# 实时查看日志（如果脚本正在运行）
tail -f /var/log/k8s-deploy/*.log
```

### 系统组件日志

```bash
# kubelet 日志
journalctl -u kubelet -f
journalctl -u kubelet --since "1 hour ago"
journalctl -u kubelet -n 100 --no-pager

# containerd 日志
journalctl -u containerd -f
journalctl -u containerd --since "10 minutes ago"

# Docker 日志（如果使用 Docker）
journalctl -u docker -f

# 查看系统日志
tail -f /var/log/messages
dmesg -T | tail -100
```

### Kubernetes 组件日志

```bash
# API Server 日志
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l component=kube-apiserver -o name | head -1)

# Controller Manager 日志
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l component=kube-controller-manager -o name | head -1)

# Scheduler 日志
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l component=kube-scheduler -o name | head -1)

# CoreDNS 日志
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l k8s-app=kube-dns -o name | head -1)

# 网络插件日志（Calico）
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l k8s-app=calico-node -o name | head -1)

# 网络插件日志（Flannel）
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l app=flannel -o name | head -1)
```

## 🔧 常见问题

### 系统准备阶段

#### 问题 1: SELinux 无法禁用

**症状：**
```
setenforce: SELinux is disabled
```

**原因：** SELinux 已经禁用或配置文件不存在

**解决方案：**
```bash
# 检查 SELinux 状态
getenforce

# 如果是 Permissive 或 Disabled，可以继续
# 如果是 Enforcing，检查配置文件
cat /etc/selinux/config

# 手动设置
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
reboot
```

#### 问题 2: swap 禁用失败

**症状：**
```
swapoff: /dev/dm-1: swapoff failed: Cannot allocate memory
```

**解决方案：**
```bash
# 强制禁用所有 swap
swapoff -a

# 检查 swap 状态
swapon -s
free -h

# 确保 fstab 中 swap 已注释
cat /etc/fstab | grep swap

# 如果仍有问题，重启系统
reboot
```

#### 问题 3: 内核模块加载失败

**症状：**
```
modprobe: ERROR: could not insert 'br_netfilter': Operation not permitted
```

**原因：** 缺少内核模块或权限不足

**解决方案：**
```bash
# 检查模块是否存在
modinfo br_netfilter
modinfo overlay

# 以 root 权限加载
sudo modprobe br_netfilter
sudo modprobe overlay

# 验证加载
lsmod | grep br_netfilter
lsmod | grep overlay

# 如果模块不存在，更新内核
yum update kernel -y
reboot
```

#### 问题 4: 时间同步失败

**症状：**
```
chronyd: Source 0.centos.pool.ntp.org offline
```

**原因：** 无法访问 NTP 服务器

**解决方案：**
```bash
# 检查网络连接
ping -c 4 0.centos.pool.ntp.org

# 使用其他 NTP 服务器
cat > /etc/chrony.conf <<EOF
server ntp.aliyun.com iburst
server ntp1.aliyun.com iburst
server time1.cloud.tencent.com iburst
EOF

# 重启 chronyd
systemctl restart chronyd

# 验证同步
chronyc tracking
chronyc sources -v

# 手动同步时间
chronyd -q 'server 0.centos.pool.ntp.org iburst'
```

### 安装阶段

#### 问题 5: 无法安装 Docker/containerd

**症状：**
```
Error: Package: docker-ce-20.10.x requires containerd.io >= 1.4.1
```

**原因：** 依赖版本冲突

**解决方案：**
```bash
# 卸载旧版本
yum remove -y docker docker-client docker-client-latest docker-common \
  docker-latest docker-latest-logrotate docker-logrotate docker-engine \
  containerd runc

# 清理缓存
yum clean all
rm -rf /var/cache/yum

# 重新安装
yum install -y containerd.io
yum install -y docker-ce docker-ce-cli
```

#### 问题 6: containerd 启动失败

**症状：**
```
Failed to start containerd container runtime
```

**解决方案：**
```bash
# 检查配置文件
containerd config default > /etc/containerd/config.toml

# 检查日志
journalctl -u containerd -n 50 --no-pager

# 检查是否有冲突的服务
systemctl status docker

# 重新生成配置
rm /etc/containerd/config.toml
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 重启服务
systemctl daemon-reload
systemctl restart containerd
systemctl status containerd
```

#### 问题 7: kubeadm 安装失败

**症状：**
```
Error: No matching package to install: 'kubeadm-1.28.0'
```

**原因：** 仓库配置错误或版本不可用

**解决方案：**
```bash
# 检查仓库配置
cat /etc/yum.repos.d/kubernetes.repo

# 清理缓存
yum clean all
yum makecache

# 查看可用版本
yum list available --showduplicates | grep kubeadm

# 安装最新版本
yum install -y kubeadm kubelet kubectl --disableexcludes=kubernetes

# 或指定版本
yum install -y kubeadm-1.28.0 kubelet-1.28.0 kubectl-1.28.0 --disableexcludes=kubernetes
```

#### 问题 8: 镜像拉取失败

**症状：**
```
Failed to pull image "registry.k8s.io/pause:3.9": rpc error: code = Unknown
```

**原因：** 网络问题或镜像仓库无法访问

**解决方案：**
```bash
# 检查网络连接
ping -c 4 registry.k8s.io

# 使用镜像加速器（重新运行安装脚本）
sudo ./install-docker-k8s.sh --use-mirror

# 手动配置 containerd 镜像加速
cat >> /etc/containerd/config.toml <<EOF
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
  endpoint = ["https://registry.cn-hangzhou.aliyuncs.com/google_containers"]
EOF

systemctl restart containerd

# 手动拉取镜像
ctr -n k8s.io image pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.9
ctr -n k8s.io image tag registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.9 registry.k8s.io/pause:3.9
```

### 集群初始化阶段

#### 问题 9: kubeadm init 失败

**症状：**
```
[ERROR Port-6443]: Port 6443 is in use
```

**原因：** 端口被占用或之前初始化失败

**解决方案：**
```bash
# 检查端口占用
netstat -tlnp | grep 6443
lsof -i :6443

# 重置 kubeadm
kubeadm reset -f

# 清理残留
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf $HOME/.kube

# 清理网络配置
rm -rf /etc/cni/net.d

# 重新初始化
sudo ./init-master.sh
```

#### 问题 10: etcd 启动失败

**症状：**
```
[ERROR Etcd]: etcd cluster is not healthy
```

**解决方案：**
```bash
# 检查 etcd Pod
kubectl get pods -n kube-system | grep etcd

# 查看 etcd 日志
kubectl logs -n kube-system etcd-$(hostname) --previous

# 检查 etcd 数据目录
ls -la /var/lib/etcd

# 清理并重新初始化
kubeadm reset -f
rm -rf /var/lib/etcd
sudo ./init-master.sh
```

#### 问题 11: API Server 无法访问

**症状：**
```
The connection to the server localhost:6443 was refused
```

**解决方案：**
```bash
# 检查 API Server Pod
kubectl get pods -n kube-system | grep apiserver
docker ps | grep apiserver

# 查看 API Server 日志
journalctl -u kubelet | grep apiserver

# 检查证书
ls -la /etc/kubernetes/pki

# 检查配置文件
cat /etc/kubernetes/admin.conf

# 检查 API Server 监听
netstat -tlnp | grep 6443

# 重启 kubelet
systemctl restart kubelet
```

#### 问题 12: CoreDNS Pod 无法启动

**症状：**
```
coredns-xxx  0/1  CrashLoopBackOff
```

**解决方案：**
```bash
# 查看 Pod 详情
kubectl describe pod -n kube-system coredns-xxx

# 查看日志
kubectl logs -n kube-system coredns-xxx

# 常见原因：SELinux 未禁用
getenforce
setenforce 0

# 或者 loop 检测问题，编辑 CoreDNS ConfigMap
kubectl edit cm coredns -n kube-system
# 移除或注释 'loop' 插件

# 重启 CoreDNS
kubectl delete pod -n kube-system -l k8s-app=kube-dns
```

### 节点加入阶段

#### 问题 13: 令牌过期

**症状：**
```
[ERROR FileContent--token]: the provided token is invalid
```

**原因：** 令牌有效期默认为 24 小时

**解决方案：**
```bash
# 在 Master 节点生成新令牌
kubeadm token create --print-join-command

# 或者创建新令牌和证书哈希
TOKEN=$(kubeadm token create)
CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //')

echo "kubeadm join <master-ip>:6443 --token ${TOKEN} --discovery-token-ca-cert-hash sha256:${CA_CERT_HASH}"
```

#### 问题 14: 无法连接到 Master

**症状：**
```
[ERROR Dial]: connection refused
```

**解决方案：**
```bash
# 检查网络连接
ping <master-ip>
telnet <master-ip> 6443

# 检查防火墙
systemctl status firewalld
firewall-cmd --list-all

# 临时关闭防火墙测试
systemctl stop firewalld

# 在 Master 节点检查 API Server
systemctl status kubelet
kubectl get nodes

# 检查 Master IP 配置
kubectl cluster-info
```

#### 问题 15: 证书验证失败

**症状：**
```
[ERROR CertificateVerification]: Failed to verify CA certificate
```

**解决方案：**
```bash
# 在 Master 节点重新获取证书哈希
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //'

# 使用正确的哈希值重新加入
sudo ./join-worker.sh \
  --master <master-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<correct-hash>
```

#### 问题 16: kubelet 无法启动

**症状：**
```
kubelet: Failed to start kubelet
```

**解决方案：**
```bash
# 查看 kubelet 状态
systemctl status kubelet -l

# 查看详细日志
journalctl -u kubelet -n 100 --no-pager

# 常见原因1: swap 未禁用
swapoff -a
systemctl restart kubelet

# 常见原因2: cgroup 驱动不匹配
# 检查 Docker/containerd 配置
docker info | grep Cgroup
crictl info | grep -i cgroup

# 配置 kubelet cgroup 驱动
cat > /etc/sysconfig/kubelet <<EOF
KUBELET_EXTRA_ARGS=--cgroup-driver=systemd
EOF

systemctl daemon-reload
systemctl restart kubelet

# 常见原因3: 容器运行时未启动
systemctl status containerd
systemctl status docker
systemctl restart containerd
systemctl restart kubelet
```

### 网络问题

#### 问题 17: Pod 无法获取 IP

**症状：**
```
pod-xxx  0/1  ContainerCreating
```

**解决方案：**
```bash
# 查看 Pod 详情
kubectl describe pod <pod-name>

# 检查网络插件
kubectl get pods -n kube-system | grep -E "calico|flannel"

# Calico 故障排查
kubectl logs -n kube-system -l k8s-app=calico-node

# 检查 CNI 配置
ls -la /etc/cni/net.d/

# 检查 CNI 插件
ls -la /opt/cni/bin/

# 重启网络插件
kubectl delete pod -n kube-system -l k8s-app=calico-node
# 或
kubectl delete pod -n kube-system -l app=flannel

# 检查 IP 池
kubectl get ippool -o wide
```

#### 问题 18: Pod 间网络不通

**症状：**
无法在 Pod 间通信

**解决方案：**
```bash
# 创建测试 Pod
kubectl run test1 --image=busybox --command -- sleep 3600
kubectl run test2 --image=busybox --command -- sleep 3600

# 获取 Pod IP
POD1_IP=$(kubectl get pod test1 -o jsonpath='{.status.podIP}')
POD2_IP=$(kubectl get pod test2 -o jsonpath='{.status.podIP}')

# 测试连通性
kubectl exec test1 -- ping -c 4 ${POD2_IP}

# 如果不通，检查：
# 1. 网络插件状态
kubectl get pods -n kube-system -o wide | grep -E "calico|flannel"

# 2. 路由规则
ip route show

# 3. iptables 规则
iptables -t nat -L -n | grep KUBE

# 4. 节点间网络
ping <worker-node-ip>

# 5. 检查防火墙
iptables -L -n

# 清理测试 Pod
kubectl delete pod test1 test2
```

#### 问题 19: Service 无法访问

**症状：**
无法访问 Service ClusterIP

**解决方案：**
```bash
# 查看 Service
kubectl get svc
kubectl describe svc <service-name>

# 查看 Endpoints
kubectl get endpoints <service-name>

# 如果 Endpoints 为空，检查 Pod 标签
kubectl get pods --show-labels
kubectl describe svc <service-name> | grep Selector

# 测试 Service DNS
kubectl run test --image=busybox --rm -it -- nslookup <service-name>

# 测试 Service IP
kubectl run test --image=busybox --rm -it -- wget -O- <service-ip>:<port>

# 检查 kube-proxy
kubectl get pods -n kube-system | grep kube-proxy
kubectl logs -n kube-system <kube-proxy-pod>

# 检查 iptables 规则
iptables -t nat -L -n | grep <service-name>
```

#### 问题 20: DNS 解析失败

**症状：**
```
nslookup: can't resolve 'kubernetes.default'
```

**解决方案：**
```bash
# 检查 CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# 检查 CoreDNS Service
kubectl get svc -n kube-system kube-dns
kubectl describe svc -n kube-system kube-dns

# 检查 DNS 配置
kubectl exec -it <any-pod> -- cat /etc/resolv.conf

# 测试 DNS
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default

# 重启 CoreDNS
kubectl delete pod -n kube-system -l k8s-app=kube-dns

# 检查 SELinux（常见原因）
getenforce
# 如果是 Enforcing，禁用它
setenforce 0
```

### 存储问题

#### 问题 21: PV/PVC 绑定失败

**症状：**
```
PVC status: Pending
```

**解决方案：**
```bash
# 查看 PVC 详情
kubectl describe pvc <pvc-name>

# 查看可用的 PV
kubectl get pv

# 检查 StorageClass
kubectl get storageclass

# 常见原因1: 没有匹配的 PV
# 创建匹配的 PV 或使用动态供应

# 常见原因2: 访问模式不匹配
# 检查 PV 和 PVC 的 accessModes

# 常见原因3: 存储大小不匹配
# PV 容量必须 >= PVC 请求

# 常见原因4: StorageClass 不匹配
# 确保 PVC 的 storageClassName 与 PV 匹配
```

## 🛠️ 诊断工具

### 系统诊断脚本

创建诊断脚本 `diagnose.sh`:

```bash
#!/bin/bash

echo "=== 系统信息 ==="
uname -a
cat /etc/os-release

echo -e "\n=== 内存信息 ==="
free -h

echo -e "\n=== 磁盘信息 ==="
df -h

echo -e "\n=== Swap 状态 ==="
swapon -s

echo -e "\n=== SELinux 状态 ==="
getenforce

echo -e "\n=== 防火墙状态 ==="
systemctl status firewalld --no-pager

echo -e "\n=== 容器运行时状态 ==="
systemctl status containerd --no-pager
systemctl status docker --no-pager 2>/dev/null

echo -e "\n=== kubelet 状态 ==="
systemctl status kubelet --no-pager

echo -e "\n=== 节点状态 ==="
kubectl get nodes -o wide

echo -e "\n=== Pod 状态 ==="
kubectl get pods -A

echo -e "\n=== 网络插件状态 ==="
kubectl get pods -n kube-system | grep -E "calico|flannel"

echo -e "\n=== 最近的 kubelet 日志 ==="
journalctl -u kubelet -n 20 --no-pager
```

### 网络诊断

```bash
# 创建网络诊断 Pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: net-debug
spec:
  containers:
  - name: net-debug
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
EOF

# 进入 Pod 进行诊断
kubectl exec -it net-debug -- bash

# 在 Pod 中执行
# 测试 DNS
nslookup kubernetes.default

# 测试网络连接
ping <pod-ip>
telnet <service-ip> <port>
curl http://<service-name>

# 查看路由
ip route

# 查看网络接口
ip addr

# 抓包
tcpdump -i any -nn host <ip>
```

## 🔄 恢复步骤

### 完全重置节点

```bash
# 1. 重置 kubeadm
kubeadm reset -f

# 2. 停止服务
systemctl stop kubelet
systemctl stop containerd
systemctl stop docker 2>/dev/null

# 3. 清理配置和数据
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/etcd
rm -rf /etc/cni/net.d
rm -rf $HOME/.kube

# 4. 清理网络
ip link delete cni0 2>/dev/null
ip link delete flannel.1 2>/dev/null
ip link delete tunl0 2>/dev/null

# 5. 清理 iptables
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# 6. 清理 IPVS
ipvsadm --clear 2>/dev/null

# 7. 重启服务
systemctl start containerd
systemctl start kubelet

# 8. 重新部署
# Master 节点
sudo ./init-master.sh

# Worker 节点
sudo ./join-worker.sh --master-ssh root@<master-ip>
```

### 重建 Master 节点

```bash
# 1. 备份重要数据
mkdir -p /backup
cp -r /etc/kubernetes/pki /backup/pki
cp /etc/kubernetes/admin.conf /backup/

# 2. 备份 etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 3. 重置节点
kubeadm reset -f

# 4. 清理
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /etc/cni/net.d

# 5. 恢复证书（如果需要保留证书）
mkdir -p /etc/kubernetes
cp -r /backup/pki /etc/kubernetes/

# 6. 重新初始化
sudo ./init-master.sh
```

## 📞 获取帮助

如果以上方法都无法解决问题：

1. 收集完整的日志和诊断信息
2. 记录详细的错误信息和操作步骤
3. 查看 Kubernetes 官方文档
4. 在社区论坛寻求帮助

### 有用的资源

- Kubernetes 官方文档: https://kubernetes.io/docs/
- Kubernetes GitHub Issues: https://github.com/kubernetes/kubernetes/issues
- Stack Overflow: https://stackoverflow.com/questions/tagged/kubernetes
- Kubernetes Slack: https://kubernetes.slack.com/

---

**记住**: 大多数问题都可以通过查看日志和仔细阅读错误信息来解决！
