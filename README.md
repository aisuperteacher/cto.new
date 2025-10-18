# Kubernetes 集群部署指南

本仓库包含 Kubernetes 集群部署的相关文档和配置文件。

## 📚 文档目录

### 部署教程

- **[Kubeadm 多节点集群部署教程（CentOS 7/8）](docs/kubeadm-multinode-centos.md)** - 完整的生产级 Kubernetes 多节点集群搭建指南

## 🚀 快速开始

如果您想在 CentOS 7/8 上快速搭建一个 Kubernetes 多节点集群，请参阅 [Kubeadm 多节点集群部署教程](docs/kubeadm-multinode-centos.md)。

该教程涵盖：

- ✅ 系统准备和前置配置
- ✅ Docker 与 Kubernetes 组件安装
- ✅ Master 节点初始化
- ✅ Worker 节点加入集群
- ✅ 网络插件配置（Calico/Flannel）
- ✅ 集群验证和示例应用部署
- ✅ 故障排查与最佳实践

## 📋 系统要求

- **操作系统**: CentOS 7.x 或 CentOS 8.x
- **最低配置**: 
  - Master 节点: 2 CPU, 4GB RAM
  - Worker 节点: 2 CPU, 2GB RAM

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进文档！

## 📄 许可证

本项目采用 MIT 许可证。

## 🔗 相关资源

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [kubeadm 文档](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Docker 文档](https://docs.docker.com/)
