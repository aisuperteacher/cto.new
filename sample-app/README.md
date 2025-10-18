# Kubernetes 示例应用

这是一个简单的 Python Flask 应用，用于演示 Kubernetes 部署和管理。

## 应用功能

应用提供以下 API 端点：

- `GET /` - 主页，返回欢迎信息和基本状态
- `GET /health` - 健康检查端点
- `GET /ready` - 就绪检查端点
- `GET /info` - 应用信息和环境详情
- `GET /api/data` - 数据接口说明
- `POST /api/data` - 提交数据

## 本地开发

### 前置要求

- Python 3.11 或更高版本
- pip

### 安装依赖

```bash
pip install -r requirements.txt
```

### 运行应用

```bash
python app.py
```

应用将在 `http://localhost:8080` 上运行。

### 测试

```bash
# 测试主页
curl http://localhost:8080/

# 测试健康检查
curl http://localhost:8080/health

# 测试信息端点
curl http://localhost:8080/info

# 测试 POST 请求
curl -X POST http://localhost:8080/api/data \
  -H "Content-Type: application/json" \
  -d '{"name":"test","value":"123"}'
```

## Docker 构建

### 构建镜像

```bash
docker build -t kubernetes-sample-app:1.0.0 .
```

### 运行容器

```bash
docker run -d -p 8080:8080 --name sample-app kubernetes-sample-app:1.0.0
```

### 测试容器

```bash
curl http://localhost:8080/
```

### 停止和删除容器

```bash
docker stop sample-app
docker rm sample-app
```

## 推送到镜像仓库

### Docker Hub

```bash
# 标记镜像
docker tag kubernetes-sample-app:1.0.0 your-username/kubernetes-sample-app:1.0.0

# 登录 Docker Hub
docker login

# 推送镜像
docker push your-username/kubernetes-sample-app:1.0.0
```

### 私有镜像仓库

```bash
# 标记镜像
docker tag kubernetes-sample-app:1.0.0 registry.example.com/kubernetes-sample-app:1.0.0

# 推送镜像
docker push registry.example.com/kubernetes-sample-app:1.0.0
```

## Kubernetes 部署

参见 `../k8s-manifests/` 目录中的 Kubernetes 配置文件。

基本部署步骤：

```bash
# 创建 Deployment
kubectl apply -f ../k8s-manifests/deployment.yaml

# 创建 Service
kubectl apply -f ../k8s-manifests/service.yaml

# 查看部署状态
kubectl get pods
kubectl get services

# 访问应用（如果使用 NodePort）
curl http://<node-ip>:<node-port>/
```

详细部署说明请参见主 README.md 文件。

## 环境变量

- `PORT` - 应用监听端口（默认：8080）
- `ENVIRONMENT` - 运行环境（默认：production）

## 多阶段构建优化（可选）

如需更小的镜像大小，可以使用多阶段构建。创建 `Dockerfile.optimized`：

```dockerfile
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY app.py .
ENV PATH=/root/.local/bin:$PATH
ENV PORT=8080
EXPOSE 8080
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser
CMD ["python", "app.py"]
```

构建优化镜像：

```bash
docker build -f Dockerfile.optimized -t kubernetes-sample-app:1.0.0-slim .
```
