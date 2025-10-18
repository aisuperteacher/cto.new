#!/bin/bash

################################################################################
# init-master.sh - Kubernetes Master 节点初始化脚本
#
# 功能说明：
#   初始化 Kubernetes Master 节点（控制平面）
#   - 执行 kubeadm init 初始化集群
#   - 配置 kubectl 访问权限
#   - 安装网络插件（Calico 或 Flannel）
#   - 生成 Worker 节点加入命令
#   - 配置集群组件
#
# 支持系统：CentOS 7/8, Rocky Linux 8, AlmaLinux 8
#
# 使用方法：
#   基本用法（使用默认配置）：
#     sudo ./init-master.sh
#
#   指定 Pod 网络 CIDR：
#     sudo ./init-master.sh --pod-network-cidr 10.244.0.0/16
#
#   指定网络插件：
#     sudo ./init-master.sh --network-plugin calico
#     sudo ./init-master.sh --network-plugin flannel
#
#   指定 API Server 地址：
#     sudo ./init-master.sh --apiserver-advertise-address 192.168.1.10
#
#   指定 Service CIDR：
#     sudo ./init-master.sh --service-cidr 10.96.0.0/12
#
#   完整示例：
#     sudo ./init-master.sh \
#       --apiserver-advertise-address 192.168.1.10 \
#       --pod-network-cidr 10.244.0.0/16 \
#       --service-cidr 10.96.0.0/12 \
#       --network-plugin flannel \
#       --k8s-version 1.28.0
#
# 参数说明：
#   --apiserver-advertise-address <ip>  API Server 监听地址（默认: 自动检测）
#   --pod-network-cidr <cidr>           Pod 网络 CIDR（默认: 10.244.0.0/16）
#   --service-cidr <cidr>               Service CIDR（默认: 10.96.0.0/12）
#   --network-plugin <plugin>           网络插件 calico|flannel（默认: calico）
#   --k8s-version <version>             Kubernetes 版本（默认: 自动检测）
#   --control-plane-endpoint <endpoint> 控制平面端点（HA 场景使用）
#   --upload-certs                      上传证书到集群（HA 场景使用）
#   --skip-network-plugin               跳过网络插件安装
#   -h, --help                          显示帮助信息
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
readonly LOG_FILE="${LOG_DIR}/init-master-$(date +%Y%m%d-%H%M%S).log"
readonly JOIN_COMMAND_FILE="${LOG_DIR}/kubeadm-join-command.sh"

# 默认配置
APISERVER_ADVERTISE_ADDRESS=""
POD_NETWORK_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
NETWORK_PLUGIN="calico"
K8S_VERSION=""
CONTROL_PLANE_ENDPOINT=""
UPLOAD_CERTS=false
SKIP_NETWORK_PLUGIN=false

