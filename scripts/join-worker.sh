#!/bin/bash

################################################################################
# join-worker.sh - Kubernetes Worker 节点加入脚本
#
# 功能说明：
#   将节点加入到 Kubernetes 集群作为 Worker 节点
#   - 验证系统环境和依赖
#   - 执行节点加入操作
#   - 配置节点标签和污点
#   - 验证加入状态
#
# 支持系统：CentOS 7/8, Rocky Linux 8, AlmaLinux 8
#
# 使用方法：
#   方式一：从 Master 节点复制加入命令
#     1. 在 Master 节点查看加入命令：
#        cat /var/log/k8s-deploy/kubeadm-join-command.sh
#     
#     2. 在 Worker 节点执行加入命令：
#        sudo ./join-worker.sh \
#          --token <token> \
#          --discovery-token-ca-cert-hash <hash> \
#          --master <master-ip:6443>
#
#   方式二：自动从 Master 节点获取（需要 SSH 访问）
#     sudo ./join-worker.sh \
#       --master-ssh root@192.168.1.10
#
#   方式三：使用完整的 kubeadm join 命令
#     sudo ./join-worker.sh \
#       --join-command "kubeadm join 192.168.1.10:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"
#
#   添加节点标签：
#     sudo ./join-worker.sh \
#       --token <token> \
#       --discovery-token-ca-cert-hash <hash> \
#       --master <master-ip:6443> \
#       --node-label "node-role=worker" \
#       --node-label "zone=us-west"
#
# 参数说明：
#   --master <ip:port>                    Master 节点地址（例: 192.168.1.10:6443）
#   --token <token>                       加入令牌
#   --discovery-token-ca-cert-hash <hash> CA 证书哈希
#   --join-command <command>              完整的 kubeadm join 命令
#   --master-ssh <user@host>              Master 节点 SSH 地址（自动获取加入信息）
#   --node-label <key=value>              添加节点标签（可多次使用）
#   --skip-verify                         跳过加入后验证
#   -h, --help                            显示帮助信息
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
readonly LOG_FILE="${LOG_DIR}/join-worker-$(date +%Y%m%d-%H%M%S).log"

# 变量
MASTER_ADDR=""
JOIN_TOKEN=""
CA_CERT_HASH=""
JOIN_COMMAND=""
MASTER_SSH=""
NODE_LABELS=()
SKIP_VERIFY=false

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
            --master)
                MASTER_ADDR="$2"
                shift 2
                ;;
            --token)
                JOIN_TOKEN="$2"
                shift 2
                ;;
            --discovery-token-ca-cert-hash)
                CA_CERT_HASH="$2"
                shift 2
                ;;
            --join-command)
                JOIN_COMMAND="$2"
                shift 2
                ;;
            --master-ssh)
                MASTER_SSH="$2"
                shift 2
                ;;
            --node-label)
                NODE_LABELS+=("$2")
                shift 2
                ;;
            --skip-verify)
                SKIP_VERIFY=true
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

    # 检测操作系统
    if [[ ! -f /etc/os-release ]]; then
        error_exit "无法检测操作系统版本"
    fi

    source /etc/os-release
    log_info "操作系统: ${NAME} ${VERSION}"

    # 检查 kubeadm 是否安装
    if ! command -v kubeadm &> /dev/null; then
        error_exit "kubeadm 未安装，请先运行 install-docker-k8s.sh"
    fi

    # 检查 kubelet 是否安装
    if ! command -v kubelet &> /dev/null; then
        error_exit "kubelet 未安装，请先运行 install-docker-k8s.sh"
    fi

    # 检查容器运行时
    if ! systemctl is-active --quiet containerd && ! systemctl is-active --quiet docker; then
        error_exit "容器运行时未运行，请先运行 install-docker-k8s.sh"
    fi

    # 检查 kubelet 是否已经运行
    if systemctl is-active --quiet kubelet; then
        log_warn "kubelet 已在运行，节点可能已加入集群"
        
        if kubectl get nodes 2>/dev/null | grep -q "$(hostname)"; then
            log_warn "节点 $(hostname) 已在集群中"
            read -p "是否继续？这将重置节点。(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
            kubeadm reset -f
        fi
    fi

    log_info "环境检查通过"
}

################################################################################
# 函数：从 Master 节点获取加入信息
################################################################################

