#!/bin/bash

################################################################################
# install-docker-k8s.sh - Docker 和 Kubernetes 安装脚本
#
# 功能说明：
#   在 CentOS 7/8 系统上安装 Docker 和 Kubernetes 组件
#   - 自动检测操作系统版本
#   - 配置 Docker/containerd 运行时
#   - 安装 kubeadm、kubelet、kubectl
#   - 配置 cgroup 驱动
#   - 设置镜像加速器
#   - 预拉取必要的镜像
#
# 支持系统：CentOS 7/8, Rocky Linux 8, AlmaLinux 8
#
# 使用方法：
#   基本用法（使用默认版本）：
#     sudo ./install-docker-k8s.sh
#
#   指定 Kubernetes 版本：
#     sudo ./install-docker-k8s.sh --k8s-version 1.28.0
#
#   指定容器运行时：
#     sudo ./install-docker-k8s.sh --runtime containerd
#     sudo ./install-docker-k8s.sh --runtime docker
#
#   使用镜像加速器（国内环境）：
#     sudo ./install-docker-k8s.sh --use-mirror
#
#   跳过镜像预拉取：
#     sudo ./install-docker-k8s.sh --skip-pull-images
#
#   完整示例：
#     sudo ./install-docker-k8s.sh \
#       --k8s-version 1.28.0 \
#       --runtime containerd \
#       --use-mirror
#
# 参数说明：
#   --k8s-version <version>  指定 Kubernetes 版本（默认: 1.28.0）
#   --runtime <type>         容器运行时 docker|containerd（默认: containerd）
#   --use-mirror             使用镜像加速器（阿里云）
#   --skip-pull-images       跳过镜像预拉取
#   --docker-version <ver>   指定 Docker 版本（可选）
#   -h, --help               显示帮助信息
#
# 作者：Kubernetes Automation Team
# 版本：1.0.0
################################################################################

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 日志文件
readonly LOG_DIR="/var/log/k8s-deploy"
readonly LOG_FILE="${LOG_DIR}/install-docker-k8s-$(date +%Y%m%d-%H%M%S).log"

# 默认配置
K8S_VERSION="1.28.0"
CONTAINER_RUNTIME="containerd"
USE_MIRROR=false
SKIP_PULL_IMAGES=false
DOCKER_VERSION=""

# 镜像仓库配置
ALIYUN_DOCKER_MIRROR="https://registry.cn-hangzhou.aliyuncs.com"
ALIYUN_K8S_MIRROR="https://mirrors.aliyun.com/kubernetes"

################################################################################
# 函数：日志输出
################################################################################

log_info() {
    local msg="$1"
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" | tee -a "${LOG_FILE}"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" | tee -a "${LOG_FILE}"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" | tee -a "${LOG_FILE}"
}

log_step() {
    local msg="$1"
    echo -e "\n${BLUE}==>${NC} ${msg}" | tee -a "${LOG_FILE}"
}

################################################################################
# 函数：错误处理
################################################################################

error_exit() {
    log_error "$1"
    log_error "脚本执行失败！请查看日志: ${LOG_FILE}"
    exit 1
}

trap 'error_exit "脚本在第 ${LINENO} 行执行失败"' ERR

################################################################################
# 函数：显示帮助信息
################################################################################

show_help() {
    grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# \?//'
    exit 0
}

################################################################################
# 函数：解析命令行参数
################################################################################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --k8s-version)
                K8S_VERSION="$2"
                shift 2
                ;;
            --runtime)
                CONTAINER_RUNTIME="$2"
                if [[ "${CONTAINER_RUNTIME}" != "docker" ]] && [[ "${CONTAINER_RUNTIME}" != "containerd" ]]; then
                    error_exit "不支持的运行时: ${CONTAINER_RUNTIME}。仅支持 docker 或 containerd"
                fi
                shift 2
                ;;
            --use-mirror)
                USE_MIRROR=true
                shift
                ;;
            --skip-pull-images)
                SKIP_PULL_IMAGES=true
                shift
                ;;
            --docker-version)
                DOCKER_VERSION="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                ;;
        esac
    done
}

################################################################################
# 函数：环境检查
################################################################################