# 网络插件配置
readonly CALICO_VERSION="v3.26.1"
readonly CALICO_MANIFEST="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
readonly FLANNEL_VERSION="v0.22.0"
readonly FLANNEL_MANIFEST="https://raw.githubusercontent.com/flannel-io/flannel/${FLANNEL_VERSION}/Documentation/kube-flannel.yml"

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
            --apiserver-advertise-address)
                APISERVER_ADVERTISE_ADDRESS="$2"
                shift 2
                ;;
            --pod-network-cidr)
                POD_NETWORK_CIDR="$2"
                shift 2
                ;;
            --service-cidr)
                SERVICE_CIDR="$2"
                shift 2
                ;;
            --network-plugin)
                NETWORK_PLUGIN="$2"
                if [[ "${NETWORK_PLUGIN}" != "calico" ]] && [[ "${NETWORK_PLUGIN}" != "flannel" ]]; then
                    error_exit "不支持的网络插件: ${NETWORK_PLUGIN}。仅支持 calico 或 flannel"
                fi
                shift 2
                ;;
            --k8s-version)
                K8S_VERSION="$2"
                shift 2
                ;;
            --control-plane-endpoint)
                CONTROL_PLANE_ENDPOINT="$2"
                shift 2
                ;;
            --upload-certs)
                UPLOAD_CERTS=true
                shift
                ;;
            --skip-network-plugin)
                SKIP_NETWORK_PLUGIN=true
                shift
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

    # 检查 kubeadm 是否安装
    if ! command -v kubeadm &> /dev/null; then
        error_exit "kubeadm 未安装，请先运行 install-docker-k8s.sh"
    fi

    # 检查 kubelet 是否安装
    if ! command -v kubelet &> /dev/null; then
        error_exit "kubelet 未安装，请先运行 install-docker-k8s.sh"
    fi

    # 检查 kubectl 是否安装
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl 未安装，请先运行 install-docker-k8s.sh"
    fi

    # 检查容器运行时
    if ! systemctl is-active --quiet containerd && ! systemctl is-active --quiet docker; then
        error_exit "容器运行时未运行，请先运行 install-docker-k8s.sh"
    fi

    # 检查 kubelet 是否已经运行
    if systemctl is-active --quiet kubelet; then
        log_warn "kubelet 已在运行，集群可能已初始化"
    fi

    # 自动检测 API Server 地址
    if [[ -z "${APISERVER_ADVERTISE_ADDRESS}" ]]; then
        APISERVER_ADVERTISE_ADDRESS=$(hostname -I | awk '{print $1}')
        log_info "自动检测 API Server 地址: ${APISERVER_ADVERTISE_ADDRESS}"
    fi

    # 自动检测 Kubernetes 版本
    if [[ -z "${K8S_VERSION}" ]]; then
        K8S_VERSION=$(kubeadm version -o short | sed 's/v//')
        log_info "自动检测 Kubernetes 版本: ${K8S_VERSION}"
    fi

    log_info "Master 节点 IP: ${APISERVER_ADVERTISE_ADDRESS}"
    log_info "Pod 网络 CIDR: ${POD_NETWORK_CIDR}"
    log_info "Service CIDR: ${SERVICE_CIDR}"
    log_info "网络插件: ${NETWORK_PLUGIN}"
}

################################################################################
# 函数：生成 kubeadm 配置文件
################################################################################

generate_kubeadm_config() {
    log_step "生成 kubeadm 配置文件"

    local config_file="/tmp/kubeadm-config.yaml"

    cat > "${config_file}" <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${APISERVER_ADVERTISE_ADDRESS}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  taints: null
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VERSION}
networking:
  podSubnet: ${POD_NETWORK_CIDR}
  serviceSubnet: ${SERVICE_CIDR}
EOF

    # 添加控制平面端点（HA 场景）
    if [[ -n "${CONTROL_PLANE_ENDPOINT}" ]]; then
        cat >> "${config_file}" <<EOF
controlPlaneEndpoint: ${CONTROL_PLANE_ENDPOINT}
EOF
        log_info "配置控制平面端点: ${CONTROL_PLANE_ENDPOINT}"
    fi

    cat >> "${config_file}" <<EOF
apiServer:
  timeoutForControlPlane: 4m0s
  extraArgs:
    authorization-mode: Node,RBAC
  certSANs:
  - ${APISERVER_ADVERTISE_ADDRESS}
  - $(hostname)
  - localhost
  - 127.0.0.1
controllerManager: {}
scheduler: {}
certificatesDir: /etc/kubernetes/pki
imageRepository: registry.k8s.io
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

    log_info "kubeadm 配置文件已生成: ${config_file}"
    cat "${config_file}" | tee -a "${LOG_FILE}"

    echo "${config_file}"
}

################################################################################
# 函数：初始化 Master 节点
################################################################################