fetch_join_info_from_master() {
    if [[ -z "${MASTER_SSH}" ]]; then
        return
    fi

    log_step "从 Master 节点获取加入信息"

    log_info "连接到 Master 节点: ${MASTER_SSH}"

    # 检查 SSH 连接
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${MASTER_SSH}" "echo test" &>/dev/null; then
        error_exit "无法连接到 Master 节点: ${MASTER_SSH}"
    fi

    # 获取加入命令
    local join_cmd_file="/var/log/k8s-deploy/kubeadm-join-command.sh"
    
    log_info "获取加入命令..."
    JOIN_COMMAND=$(ssh -o StrictHostKeyChecking=no "${MASTER_SSH}" "tail -1 ${join_cmd_file}" 2>/dev/null || true)

    if [[ -z "${JOIN_COMMAND}" ]]; then
        log_warn "无法从文件获取加入命令，尝试生成新的令牌..."
        JOIN_COMMAND=$(ssh -o StrictHostKeyChecking=no "${MASTER_SSH}" "kubeadm token create --print-join-command" 2>/dev/null || true)
    fi

    if [[ -z "${JOIN_COMMAND}" ]]; then
        error_exit "无法从 Master 节点获取加入命令"
    fi

    log_info "成功获取加入命令"
}

################################################################################
# 函数：构建加入命令
################################################################################

build_join_command() {
    log_step "构建加入命令"

    # 优先使用完整的加入命令
    if [[ -n "${JOIN_COMMAND}" ]]; then
        log_info "使用提供的完整加入命令"
        return
    fi

    # 从 Master 节点获取
    if [[ -n "${MASTER_SSH}" ]]; then
        fetch_join_info_from_master
        return
    fi

    # 从参数构建
    if [[ -z "${MASTER_ADDR}" ]] || [[ -z "${JOIN_TOKEN}" ]] || [[ -z "${CA_CERT_HASH}" ]]; then
        error_exit "缺少必要的参数。请提供 --master, --token, --discovery-token-ca-cert-hash 或使用 --join-command 或 --master-ssh"
    fi

    JOIN_COMMAND="kubeadm join ${MASTER_ADDR} --token ${JOIN_TOKEN} --discovery-token-ca-cert-hash ${CA_CERT_HASH}"
    log_info "从参数构建加入命令"
}

################################################################################
# 函数：执行节点加入
################################################################################

join_cluster() {
    log_step "加入 Kubernetes 集群"

    log_info "执行加入命令..."
    log_info "命令: ${JOIN_COMMAND}"

    # 执行加入
    if eval "${JOIN_COMMAND}" | tee -a "${LOG_FILE}"; then
        log_info "节点成功加入集群"
    else
        error_exit "节点加入失败"
    fi

    # 等待 kubelet 启动
    log_info "等待 kubelet 启动..."
    local max_attempts=30
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if systemctl is-active --quiet kubelet; then
            log_info "kubelet 已启动"
            break
        fi

        sleep 2
        ((attempt++))
    done

    if [[ ${attempt} -ge ${max_attempts} ]]; then
        log_warn "kubelet 未在预期时间内启动"
    fi
}

################################################################################
# 函数：配置节点标签
################################################################################