check_environment() {
    log_step "执行环境检查"

    # 检查是否以 root 权限运行
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本必须以 root 权限运行"
    fi

    # 创建日志目录
    mkdir -p "${LOG_DIR}"
    log_info "日志文件: ${LOG_FILE}"

    # 检测操作系统
    if [[ ! -f /etc/os-release ]]; then
        error_exit "无法检测操作系统版本"
    fi

    source /etc/os-release
    log_info "操作系统: ${NAME} ${VERSION}"

    # 验证支持的操作系统
    case "${ID}" in
        centos|rhel)
            if [[ "${VERSION_ID}" != "7" ]] && [[ "${VERSION_ID}" != "8" ]]; then
                error_exit "不支持的 CentOS/RHEL 版本: ${VERSION_ID}。仅支持版本 7 和 8"
            fi
            ;;
        rocky|almalinux)
            if [[ "${VERSION_ID}" != "8"* ]]; then
                error_exit "不支持的 ${NAME} 版本: ${VERSION_ID}。仅支持版本 8"
            fi
            ;;
        *)
            error_exit "不支持的操作系统: ${NAME}。仅支持 CentOS 7/8, Rocky Linux 8, AlmaLinux 8"
            ;;
    esac

    # 检查系统是否已准备
    log_info "检查系统准备状态..."
    
    if [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
        log_warn "SELinux 仍为 Enforcing 模式，建议先运行 prep-system.sh"
    fi

    if swapon -s | grep -q "/"; then
        log_warn "swap 仍然启用，建议先运行 prep-system.sh"
    fi

    # 检查网络连接
    log_info "检查网络连接..."
    if ! ping -c 1 -W 3 8.8.8.8 &> /dev/null; then
        log_warn "无法访问外网，请确保网络配置正确"
    else
        log_info "网络连接正常"
    fi
}

################################################################################
# 函数：安装 Docker
################################################################################

install_docker() {
    log_step "安装 Docker"

    if command -v docker &> /dev/null; then
        local current_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        log_info "Docker 已安装，版本: ${current_version}"
        
        if [[ -n "${DOCKER_VERSION}" ]] && [[ "${current_version}" != "${DOCKER_VERSION}" ]]; then
            log_warn "当前 Docker 版本与指定版本不匹配，将重新安装"
        else
            log_info "跳过 Docker 安装"
            return
        fi
    fi

    source /etc/os-release

    # 卸载旧版本
    log_info "卸载旧版本 Docker..."
    yum remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine \
        docker-ce docker-ce-cli containerd.io 2>/dev/null || true

    # 安装依赖
    log_info "安装依赖包..."
    yum install -y yum-utils device-mapper-persistent-data lvm2

    # 添加 Docker 仓库
    log_info "添加 Docker 仓库..."
    if [[ "${USE_MIRROR}" == true ]]; then
        yum-config-manager --add-repo ${ALIYUN_DOCKER_MIRROR}/docker-ce/linux/centos/docker-ce.repo
        log_info "使用阿里云镜像"
    else
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi

    # 安装 Docker
    log_info "安装 Docker CE..."
    if [[ -n "${DOCKER_VERSION}" ]]; then
        yum install -y docker-ce-${DOCKER_VERSION} docker-ce-cli-${DOCKER_VERSION} containerd.io
    else
        yum install -y docker-ce docker-ce-cli containerd.io
    fi

    # 配置 Docker daemon
    log_info "配置 Docker daemon..."
    mkdir -p /etc/docker

    local registry_mirrors=""
    if [[ "${USE_MIRROR}" == true ]]; then
        registry_mirrors='  "registry-mirrors": ["https://registry.cn-hangzhou.aliyuncs.com"],'
    fi

    cat > /etc/docker/daemon.json <<EOF
{
${registry_mirrors}
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

    # 启动 Docker
    log_info "启动 Docker..."
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker

    # 验证安装
    if docker version &> /dev/null; then
        log_info "Docker 安装成功，版本: $(docker version --format '{{.Server.Version}}')"
    else
        error_exit "Docker 安装失败"
    fi
}

################################################################################
# 函数：安装 containerd
################################################################################

install_containerd() {
    log_step "安装 containerd"

    if command -v containerd &> /dev/null && systemctl is-active --quiet containerd; then
        log_info "containerd 已安装并运行"
        return
    fi

    # 安装 containerd
    log_info "安装 containerd..."
    yum install -y containerd.io

    # 生成默认配置
    log_info "配置 containerd..."
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    # 配置 systemd cgroup 驱动
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    # 配置镜像加速
    if [[ "${USE_MIRROR}" == true ]]; then
        log_info "配置 containerd 镜像加速..."
        
        # 配置 sandbox 镜像
        sed -i 's|sandbox_image = "registry.k8s.io/pause:3.8"|sandbox_image = "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.9"|' /etc/containerd/config.toml
        
        # 添加镜像仓库配置
        cat >> /etc/containerd/config.toml <<EOF

[plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
  endpoint = ["https://registry.cn-hangzhou.aliyuncs.com"]

[plugins."io.containerd.grpc.v1.cri".registry.mirrors."k8s.gcr.io"]
  endpoint = ["https://registry.cn-hangzhou.aliyuncs.com/google_containers"]

[plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
  endpoint = ["https://registry.cn-hangzhou.aliyuncs.com/google_containers"]
EOF
    fi

    # 启动 containerd
    log_info "启动 containerd..."
    systemctl daemon-reload
    systemctl enable containerd
    systemctl restart containerd

    # 验证安装
    if systemctl is-active --quiet containerd; then
        log_info "containerd 安装成功并运行中"
    else
        error_exit "containerd 启动失败"
    fi
}

################################################################################
# 函数：配置容器运行时
################################################################################

configure_container_runtime() {
    log_step "配置容器运行时: ${CONTAINER_RUNTIME}"

    case "${CONTAINER_RUNTIME}" in
        docker)
            install_docker
            # 确保 containerd 也安装（Docker 依赖）
            if ! systemctl is-active --quiet containerd; then
                systemctl start containerd
                systemctl enable containerd
            fi
            ;;
        containerd)
            install_containerd
            ;;
        *)
            error_exit "不支持的运行时: ${CONTAINER_RUNTIME}"
            ;;
    esac

    log_info "容器运行时配置完成"
}

