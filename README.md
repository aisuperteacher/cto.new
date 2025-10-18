# Kubernetes 集群自动化部署脚本

本项目提供了一套完整的 Shell 脚本，用于在 CentOS 7/8 系统上自动化部署 Kubernetes 集群。脚本包含严格的错误处理、详细的日志输出和全面的环境检查。

## 📋 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [脚本说明](#脚本说明)
- [使用指南](#使用指南)
- [网络插件选择](#网络插件选择)
- [故障排查](#故障排查)
- [最佳实践](#最佳实践)

## ✨ 功能特性

- ✅ **完整的生命周期管理**：从系统准备到集群初始化的全流程自动化
- ✅ **多系统支持**：支持 CentOS 7/8、Rocky Linux 8、AlmaLinux 8
- ✅ **多网络插件**：支持 Calico 和 Flannel 网络插件
- ✅ **灵活的运行时**：支持 Docker 和 containerd 容器运行时
- ✅ **严格的错误处理**：每个关键操作都有错误检查和回滚机制
- ✅ **详细的日志记录**：所有操作记录到 `/var/log/k8s-deploy/` 目录
- ✅ **环境验证**：自动检查系统资源、网络连接和依赖项
- ✅ **镜像加速支持**：支持国内镜像加速器，加快部署速度
- ✅ **交互式模式**：支持交互式和非交互式两种运行模式

## 🖥️ 系统要求

### 硬件要求

**Master 节点（控制平面）**
- CPU: 2 核心或以上
- 内存: 2GB 或以上
- 硬盘: 20GB 或以上

**Worker 节点**
- CPU: 2 核心或以上
- 内存: 2GB 或以上
- 硬盘: 20GB 或以上

### 软件要求

- **操作系统**: CentOS 7/8, Rocky Linux 8, 或 AlmaLinux 8
- **权限**: root 或 sudo 权限
- **网络**: 所有节点需要能够相互通信
- **防火墙**: 建议关闭或配置相应端口

### 网络端口要求

**Master 节点**
- 6443: Kubernetes API Server
- 2379-2380: etcd 服务
- 10250: Kubelet API
- 10251: kube-scheduler
- 10252: kube-controller-manager

**Worker 节点**
- 10250: Kubelet API
- 30000-32767: NodePort 服务

## 🚀 快速开始

### 1. 下载脚本

```bash
# 克隆仓库或下载脚本到所有节点
git clone <repository-url>
cd scripts/

# 确保脚本有执行权限
chmod +x *.sh
```

### 2. 准备系统（所有节点）

在所有 Master 和 Worker 节点上运行：

```bash
sudo ./prep-system.sh --hostname k8s-master-01 \
  --add-host "192.168.1.10 k8s-master-01" \
  --add-host "192.168.1.11 k8s-worker-01" \
  --add-host "192.168.1.12 k8s-worker-02"
```

**如果 SELinux 配置有更新，建议重启系统。**

### 3. 安装 Docker 和 Kubernetes（所有节点）

在所有节点上安装容器运行时和 Kubernetes 组件：

```bash
# 使用 containerd（推荐）
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime containerd \
  --use-mirror

# 或使用 Docker
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime docker \
  --use-mirror
```

### 4. 初始化 Master 节点

仅在 Master 节点上运行：

```bash
# 使用 Calico 网络插件
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --pod-network-cidr 10.244.0.0/16 \
  --network-plugin calico

# 或使用 Flannel 网络插件
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --pod-network-cidr 10.244.0.0/16 \
  --network-plugin flannel
```

初始化完成后，脚本会生成 Worker 节点加入命令，保存在：
```
/var/log/k8s-deploy/kubeadm-join-command.sh
```

### 5. 加入 Worker 节点

在每个 Worker 节点上运行：

```bash
# 方式一：使用 SSH 自动获取加入信息（推荐）
sudo ./join-worker.sh --master-ssh root@192.168.1.10

# 方式二：手动指定加入参数
sudo ./join-worker.sh \
  --master 192.168.1.10:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# 方式三：使用完整的加入命令
sudo ./join-worker.sh \
  --join-command "kubeadm join 192.168.1.10:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"
```

### 6. 验证集群

在 Master 节点上运行：

```bash
# 查看节点状态
kubectl get nodes

# 查看所有 Pod
kubectl get pods -A

# 查看集群信息
kubectl cluster-info
```

## 📚 脚本说明

### prep-system.sh - 系统准备脚本

准备系统环境以支持 Kubernetes 部署。

**主要功能：**
- 检测和验证操作系统版本
- 禁用 SELinux 和防火墙
- 配置内核参数和模块加载
- 禁用 swap
- 配置时间同步（chrony）
- 设置主机名和 hosts 文件
- 配置 IPVS 模块
- 系统优化（资源限制等）

**常用选项：**
```bash
--hostname <name>        # 设置系统主机名
--add-host <ip hostname> # 添加主机条目到 /etc/hosts
--skip-chrony            # 跳过时间同步配置
--skip-reboot-check      # 跳过重启检查提示
```

**使用示例：**
```bash
# 基本用法
sudo ./prep-system.sh

# 完整配置
sudo ./prep-system.sh \
  --hostname k8s-master-01 \
  --add-host "192.168.1.10 k8s-master-01" \
  --add-host "192.168.1.11 k8s-worker-01"
```

### install-docker-k8s.sh - Docker 和 Kubernetes 安装脚本

安装容器运行时和 Kubernetes 组件。

**主要功能：**
- 安装 Docker 或 containerd
- 配置容器运行时参数
- 安装 kubeadm、kubelet、kubectl
- 配置 cgroup 驱动
- 配置镜像加速器
- 预拉取必要的镜像

**常用选项：**
```bash
--k8s-version <version>  # 指定 Kubernetes 版本（默认: 1.28.0）
--runtime <type>         # 容器运行时 docker|containerd（默认: containerd）
--use-mirror             # 使用镜像加速器（阿里云）
--skip-pull-images       # 跳过镜像预拉取
--docker-version <ver>   # 指定 Docker 版本（可选）
```

**使用示例：**
```bash
# 使用 containerd（推荐）
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime containerd \
  --use-mirror

# 使用 Docker
sudo ./install-docker-k8s.sh \
  --k8s-version 1.28.0 \
  --runtime docker

# 跳过镜像预拉取
sudo ./install-docker-k8s.sh \
  --runtime containerd \
  --skip-pull-images
```

### init-master.sh - Master 节点初始化脚本

初始化 Kubernetes Master 节点（控制平面）。

**主要功能：**
- 执行 kubeadm init 初始化集群
- 配置 kubectl 访问权限
- 安装网络插件（Calico 或 Flannel）
- 生成 Worker 节点加入命令
- 验证集群状态

**常用选项：**
```bash
--apiserver-advertise-address <ip>  # API Server 监听地址（默认: 自动检测）
--pod-network-cidr <cidr>           # Pod 网络 CIDR（默认: 10.244.0.0/16）
--service-cidr <cidr>               # Service CIDR（默认: 10.96.0.0/12）
--network-plugin <plugin>           # 网络插件 calico|flannel（默认: calico）
--k8s-version <version>             # Kubernetes 版本（默认: 自动检测）
--control-plane-endpoint <endpoint> # 控制平面端点（HA 场景使用）
--upload-certs                      # 上传证书到集群（HA 场景使用）
--skip-network-plugin               # 跳过网络插件安装
```

**使用示例：**
```bash
# 基本用法（使用 Calico）
sudo ./init-master.sh

# 使用 Flannel
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --pod-network-cidr 10.244.0.0/16 \
  --network-plugin flannel

# HA 模式（多 Master）
sudo ./init-master.sh \
  --apiserver-advertise-address 192.168.1.10 \
  --control-plane-endpoint "k8s-cluster.example.com:6443" \
  --upload-certs
```

### join-worker.sh - Worker 节点加入脚本

将节点加入到 Kubernetes 集群作为 Worker 节点。

**主要功能：**
- 验证系统环境和依赖
- 执行节点加入操作
- 配置节点标签
- 验证加入状态

**常用选项：**
```bash
--master <ip:port>                    # Master 节点地址
--token <token>                       # 加入令牌
--discovery-token-ca-cert-hash <hash> # CA 证书哈希
--join-command <command>              # 完整的 kubeadm join 命令
--master-ssh <user@host>              # Master 节点 SSH 地址（自动获取）
--node-label <key=value>              # 添加节点标签（可多次使用）
--skip-verify                         # 跳过加入后验证
```

**使用示例：**
```bash
# 使用 SSH 自动获取（推荐）
sudo ./join-worker.sh --master-ssh root@192.168.1.10

# 手动指定参数
sudo ./join-worker.sh \
  --master 192.168.1.10:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:xxx

# 使用完整命令
sudo ./join-worker.sh \
  --join-command "kubeadm join 192.168.1.10:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"

# 添加节点标签
sudo ./join-worker.sh \
  --master-ssh root@192.168.1.10 \
  --node-label "node-role.kubernetes.io/worker=" \
  --node-label "zone=us-west-1"

# 交互式模式（无参数运行）
sudo ./join-worker.sh
```

## 🌐 网络插件选择

### Calico（默认推荐）

**优点：**
- 功能强大，支持网络策略（NetworkPolicy）
- 性能优秀，支持大规模集群
- 支持 BGP 路由
- 灵活的 IP 管理

**适用场景：**
- 需要网络策略功能
- 大规模生产环境
- 需要高级网络功能

**配置：**
```bash
sudo ./init-master.sh \
  --network-plugin calico \
  --pod-network-cidr 192.168.0.0/16
```

### Flannel

**优点：**
- 简单易用，配置简单
- 性能稳定
- 社区活跃

**适用场景：**
- 小型集群
- 测试开发环境
- 不需要复杂网络策略

**配置：**
```bash
sudo ./init-master.sh \
  --network-plugin flannel \
  --pod-network-cidr 10.244.0.0/16
```

### 网络 CIDR 规划建议

| 组件 | 默认 CIDR | 可调整范围 |
|------|-----------|-----------|
| Pod 网络（Calico） | 192.168.0.0/16 | 任意私有网段 |
| Pod 网络（Flannel） | 10.244.0.0/16 | 任意私有网段 |
| Service 网络 | 10.96.0.0/12 | 任意私有网段 |

**注意事项：**
- Pod 网络、Service 网络和节点网络不能重叠
- 确保 CIDR 范围足够大，能容纳所有 Pod 和 Service
- 不同网络插件可能有不同的 CIDR 要求

## 🔧 故障排查

### 日志位置

所有脚本日志保存在 `/var/log/k8s-deploy/` 目录：

```bash
# 查看最新日志
ls -lht /var/log/k8s-deploy/

# 查看系统准备日志
cat /var/log/k8s-deploy/prep-system-*.log

# 查看安装日志
cat /var/log/k8s-deploy/install-docker-k8s-*.log

# 查看 Master 初始化日志
cat /var/log/k8s-deploy/init-master-*.log

# 查看 Worker 加入日志
cat /var/log/k8s-deploy/join-worker-*.log
```

### 常见问题

#### 1. kubelet 无法启动

```bash
# 查看 kubelet 状态
systemctl status kubelet

# 查看 kubelet 日志
journalctl -u kubelet -f

# 常见原因：
# - swap 未禁用
# - 容器运行时未启动
# - cgroup 驱动配置不匹配
```

#### 2. Pod 无法启动或网络不通

```bash
# 查看 Pod 状态
kubectl get pods -A

# 查看 Pod 详情
kubectl describe pod <pod-name> -n <namespace>

# 检查网络插件
kubectl get pods -n kube-system | grep -E "calico|flannel"

# 常见原因：
# - 网络插件未正确安装
# - 防火墙规则阻止通信
# - Pod 网络 CIDR 配置错误
```

#### 3. 节点无法加入集群

```bash
# 检查网络连接
ping <master-ip>
telnet <master-ip> 6443

# 检查证书哈希
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //'

# 重新生成加入令牌（在 Master 节点）
kubeadm token create --print-join-command

# 常见原因：
# - 令牌过期（24小时有效期）
# - 网络不通
# - 时间不同步
```

#### 4. 镜像拉取失败

```bash
# 检查容器运行时
systemctl status containerd
systemctl status docker

# 手动拉取镜像测试
ctr -n k8s.io image pull registry.k8s.io/pause:3.9
# 或
docker pull registry.k8s.io/pause:3.9

# 解决方案：
# - 使用 --use-mirror 参数启用镜像加速
# - 配置 HTTP 代理
# - 使用私有镜像仓库
```

### 系统命令参考

```bash
# 查看集群状态
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# 查看组件日志
journalctl -u kubelet -f
journalctl -u containerd -f
journalctl -u docker -f

# 检查容器运行时
crictl ps -a
crictl images
docker ps -a
docker images

# 重置节点（重新开始）
kubeadm reset -f
rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd

# 重新生成证书
kubeadm certs renew all

# 查看令牌列表
kubeadm token list
```

## 💡 最佳实践

### 1. 部署前准备

- ✅ 规划好网络 CIDR，避免与现有网络冲突
- ✅ 准备好所有节点的 IP 地址和主机名
- ✅ 确保所有节点时间同步
- ✅ 备份重要数据
- ✅ 准备好镜像加速器或私有仓库（国内环境）

### 2. 系统配置

- ✅ 使用 SSD 硬盘提高性能
- ✅ 为 etcd 数据目录单独挂载磁盘
- ✅ 配置合适的 DNS 服务器
- ✅ 禁用不必要的系统服务

### 3. 安全建议

- ✅ 使用防火墙限制访问（只开放必要端口）
- ✅ 定期更新系统和 Kubernetes 组件
- ✅ 启用 RBAC 授权
- ✅ 使用网络策略限制 Pod 间通信
- ✅ 定期备份 etcd 数据

### 4. 高可用配置

对于生产环境，建议配置高可用（HA）集群：

- 至少 3 个 Master 节点（奇数个）
- 使用负载均衡器作为控制平面入口
- 使用外部 etcd 集群或堆叠式 etcd

```bash
# HA 模式初始化第一个 Master
sudo ./init-master.sh \
  --control-plane-endpoint "lb.example.com:6443" \
  --upload-certs \
  --network-plugin calico

# 其他 Master 节点加入
kubeadm join lb.example.com:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <certificate-key>
```

### 5. 监控和日志

- ✅ 部署 Prometheus + Grafana 监控集群
- ✅ 使用 ELK/EFK 收集日志
- ✅ 配置告警规则
- ✅ 定期检查集群健康状态

### 6. 资源规划

根据工作负载合理规划资源：

| 集群规模 | Master CPU | Master 内存 | Worker CPU | Worker 内存 |
|---------|-----------|------------|-----------|------------|
| 小型（<50节点） | 2核 | 4GB | 2核 | 4GB |
| 中型（50-250节点） | 4核 | 8GB | 4核 | 8GB |
| 大型（>250节点） | 8核 | 16GB | 8核 | 16GB+ |

## 📝 版本兼容性

| 组件 | 版本 | 状态 |
|------|------|------|
| CentOS | 7.x | ✅ 支持 |
| CentOS | 8.x | ✅ 支持 |
| Rocky Linux | 8.x | ✅ 支持 |
| AlmaLinux | 8.x | ✅ 支持 |
| Kubernetes | 1.24+ | ✅ 支持 |
| Kubernetes | 1.28.x | ✅ 推荐 |
| Docker | 20.10+ | ✅ 支持 |
| containerd | 1.6+ | ✅ 推荐 |
| Calico | 3.26+ | ✅ 支持 |
| Flannel | 0.22+ | ✅ 支持 |

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证。

## 📮 联系方式

- 作者: Kubernetes Automation Team
- 版本: 1.0.0
- 最后更新: 2024

---

**祝您部署顺利！🎉**
