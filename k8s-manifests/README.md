# Kubernetes 配置清单

本目录包含用于部署示例应用的 Kubernetes 配置文件，涵盖了常见的资源类型和网络策略配置。

## 目录结构

```
k8s-manifests/
├── README.md                           # 本文件
├── deployment.yaml                     # Deployment 配置
├── service.yaml                        # Service 配置（ClusterIP、NodePort、LoadBalancer）
├── ingress.yaml                        # Ingress 配置和 TLS
├── persistent-volume.yaml              # PersistentVolume 配置
├── persistent-volume-claim.yaml        # PersistentVolumeClaim 配置
├── storage-class.yaml                  # StorageClass 配置
└── network-policies/
    ├── calico-example.yaml             # Calico 网络策略示例
    └── flannel-example.yaml            # Flannel 配置和标准网络策略
```

## 快速开始

### 1. 前置要求

- Kubernetes 集群（v1.20+）
- kubectl 命令行工具
- 镜像已构建并推送到镜像仓库

### 2. 创建存储资源

```bash
# 创建 StorageClass
kubectl apply -f storage-class.yaml

# 创建 PersistentVolume（如果使用静态配置）
kubectl apply -f persistent-volume.yaml

# 创建 PersistentVolumeClaim
kubectl apply -f persistent-volume-claim.yaml

# 查看存储状态
kubectl get storageclass
kubectl get pv
kubectl get pvc
```

### 3. 部署应用

```bash
# 部署应用
kubectl apply -f deployment.yaml

# 查看部署状态
kubectl get deployments
kubectl get pods
kubectl describe deployment sample-app
```

### 4. 创建服务

```bash
# 创建 Service（根据需要选择一种或多种）
kubectl apply -f service.yaml

# 查看服务
kubectl get services
```

### 5. 配置 Ingress（可选）

```bash
# 确保已安装 Ingress Controller（如 nginx-ingress）
# 创建 Ingress
kubectl apply -f ingress.yaml

# 查看 Ingress
kubectl get ingress
kubectl describe ingress sample-app-ingress
```

### 6. 配置网络策略（可选）

```bash
# 如果使用 Calico
kubectl apply -f network-policies/calico-example.yaml

# 如果使用 Flannel 或其他 CNI
kubectl apply -f network-policies/flannel-example.yaml

# 查看网络策略
kubectl get networkpolicies
```

## 配置文件详解

### Deployment（deployment.yaml）

- **副本数**：3 个副本实现高可用
- **滚动更新策略**：maxSurge=1, maxUnavailable=1
- **资源限制**：
  - 请求：128Mi 内存，100m CPU
  - 限制：256Mi 内存，200m CPU
- **健康检查**：
  - 存活探针（Liveness）：/health
  - 就绪探针（Readiness）：/ready
- **Pod 反亲和性**：尽量分散到不同节点

### Service（service.yaml）

提供三种服务类型示例：

1. **ClusterIP**（默认）：集群内部访问
2. **NodePort**：通过节点 IP:端口访问
3. **LoadBalancer**：云环境负载均衡器

### Ingress（ingress.yaml）

- 基于域名的路由
- TLS/SSL 终止
- URL 重写
- CORS 配置
- 限流配置

### 存储配置

#### PersistentVolume（persistent-volume.yaml）

提供多种存储后端示例：
- HostPath（本地测试）
- NFS（网络文件系统）
- Local（本地 SSD）
- iSCSI

#### PersistentVolumeClaim（persistent-volume-claim.yaml）

- 静态绑定（指定 PV）
- 动态配置（通过 StorageClass）
- 不同访问模式（RWO、RWX）

#### StorageClass（storage-class.yaml）

提供多种云服务商和存储类型：
- AWS EBS
- GCE Persistent Disk
- Azure Disk
- NFS
- Ceph RBD
- Local Storage

### 网络策略

#### Calico（network-policies/calico-example.yaml）

- 标准 Kubernetes NetworkPolicy
- Calico 扩展策略
- GlobalNetworkPolicy
- HostEndpoint
- 基于标签、命名空间、服务账号的规则