init_master() {
    log_step "初始化 Kubernetes Master 节点"

    local config_file=$(generate_kubeadm_config)

    # 执行 kubeadm init
    log_info "执行 kubeadm init，这可能需要几分钟..."
    
    local init_cmd="kubeadm init --config=${config_file}"
    
    if [[ "${UPLOAD_CERTS}" == true ]]; then
        init_cmd="${init_cmd} --upload-certs"
        log_info "启用证书上传（HA 模式）"
    fi

    if ${init_cmd} | tee -a "${LOG_FILE}"; then
        log_info "Master 节点初始化成功"
    else
        error_exit "Master 节点初始化失败"
    fi

    # 清理配置文件
    rm -f "${config_file}"
}

################################################################################
# 函数：配置 kubectl
################################################################################

configure_kubectl() {
    log_step "配置 kubectl"

    # 为 root 用户配置
    mkdir -p /root/.kube
    cp -f /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    log_info "已为 root 用户配置 kubectl"

    # 为当前用户配置（如果不是 root）
    if [[ -n "${SUDO_USER}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        local user_home=$(eval echo ~${SUDO_USER})
        mkdir -p "${user_home}/.kube"
        cp -f /etc/kubernetes/admin.conf "${user_home}/.kube/config"
        chown -R ${SUDO_USER}:${SUDO_USER} "${user_home}/.kube"
        log_info "已为用户 ${SUDO_USER} 配置 kubectl"
    fi

    # 验证 kubectl
    sleep 5
    if kubectl get nodes &> /dev/null; then
        log_info "kubectl 配置成功"
        kubectl get nodes | tee -a "${LOG_FILE}"
    else
        log_warn "kubectl 配置可能有问题"
    fi
}

################################################################################
# 函数：安装 Calico 网络插件
################################################################################

install_calico() {
    log_step "安装 Calico 网络插件"

    log_info "下载 Calico manifest..."
    local manifest_file="/tmp/calico.yaml"
    
    if curl -fsSL -o "${manifest_file}" "${CALICO_MANIFEST}"; then
        log_info "Calico manifest 下载成功"
    else
        log_warn "从官方源下载失败，尝试使用国内镜像..."
        if curl -fsSL -o "${manifest_file}" "https://mirror.ghproxy.com/${CALICO_MANIFEST}"; then
            log_info "从国内镜像下载成功"
        else
            error_exit "下载 Calico manifest 失败"
        fi
    fi

    # 修改 Pod 网络 CIDR
    if [[ "${POD_NETWORK_CIDR}" != "192.168.0.0/16" ]]; then
        log_info "配置 Calico Pod 网络 CIDR: ${POD_NETWORK_CIDR}"
        sed -i "s|192.168.0.0/16|${POD_NETWORK_CIDR}|g" "${manifest_file}"
    fi

    # 应用 Calico
    log_info "应用 Calico 配置..."
    if kubectl apply -f "${manifest_file}"; then
        log_info "Calico 安装成功"
    else
        error_exit "Calico 安装失败"
    fi

    # 清理临时文件
    rm -f "${manifest_file}"

    log_info "等待 Calico Pod 启动..."
    sleep 10
}

################################################################################
# 函数：安装 Flannel 网络插件
################################################################################

install_flannel() {
    log_step "安装 Flannel 网络插件"

    log_info "下载 Flannel manifest..."
    local manifest_file="/tmp/kube-flannel.yml"
    
    if curl -fsSL -o "${manifest_file}" "${FLANNEL_MANIFEST}"; then
        log_info "Flannel manifest 下载成功"
    else
        log_warn "从官方源下载失败，尝试使用国内镜像..."
        if curl -fsSL -o "${manifest_file}" "https://mirror.ghproxy.com/${FLANNEL_MANIFEST}"; then
            log_info "从国内镜像下载成功"
        else
            error_exit "下载 Flannel manifest 失败"
        fi
    fi

    # 修改 Pod 网络 CIDR
    if [[ "${POD_NETWORK_CIDR}" != "10.244.0.0/16" ]]; then
        log_info "配置 Flannel Pod 网络 CIDR: ${POD_NETWORK_CIDR}"
        sed -i "s|10.244.0.0/16|${POD_NETWORK_CIDR}|g" "${manifest_file}"
    fi

    # 应用 Flannel
    log_info "应用 Flannel 配置..."
    if kubectl apply -f "${manifest_file}"; then
        log_info "Flannel 安装成功"
    else
        error_exit "Flannel 安装失败"
    fi

    # 清理临时文件
    rm -f "${manifest_file}"

    log_info "等待 Flannel Pod 启动..."
    sleep 10
}

################################################################################
# 函数：安装网络插件
################################################################################

install_network_plugin() {
    if [[ "${SKIP_NETWORK_PLUGIN}" == true ]]; then
        log_info "跳过网络插件安装"
        return
    fi

    case "${NETWORK_PLUGIN}" in
        calico)
            install_calico
            ;;
        flannel)
            install_flannel
            ;;
        *)
            error_exit "不支持的网络插件: ${NETWORK_PLUGIN}"
            ;;
    esac

    log_info "网络插件安装完成"
}