################################################################################
# 函数：安装 Kubernetes
################################################################################

install_kubernetes() {
    log_step "安装 Kubernetes ${K8S_VERSION}"

    # 添加 Kubernetes 仓库
    log_info "配置 Kubernetes 仓库..."
    
    local k8s_repo_baseurl
    if [[ "${USE_MIRROR}" == true ]]; then
        k8s_repo_baseurl="${ALIYUN_K8S_MIRROR}/yum/repos/kubernetes-el7-\$basearch"
        log_info "使用阿里云镜像"
    else
        k8s_repo_baseurl="https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION%.*}/rpm/"
    fi

    cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=${k8s_repo_baseurl}
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

    # 清理缓存
    yum clean all
    yum makecache

    # 检查指定版本是否可用
    log_info "检查 Kubernetes 版本..."
    local k8s_version_pattern="${K8S_VERSION}-0"
    
    if yum list available --showduplicates | grep -q "kubeadm.*${K8S_VERSION}"; then
        log_info "找到指定版本: ${K8S_VERSION}"
    else
        log_warn "指定版本 ${K8S_VERSION} 不可用，将安装最新版本"
        k8s_version_pattern=""
    fi

    # 安装 Kubernetes 组件
    log_info "安装 kubeadm, kubelet, kubectl..."
    
    if [[ -n "${k8s_version_pattern}" ]]; then
        yum install -y \
            kubelet-${k8s_version_pattern} \
            kubeadm-${k8s_version_pattern} \
            kubectl-${k8s_version_pattern} \
            --disableexcludes=kubernetes
    else
        yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    fi

    # 锁定版本，防止自动更新
    yum versionlock kubelet kubeadm kubectl 2>/dev/null || \
        log_warn "无法锁定版本，请手动安装 yum-plugin-versionlock"

    # 启用 kubelet
    systemctl enable kubelet

    # 验证安装
    log_info "验证安装..."
    kubeadm version
    kubelet --version
    kubectl version --client=true

    log_info "Kubernetes 组件安装完成"
}

################################################################################
# 函数：配置 crictl
################################################################################

configure_crictl() {
    log_step "配置 crictl"

    local runtime_endpoint
    case "${CONTAINER_RUNTIME}" in
        docker)
            runtime_endpoint="unix:///var/run/dockershim.sock"
            ;;
        containerd)
            runtime_endpoint="unix:///run/containerd/containerd.sock"
            ;;
    esac

    cat > /etc/crictl.yaml <<EOF
runtime-endpoint: ${runtime_endpoint}
image-endpoint: ${runtime_endpoint}
timeout: 10
debug: false
EOF

    log_info "crictl 配置完成"
}

################################################################################
# 函数：配置 kubelet
################################################################################

configure_kubelet() {
    log_step "配置 kubelet"

    # 创建 kubelet 配置目录
    mkdir -p /var/lib/kubelet

    # 配置 kubelet 额外参数
    local kubelet_extra_args=""
    
    case "${CONTAINER_RUNTIME}" in
        containerd)
            kubelet_extra_args="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
            ;;
        docker)
            kubelet_extra_args="--container-runtime=docker"
            ;;
    esac

    # 创建 kubelet 环境变量文件
    mkdir -p /etc/sysconfig
    cat > /etc/sysconfig/kubelet <<EOF
KUBELET_EXTRA_ARGS=${kubelet_extra_args}
EOF

    log_info "kubelet 配置完成"
}

################################################################################
# 函数：预拉取镜像
################################################################################