#### Flannel（network-policies/flannel-example.yaml）

- Flannel 配置
- 标准 Kubernetes NetworkPolicy
- Canal（Flannel + Calico）集成

## 常用操作

### 查看资源状态

```bash
# 查看所有资源
kubectl get all

# 查看 Pod 详情
kubectl describe pod <pod-name>

# 查看 Pod 日志
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # 实时查看

# 查看多个副本的日志
kubectl logs -l app=sample-app --all-containers=true
```

### 扩缩容

```bash
# 手动扩缩容
kubectl scale deployment sample-app --replicas=5

# 自动扩缩容（需要先创建 HPA）
kubectl autoscale deployment sample-app --min=2 --max=10 --cpu-percent=80
```

### 更新应用

```bash
# 更新镜像
kubectl set image deployment/sample-app sample-app=kubernetes-sample-app:2.0.0

# 查看滚动更新状态
kubectl rollout status deployment/sample-app

# 查看更新历史
kubectl rollout history deployment/sample-app

# 回滚到上一个版本
kubectl rollout undo deployment/sample-app

# 回滚到指定版本
kubectl rollout undo deployment/sample-app --to-revision=2
```

### 调试

```bash
# 进入容器
kubectl exec -it <pod-name> -- /bin/bash

# 端口转发
kubectl port-forward <pod-name> 8080:8080

# 查看事件
kubectl get events --sort-by=.metadata.creationTimestamp
```

### 清理资源

```bash
# 删除所有资源
kubectl delete -f deployment.yaml
kubectl delete -f service.yaml
kubectl delete -f ingress.yaml
kubectl delete -f persistent-volume-claim.yaml
kubectl delete -f persistent-volume.yaml

# 或者使用标签删除
kubectl delete all -l app=sample-app
```

## 生产环境建议

### 1. 资源配置

- 根据实际负载调整资源请求和限制
- 使用 HorizontalPodAutoscaler 实现自动扩缩容
- 配置 PodDisruptionBudget 确保可用性

### 2. 安全性

- 使用 NetworkPolicy 限制网络访问
- 配置 RBAC 权限控制
- 使用 SecurityContext 限制容器权限
- 定期更新镜像和依赖

### 3. 高可用

- 至少运行 3 个副本
- 配置 Pod 反亲和性分散到不同节点
- 使用拓扑感知提示优化流量路由

### 4. 监控和日志

- 集成 Prometheus 监控
- 配置日志收集（如 EFK、ELK）
- 设置告警规则

### 5. 备份和恢复

- 定期备份 etcd 数据
- 备份持久化数据
- 测试恢复流程

## 高级配置示例

### HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sample-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sample-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 85
```

### PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: sample-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: sample-app
```

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sample-app-config
data:
  app.properties: |
    environment=production
    log_level=info
    max_connections=100
```

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sample-app-secret
type: Opaque
data:
  database-password: cGFzc3dvcmQxMjM=  # base64 encoded
  api-key: YXBpa2V5MTIz  # base64 encoded
```

## 故障排查

### Pod 无法启动

```bash
# 查看 Pod 状态
kubectl describe pod <pod-name>

# 查看事件
kubectl get events --field-selector involvedObject.name=<pod-name>

# 检查镜像是否可用
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[*].image}'
```

### 网络问题

```bash
# 测试 Pod 间连接
kubectl exec <pod-name> -- ping <other-pod-ip>

# 测试服务连接
kubectl exec <pod-name> -- curl http://<service-name>

# 查看网络策略
kubectl get networkpolicies
kubectl describe networkpolicy <policy-name>
```

### 存储问题

```bash
# 查看 PVC 绑定状态
kubectl get pvc

# 查看 PV 详情
kubectl describe pv <pv-name>

# 查看存储类
kubectl get storageclass
```

## 参考资料

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Calico 文档](https://docs.projectcalico.org/)
- [Flannel 文档](https://github.com/flannel-io/flannel)
- [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes 最佳实践](https://kubernetes.io/docs/concepts/configuration/overview/)

## 相关链接

- [示例应用源码](../sample-app/)
- [主教程文档](../README.md)