configure_node_labels() {
    if [[ ${#NODE_LABELS[@]} -eq 0 ]]; then
        return
    fi

    log_step "配置节点标签"

    # 等待节点在集群中可见
    sleep 10

    local node_name=$(hostname)
    log_info "节点名称: ${node_name}"

    # 需要从 Master 节点执行标签操作
    if [[ -n "${MASTER_SSH}" ]]; then
        for label in "${NODE_LABELS[@]}"; do
            log_info "添加标签: ${label}"
            ssh -o StrictHostKeyChecking=no "${MASTER_SSH}" \
                "kubectl label node ${node_name} ${label} --overwrite" || \
                log_warn "无法添加标签: ${label}"
        done
    else
        log_warn "未配置 Master SSH，无法自动添加标签"
        log_info "请在 Master 节点手动执行以下命令："
        for label in "${NODE_LABELS[@]}"; do
            echo "  kubectl label node ${node_name} ${label}" | tee -a "${LOG_FILE}"
        done
    fi
}

################################################################################
# 函数：验证加入状态
################################################################################

verify_join() {
    if [[ "${SKIP_VERIFY}" == true ]]; then
        log_info "跳过验证"
        return
    fi

    log_step "验证加入状态"

    local errors=0

    # 检查 kubelet 状态
    if systemctl is-active --quiet kubelet; then
        log_info "✓ kubelet 运行正常"
    else
        log_error "kubelet 未运行"
        ((errors++))
    fi

    # 检查容器运行时
    if systemctl is-active --quiet containerd || systemctl is-active --quiet docker; then
        log_info "✓ 容器运行时运行正常"
    else
        log_error "容器运行时未运行"
        ((errors++))
    fi

    # 等待并检查节点状态（需要从 Master 查询）
    if [[ -n "${MASTER_SSH}" ]]; then
        log_info "等待节点注册到集群..."
        local max_attempts=30
        local attempt=0
        local node_name=$(hostname)

        while [[ ${attempt} -lt ${max_attempts} ]]; do
            local node_status=$(ssh -o StrictHostKeyChecking=no "${MASTER_SSH}" \
                "kubectl get node ${node_name} -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" 2>/dev/null || echo "")

            if [[ "${node_status}" == "True" ]]; then
                log_info "✓ 节点已就绪"
                break
            fi

            log_info "等待节点就绪 (${attempt}/${max_attempts})..."
            sleep 10
            ((attempt++))
        done

        if [[ ${attempt} -ge ${max_attempts} ]]; then
            log_warn "节点未在预期时间内就绪"
            ((errors++))
        fi

        # 显示节点信息
        log_info "节点信息："
        ssh -o StrictHostKeyChecking=no "${MASTER_SSH}" \
            "kubectl get node ${node_name} -o wide" | tee -a "${LOG_FILE}" || true
    else
        log_warn "未配置 Master SSH，无法验证节点状态"
        log_info "请在 Master 节点执行以下命令验证："
        echo "  kubectl get nodes" | tee -a "${LOG_FILE}"
        echo "  kubectl get pods -A -o wide | grep $(hostname)" | tee -a "${LOG_FILE}"
    fi

    # 检查节点上的 Pod
    log_info "检查系统 Pod..."
    sleep 10

    local running_containers=0
    if command -v crictl &> /dev/null; then
        running_containers=$(crictl ps 2>/dev/null | grep -c "Running" || echo "0")
        log_info "运行中的容器数: ${running_containers}"
        
        if [[ ${running_containers} -gt 0 ]]; then
            log_info "✓ 容器正在运行"
        else
            log_warn "未检测到运行中的容器"
        fi
    fi

    if [[ ${errors} -gt 0 ]]; then
        log_warn "验证发现 ${errors} 个问题"
        return 1
    else
        log_info "✓ 验证通过"
        return 0
    fi
}

################################################################################
# 函数：显示摘要
################################################################################

show_summary() {
    log_step "加入摘要"

    local node_name=$(hostname)
    local node_ip=$(hostname -I | awk '{print $1}')

    echo "" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "Worker 节点加入完成！" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "节点名称: ${node_name}" | tee -a "${LOG_FILE}"
    echo "节点 IP: ${node_ip}" | tee -a "${LOG_FILE}"
    echo "日志文件: ${LOG_FILE}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"

    if [[ ${#NODE_LABELS[@]} -gt 0 ]]; then
        echo "配置的标签：" | tee -a "${LOG_FILE}"
        for label in "${NODE_LABELS[@]}"; do
            echo "  - ${label}" | tee -a "${LOG_FILE}"
        done
        echo "" | tee -a "${LOG_FILE}"
    fi

    echo "验证命令（在 Master 节点执行）：" | tee -a "${LOG_FILE}"
    echo "  kubectl get nodes" | tee -a "${LOG_FILE}"
    echo "  kubectl get nodes ${node_name} -o wide" | tee -a "${LOG_FILE}"
    echo "  kubectl get pods -A -o wide --field-selector spec.nodeName=${node_name}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "故障排查：" | tee -a "${LOG_FILE}"
    echo "  查看 kubelet 日志: journalctl -u kubelet -f" | tee -a "${LOG_FILE}"
    echo "  查看容器日志: crictl ps -a" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
}

################################################################################
# 函数：显示交互式帮助
################################################################################

interactive_mode() {
    log_step "交互式模式"

    echo "" | tee -a "${LOG_FILE}"
    echo "您可以选择以下方式之一加入集群：" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "1. 输入完整的 kubeadm join 命令" | tee -a "${LOG_FILE}"
    echo "2. 输入 Master 节点的 SSH 地址（自动获取）" | tee -a "${LOG_FILE}"
    echo "3. 手动输入加入参数" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"

    read -p "请选择 (1/2/3): " choice

    case ${choice} in
        1)
            read -p "请输入完整的 kubeadm join 命令: " JOIN_COMMAND
            ;;
        2)
            read -p "请输入 Master 节点 SSH 地址 (例: root@192.168.1.10): " MASTER_SSH
            ;;
        3)
            read -p "请输入 Master 地址 (例: 192.168.1.10:6443): " MASTER_ADDR
            read -p "请输入 Token: " JOIN_TOKEN
            read -p "请输入 CA 证书哈希: " CA_CERT_HASH
            ;;
        *)
            error_exit "无效的选择"
            ;;
    esac

    echo "" | tee -a "${LOG_FILE}"
}

################################################################################
# 主函数
################################################################################

main() {
    echo -e "${BLUE}"
    echo "========================================"
    echo "  Kubernetes Worker 节点加入脚本"
    echo "  版本: 1.0.0"
    echo "========================================"
    echo -e "${NC}"

    parse_args "$@"
    check_environment

    # 如果没有提供任何参数，进入交互模式
    if [[ -z "${JOIN_COMMAND}" ]] && [[ -z "${MASTER_SSH}" ]] && [[ -z "${MASTER_ADDR}" ]]; then
        interactive_mode
    fi

    build_join_command
    join_cluster
    configure_node_labels
    verify_join
    show_summary

    log_info "脚本执行完成！"
}

# 执行主函数
main "$@"
