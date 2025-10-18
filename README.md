# Kubernetes 示例应用与配置教程

本仓库提供了一个完整的 Kubernetes 应用部署示例，包括示例应用源码、Docker 镜像构建、以及完整的 Kubernetes 资源配置清单。

## 目录结构

```
.
├── README.md                    # 本文件 - 主教程
├── sample-app/                  # 示例应用目录
│   ├── app.py                   # Python Flask 应用源码
│   ├── requirements.txt         # Python 依赖
│   ├── Dockerfile              # Docker 镜像构建文件
│   └── README.md               # 应用构建和运行说明
└── k8s-manifests/              # Kubernetes 配置清单
    ├── README.md                # Kubernetes 部署详细说明
    ├── deployment.yaml          # Deployment 配置
    ├── service.yaml             # Service 配置
    ├── ingress.yaml             # Ingress 配置
    ├── persistent-volume.yaml   # PersistentVolume 配置
    ├── persistent-volume-claim.yaml  # PVC 配置
    ├── storage-class.yaml       # StorageClass 配置
    └── network-policies/        # 网络策略配置
        ├── calico-example.yaml  # Calico 网络策略
        └── flannel-example.yaml # Flannel 配置和网络策略
```

## 快速开始

### 前置要求

1. **开发环境**：
   - Docker（用于构建镜像）
   - Python 3.11+（用于本地开发测试）
   - Git

2. **Kubernetes 环境**：
   - Kubernetes 集群（v1.20 或更高版本）
   - kubectl 命令行工具
   - 可选：Helm（用于安装 Ingress Controller 等组件）

3. **网络插件**（选择其一）：
   - Calico
   - Flannel
   - Weave
   - Cilium
   - 其他 CNI 插件

### 第一步：构建应用镜像

```bash
# 克隆仓库
git clone <repository-url>
cd <repository-name>

# 进入应用目录
cd sample-app

# 构建 Docker 镜像
docker build -t kubernetes-sample-app:1.0.0 .

# 测试镜像
docker run -d -p 8080:8080 --name test-app kubernetes-sample-app:1.0.0
curl http://localhost:8080/

# 停止测试容器
docker stop test-app
docker rm test-app
```

### 第二步：推送镜像到仓库

```bash
# 标记镜像（使用你的镜像仓库地址）
docker tag kubernetes-sample-app:1.0.0 <your-registry>/kubernetes-sample-app:1.0.0

# 登录镜像仓库
docker login <your-registry>

# 推送镜像
docker push <your-registry>/kubernetes-sample-app:1.0.0
```

**注意**：记得更新 `k8s-manifests/deployment.yaml` 中的镜像地址。

### 第三步：配置存储

```bash
# 进入配置目录
cd ../k8s-manifests

# 创建 StorageClass（根据你的环境选择）
kubectl apply -f storage-class.yaml

# 创建 PersistentVolume（如果不使用动态配置）
kubectl apply -f persistent-volume.yaml

# 创建 PersistentVolumeClaim
kubectl apply -f persistent-volume-claim.yaml

# 验证存储创建成功
kubectl get sc,pv,pvc
```

### 第四步：部署应用

```bash
# 部署应用
kubectl apply -f deployment.yaml

# 等待 Pod 启动
kubectl wait --for=condition=ready pod -l app=sample-app --timeout=60s

# 查看部署状态
kubectl get deployments
kubectl get pods -o wide
```

### 第五步：创建服务

```bash
# 创建 Service
kubectl apply -f service.yaml

# 查看服务
kubectl get services
```

### 第六步：配置 Ingress（可选）

如果需要通过域名访问应用：

```bash
# 确保已安装 Ingress Controller
# 例如安装 Nginx Ingress Controller：
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# 创建 Ingress
kubectl apply -f ingress.yaml

# 查看 Ingress
kubectl get ingress
```

### 第七步：配置网络策略（可选）

```bash
# 如果使用 Calico
kubectl apply -f network-policies/calico-example.yaml

# 如果使用 Flannel 或其他 CNI
kubectl apply -f network-policies/flannel-example.yaml

# 查看网络策略
kubectl get networkpolicies
```

## 访问应用

### 方式一：通过 NodePort

```bash
# 获取 NodePort
NODE_PORT=$(kubectl get service sample-app-nodeport -o jsonpath='{.spec.ports[0].nodePort}')

# 获取节点 IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

# 访问应用
curl http://${NODE_IP}:${NODE_PORT}/
```

### 方式二：通过 LoadBalancer