################################################################################
# 函数：生成 Worker 加入命令
################################################################################

generate_join_command() {
    log_step "生成 Worker 节点加入命令"

    sleep 5

    # 生成加入命令
    local join_cmd=$(kubeadm token create --print-join-command)

    if [[ -z "${join_cmd}" ]]; then
        error_exit "无法生成加入命令"
    fi

    # 保存到文件
    cat > "${JOIN_COMMAND_FILE}" <<EOF
#!/bin/bash
#
# Kubernetes Worker 节点加入命令
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# Master 节点: ${APISERVER_ADVERTISE_ADDRESS}
#
# 使用方法：
#   在 Worker 节点上以 root 权限执行此脚本，或者
#   复制下面的命令在 Worker 节点上执行
#

${join_cmd}
EOF

    chmod +x "${JOIN_COMMAND_FILE}"

    log_info "Worker 加入命令已保存到: ${JOIN_COMMAND_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "Worker 节点加入命令：" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    cat "${JOIN_COMMAND_FILE}" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"

    # 如果是 HA 模式，生成 Master 加入命令
    if [[ "${UPLOAD_CERTS}" == true ]]; then
        log_info "生成 Master 节点加入命令（HA 模式）..."
        
        local certificate_key=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
        local master_join_cmd="${join_cmd} --control-plane --certificate-key ${certificate_key}"

        cat > "${LOG_DIR}/kubeadm-join-master-command.sh" <<EOF
#!/bin/bash
#
# Kubernetes Master 节点加入命令（HA 模式）
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
#
# 使用方法：
#   在新的 Master 节点上以 root 权限执行此脚本
#

${master_join_cmd}
EOF

        chmod +x "${LOG_DIR}/kubeadm-join-master-command.sh"
        log_info "Master 加入命令已保存到: ${LOG_DIR}/kubeadm-join-master-command.sh"
    fi
}

################################################################################
# 函数：等待集群就绪
################################################################################

wait_cluster_ready() {
    log_step "等待集群就绪"

    local max_attempts=30
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        log_info "检查集群状态 (${attempt}/${max_attempts})..."

        if kubectl get nodes | grep -q "Ready"; then
            log_info "节点已就绪"
            break
        fi

        sleep 10
        ((attempt++))
    done

    if [[ ${attempt} -ge ${max_attempts} ]]; then
        log_warn "节点未在预期时间内就绪，请检查"
    fi

    # 等待系统 Pod 就绪
    log_info "等待系统 Pod 启动..."
    attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local pending_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l || echo "0")
        
        if [[ ${pending_pods} -eq 0 ]]; then
            log_info "所有系统 Pod 已就绪"
            break
        fi

        log_info "等待 ${pending_pods} 个 Pod 启动..."
        sleep 10
        ((attempt++))
    done

    if [[ ${attempt} -ge ${max_attempts} ]]; then
        log_warn "部分 Pod 未在预期时间内就绪"
    fi
}