pull_images() {
    if [[ "${SKIP_PULL_IMAGES}" == true ]]; then
        log_info "跳过镜像预拉取"
        return
    fi

    log_step "预拉取 Kubernetes 镜像"

    # 获取镜像列表
    log_info "获取镜像列表..."
    local images=$(kubeadm config images list --kubernetes-version="${K8S_VERSION}" 2>/dev/null || true)

    if [[ -z "${images}" ]]; then
        log_warn "无法获取镜像列表，跳过预拉取"
        return
    fi

    log_info "需要拉取的镜像："
    echo "${images}" | tee -a "${LOG_FILE}"

    # 拉取镜像
    if [[ "${USE_MIRROR}" == true ]]; then
        log_info "使用阿里云镜像加速..."
        
        for img in ${images}; do
            local image_name=$(echo ${img} | awk -F'/' '{print $NF}')
            local aliyun_img="registry.cn-hangzhou.aliyuncs.com/google_containers/${image_name}"
            
            log_info "拉取镜像: ${aliyun_img}"
            
            case "${CONTAINER_RUNTIME}" in
                docker)
                    docker pull "${aliyun_img}" || log_warn "拉取失败: ${aliyun_img}"
                    docker tag "${aliyun_img}" "${img}" || log_warn "标记失败: ${img}"
                    docker rmi "${aliyun_img}" 2>/dev/null || true
                    ;;
                containerd)
                    ctr -n k8s.io image pull "${aliyun_img}" || log_warn "拉取失败: ${aliyun_img}"
                    ctr -n k8s.io image tag "${aliyun_img}" "${img}" || log_warn "标记失败: ${img}"
                    ctr -n k8s.io image rm "${aliyun_img}" 2>/dev/null || true
                    ;;
            esac
        done
    else
        for img in ${images}; do
            log_info "拉取镜像: ${img}"
            
            case "${CONTAINER_RUNTIME}" in
                docker)
                    docker pull "${img}" || log_warn "拉取失败: ${img}"
                    ;;
                containerd)
                    ctr -n k8s.io image pull "${img}" || log_warn "拉取失败: ${img}"
                    ;;
            esac
        done
    fi

    log_info "镜像预拉取完成"
}

################################################################################
# 函数：验证安装
################################################################################

verify_installation() {
    log_step "验证安装"

    local errors=0

    # 检查容器运行时
    case "${CONTAINER_RUNTIME}" in
        docker)
            if ! systemctl is-active --quiet docker; then
                log_error "Docker 未运行"
                ((errors++))
            else
                log_info "✓ Docker 运行正常"
            fi
            ;;
        containerd)
            if ! systemctl is-active --quiet containerd; then
                log_error "containerd 未运行"
                ((errors++))
            else
                log_info "✓ containerd 运行正常"
            fi
            ;;
    esac

    # 检查 kubeadm
    if ! command -v kubeadm &> /dev/null; then
        log_error "kubeadm 未安装"
        ((errors++))
    else
        log_info "✓ kubeadm 已安装: $(kubeadm version -o short)"
    fi

    # 检查 kubelet
    if ! command -v kubelet &> /dev/null; then
        log_error "kubelet 未安装"
        ((errors++))
    else
        log_info "✓ kubelet 已安装"
        if systemctl is-enabled --quiet kubelet; then
            log_info "✓ kubelet 已启用"
        else
            log_error "kubelet 未启用"
            ((errors++))
        fi
    fi

    # 检查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装"
        ((errors++))
    else
        log_info "✓ kubectl 已安装: $(kubectl version --client=true -o yaml | grep gitVersion | awk '{print $2}')"
    fi

    if [[ ${errors} -gt 0 ]]; then
        log_warn "验证发现 ${errors} 个问题"
        return 1
    else
        log_info "✓ 所有组件验证通过"
        return 0
    fi
}

################################################################################
# 函数：显示摘要
################################################################################

show_summary() {
    log_step "安装摘要"

    echo "" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "Docker 和 Kubernetes 安装完成！" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "操作系统: $(source /etc/os-release; echo ${NAME} ${VERSION})" | tee -a "${LOG_FILE}"
    echo "容器运行时: ${CONTAINER_RUNTIME}" | tee -a "${LOG_FILE}"
    echo "Kubernetes 版本: $(kubeadm version -o short)" | tee -a "${LOG_FILE}"
    echo "日志文件: ${LOG_FILE}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "下一步操作：" | tee -a "${LOG_FILE}"
    echo "  Master 节点: 运行 init-master.sh 初始化集群" | tee -a "${LOG_FILE}"
    echo "  Worker 节点: 等待 Master 初始化完成后运行 join-worker.sh" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
}

################################################################################
# 主函数
################################################################################

main() {
    echo -e "${BLUE}"
    echo "========================================"
    echo "  Docker & Kubernetes 安装脚本"
    echo "  版本: 1.0.0"
    echo "========================================"
    echo -e "${NC}"

    parse_args "$@"
    check_environment
    configure_container_runtime
    install_kubernetes
    configure_crictl
    configure_kubelet
    pull_images
    verify_installation
    show_summary

    log_info "脚本执行完成！"
}

# 执行主函数
main "$@"