```bash
# 获取外部 IP
EXTERNAL_IP=$(kubectl get service sample-app-loadbalancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 访问应用
curl http://${EXTERNAL_IP}/
```

### 方式三：通过 Ingress

```bash
# 确保 DNS 已配置或在 /etc/hosts 中添加记录
# echo "<ingress-ip> sample-app.example.com" | sudo tee -a /etc/hosts

# 访问应用
curl http://sample-app.example.com/
curl https://sample-app.example.com/  # 如果配置了 TLS
```

### 方式四：端口转发（测试用）

```bash
# 转发端口
kubectl port-forward service/sample-app-service 8080:80

# 在另一个终端访问
curl http://localhost:8080/
```

## 应用 API 端点

应用提供以下 REST API 端点：

- `GET /` - 主页，返回应用信息和状态
- `GET /health` - 健康检查端点
- `GET /ready` - 就绪检查端点
- `GET /info` - 详细的应用和环境信息
- `GET /api/data` - 数据接口说明
- `POST /api/data` - 提交数据（JSON 格式）

### 示例请求

```bash
# 获取应用信息
curl http://<app-url>/

# 健康检查
curl http://<app-url>/health

# 获取详细信息
curl http://<app-url>/info

# POST 数据
curl -X POST http://<app-url>/api/data \
  -H "Content-Type: application/json" \
  -d '{"name":"test","value":"123"}'
```

## 扩展和管理

### 扩缩容

```bash
# 手动扩容到 5 个副本
kubectl scale deployment sample-app --replicas=5

# 自动扩缩容
kubectl autoscale deployment sample-app --min=2 --max=10 --cpu-percent=80

# 查看自动扩缩容状态
kubectl get hpa
```

### 更新应用

```bash
# 更新镜像版本
kubectl set image deployment/sample-app sample-app=kubernetes-sample-app:2.0.0

# 查看滚动更新状态
kubectl rollout status deployment/sample-app

# 查看更新历史
kubectl rollout history deployment/sample-app
```

### 回滚

```bash
# 回滚到上一个版本
kubectl rollout undo deployment/sample-app

# 回滚到指定版本
kubectl rollout undo deployment/sample-app --to-revision=2
```

### 监控

```bash
# 查看 Pod 日志
kubectl logs -l app=sample-app --tail=100

# 实时查看日志
kubectl logs -f <pod-name>

# 查看 Pod 资源使用
kubectl top pods -l app=sample-app

# 查看节点资源使用
kubectl top nodes
```

## 网络配置详解

### Calico 网络策略

Calico 是一个功能强大的网络和网络策略解决方案，提供：

- **标准 Kubernetes NetworkPolicy 支持**
- **扩展的 Calico NetworkPolicy**
- **GlobalNetworkPolicy**：全局策略
- **HostEndpoint**：保护节点本身
- **基于标签和服务账号的细粒度控制**

安装 Calico：

```bash
# 下载 Calico 配置
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml -O

# 应用配置
kubectl apply -f calico.yaml

# 验证安装
kubectl get pods -n kube-system | grep calico
```

### Flannel 网络配置

Flannel 是一个简单易用的网络解决方案，适合：

- **简单的覆盖网络需求**
- **VXLAN 或 Host-GW 后端**
- **与 Calico 结合使用（Canal）获得网络策略支持**

安装 Flannel：

```bash
# 应用 Flannel 配置
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 验证安装
kubectl get pods -n kube-flannel
```

### Canal（Flannel + Calico）

结合 Flannel 的网络和 Calico 的策略：

```bash
# 安装 Canal
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/canal.yaml

# 验证安装
kubectl get pods -n kube-system | grep canal
```

## 存储配置详解

### 存储类型选择

根据你的需求和环境选择合适的存储：

1. **本地存储（HostPath/Local）**
   - 优点：性能高，简单
   - 缺点：不支持 Pod 迁移，单点故障
   - 适用：测试、单节点环境

2. **网络存储（NFS）**
   - 优点：支持 ReadWriteMany，易于共享
   - 缺点：性能较低，依赖 NFS 服务器
   - 适用：共享文件、配置文件

3. **块存储（Ceph RBD、iSCSI）**
   - 优点：性能好，支持快照和克隆
   - 缺点：配置复杂，只支持 ReadWriteOnce
   - 适用：数据库、高性能应用

4. **云存储（AWS EBS、GCE PD、Azure Disk）**
   - 优点：与云平台集成，自动配置
   - 缺点：依赖云服务商，可能有额外费用
   - 适用：云环境部署

### 动态存储配置