################################################################################
# 函数：验证集群
################################################################################

verify_cluster() {
    log_step "验证集群"

    local errors=0

    # 检查节点状态
    log_info "节点状态："
    kubectl get nodes -o wide | tee -a "${LOG_FILE}"

    if kubectl get nodes | grep -q "NotReady"; then
        log_error "存在未就绪的节点"
        ((errors++))
    else
        log_info "✓ 所有节点就绪"
    fi

    # 检查系统 Pod
    log_info "系统 Pod 状态："
    kubectl get pods -n kube-system -o wide | tee -a "${LOG_FILE}"

    local failed_pods=$(kubectl get pods -n kube-system --no-headers | grep -v "Running\|Completed" | wc -l || echo "0")
    if [[ ${failed_pods} -gt 0 ]]; then
        log_warn "存在 ${failed_pods} 个异常 Pod"
    else
        log_info "✓ 所有系统 Pod 运行正常"
    fi

    # 检查组件状态
    log_info "集群组件状态："
    kubectl get cs 2>/dev/null || log_warn "无法获取组件状态（Kubernetes 1.19+ 已弃用此命令）"

    # 测试集群功能
    log_info "测试集群功能..."
    if kubectl run test-pod --image=busybox --restart=Never --rm -it --command -- echo "Hello Kubernetes" &> /dev/null; then
        log_info "✓ 集群功能正常"
    else
        log_warn "集群功能测试失败"
    fi

    if [[ ${errors} -gt 0 ]]; then
        log_warn "验证发现 ${errors} 个问题"
        return 1
    else
        log_info "✓ 集群验证通过"
        return 0
    fi
}

################################################################################
# 函数：显示摘要
################################################################################

show_summary() {
    log_step "初始化摘要"

    echo "" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "Kubernetes Master 节点初始化完成！" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "Master 节点 IP: ${APISERVER_ADVERTISE_ADDRESS}" | tee -a "${LOG_FILE}"
    echo "Kubernetes 版本: ${K8S_VERSION}" | tee -a "${LOG_FILE}"
    echo "Pod 网络 CIDR: ${POD_NETWORK_CIDR}" | tee -a "${LOG_FILE}"
    echo "Service CIDR: ${SERVICE_CIDR}" | tee -a "${LOG_FILE}"
    echo "网络插件: ${NETWORK_PLUGIN}" | tee -a "${LOG_FILE}"
    echo "日志文件: ${LOG_FILE}" | tee -a "${LOG_FILE}"
    echo "加入命令: ${JOIN_COMMAND_FILE}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "常用命令：" | tee -a "${LOG_FILE}"
    echo "  查看节点: kubectl get nodes" | tee -a "${LOG_FILE}"
    echo "  查看 Pod: kubectl get pods -A" | tee -a "${LOG_FILE}"
    echo "  查看集群信息: kubectl cluster-info" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "下一步操作：" | tee -a "${LOG_FILE}"
    echo "  1. 在 Worker 节点上运行 join-worker.sh 加入集群" | tee -a "${LOG_FILE}"
    echo "  2. 使用以下命令查看加入命令：" | tee -a "${LOG_FILE}"
    echo "     cat ${JOIN_COMMAND_FILE}" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
}

################################################################################
# 主函数
################################################################################

main() {
    echo -e "${BLUE}"
    echo "========================================"
    echo "  Kubernetes Master 初始化脚本"
    echo "  版本: 1.0.0"
    echo "========================================"
    echo -e "${NC}"

    parse_args "$@"
    check_environment
    init_master
    configure_kubectl
    install_network_plugin
    generate_join_command
    wait_cluster_ready
    verify_cluster
    show_summary

    log_info "脚本执行完成！"
}

# 执行主函数
main "$@"