使用 StorageClass 实现动态存储配置：

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
  iops: "3000"
allowVolumeExpansion: true
```

## 生产环境最佳实践

### 1. 高可用配置

- 运行至少 3 个副本
- 配置 Pod 反亲和性
- 使用 PodDisruptionBudget
- 配置健康检查和就绪检查

### 2. 资源管理

- 设置合理的资源请求和限制
- 使用 LimitRange 和 ResourceQuota
- 配置 HorizontalPodAutoscaler
- 监控资源使用情况

### 3. 安全性

- 使用 NetworkPolicy 限制网络访问
- 配置 RBAC 权限控制
- 使用 SecurityContext 限制容器权限
- 扫描镜像漏洞
- 使用 Secret 管理敏感信息
- 启用 Pod Security Standards

### 4. 监控和日志

- 部署 Prometheus 和 Grafana
- 配置日志收集（EFK/ELK）
- 设置告警规则
- 监控应用性能指标

### 5. 备份和恢复

- 定期备份 etcd
- 备份持久化存储
- 测试恢复流程
- 使用 Velero 等工具

### 6. 更新策略

- 使用滚动更新
- 配置更新策略参数
- 在预生产环境测试
- 准备回滚计划

## 故障排查

### Pod 无法启动

```bash
# 查看 Pod 状态
kubectl describe pod <pod-name>

# 查看事件
kubectl get events --sort-by=.metadata.creationTimestamp

# 查看日志
kubectl logs <pod-name>
kubectl logs <pod-name> --previous  # 查看上一个容器的日志
```

### 网络连接问题

```bash
# 测试 DNS 解析
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# 测试服务连接
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://sample-app-service

# 检查网络策略
kubectl get networkpolicies
kubectl describe networkpolicy <policy-name>
```

### 存储问题

```bash
# 查看 PVC 状态
kubectl get pvc
kubectl describe pvc <pvc-name>

# 查看 PV 状态
kubectl get pv
kubectl describe pv <pv-name>

# 查看 StorageClass
kubectl get storageclass
kubectl describe storageclass <sc-name>
```

### 性能问题

```bash
# 查看资源使用
kubectl top pods
kubectl top nodes

# 查看 HPA 状态
kubectl get hpa
kubectl describe hpa <hpa-name>

# 查看事件
kubectl get events --field-selector type!=Normal
```

## 清理资源

```bash
# 删除应用资源
kubectl delete -f k8s-manifests/deployment.yaml
kubectl delete -f k8s-manifests/service.yaml
kubectl delete -f k8s-manifests/ingress.yaml

# 删除存储资源
kubectl delete -f k8s-manifests/persistent-volume-claim.yaml
kubectl delete -f k8s-manifests/persistent-volume.yaml

# 删除网络策略
kubectl delete -f k8s-manifests/network-policies/

# 或者使用标签删除所有相关资源
kubectl delete all,pvc,ingress -l app=sample-app
```

## 进阶主题

### 1. 服务网格（Service Mesh）

考虑使用 Istio 或 Linkerd 实现：
- 流量管理
- 安全通信
- 可观测性
- 灰度发布

### 2. GitOps

使用 ArgoCD 或 Flux 实现：
- 声明式配置管理
- 自动化部署
- 配置版本控制
- 审计追踪

### 3. Helm Charts

将配置打包为 Helm Chart：
- 参数化配置
- 版本管理
- 依赖管理
- 简化部署

### 4. CI/CD 集成

集成到 CI/CD 流程：
- 自动构建镜像
- 自动化测试
- 自动部署
- 回滚机制

## 相关资源

### 官方文档

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Docker 文档](https://docs.docker.com/)
- [Calico 文档](https://docs.projectcalico.org/)
- [Flannel GitHub](https://github.com/flannel-io/flannel)

### 工具和插件

- [kubectl 插件](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/)
- [k9s](https://k9scli.io/) - Kubernetes CLI 管理工具
- [Lens](https://k8slens.dev/) - Kubernetes IDE
- [Helm](https://helm.sh/) - Kubernetes 包管理器

### 学习资源

- [Kubernetes 官方教程](https://kubernetes.io/docs/tutorials/)
- [Kubernetes By Example](https://kubernetesbyexample.com/)
- [Kubernetes Patterns](https://www.oreilly.com/library/view/kubernetes-patterns/9781492050278/)

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 联系方式

如有问题或建议，请提交 Issue。

---

**快速导航**：
- [示例应用源码和构建说明](./sample-app/README.md)
- [Kubernetes 配置详细说明](./k8s-manifests/README.md)
