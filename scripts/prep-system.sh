#!/bin/bash

################################################################################
# prep-system.sh - 系统准备脚本
#
# 功能说明：
#   准备 CentOS 7/8 系统以支持 Kubernetes 集群部署
#   - 检测和验证操作系统版本
#   - 禁用 SELinux 和防火墙
#   - 配置系统参数（内核参数、模块加载等）
#   - 禁用 swap
#   - 配置时间同步
#   - 设置主机名和 hosts 文件
#
# 支持系统：CentOS 7/8, Rocky Linux 8, AlmaLinux 8
#
# 使用方法：
#   基本用法：
#     sudo ./prep-system.sh
#
#   设置主机名：
#     sudo ./prep-system.sh --hostname k8s-master-01
#
#   添加集群节点到 hosts：
#     sudo ./prep-system.sh --hostname k8s-master-01 \
#       --add-host "192.168.1.10 k8s-master-01" \
#       --add-host "192.168.1.11 k8s-worker-01" \
#       --add-host "192.168.1.12 k8s-worker-02"
#
#   跳过时间同步配置：
#     sudo ./prep-system.sh --skip-chrony
#
# 参数说明：
#   --hostname <name>        设置系统主机名
#   --add-host <ip hostname> 添加主机条目到 /etc/hosts
#   --skip-chrony            跳过时间同步配置
#   --skip-reboot-check      跳过重启检查提示
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
readonly LOG_FILE="${LOG_DIR}/prep-system-$(date +%Y%m%d-%H%M%S).log"

# 全局变量
HOSTNAME=""
HOSTS_ENTRIES=()
SKIP_CHRONY=false
SKIP_REBOOT_CHECK=false

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
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --add-host)
                HOSTS_ENTRIES+=("$2")
                shift 2
                ;;
            --skip-chrony)
                SKIP_CHRONY=true
                shift
                ;;
            --skip-reboot-check)
                SKIP_REBOOT_CHECK=true
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

    # 检查网络连接
    log_info "检查网络连接..."
    if ! ping -c 1 -W 3 8.8.8.8 &> /dev/null; then
        log_warn "无法访问外网，请确保网络配置正确"
    else
        log_info "网络连接正常"
    fi

    # 检查可用内存
    local mem_total=$(free -g | awk '/^Mem:/{print $2}')
    if [[ ${mem_total} -lt 2 ]]; then
        log_warn "系统内存小于 2GB (当前: ${mem_total}GB)，可能影响集群性能"
    else
        log_info "系统内存: ${mem_total}GB"
    fi

    # 检查 CPU 核心数
    local cpu_cores=$(nproc)
    if [[ ${cpu_cores} -lt 2 ]]; then
        log_warn "CPU 核心数小于 2 (当前: ${cpu_cores})，可能影响集群性能"
    else
        log_info "CPU 核心数: ${cpu_cores}"
    fi
}

################################################################################
# 函数：禁用 SELinux
################################################################################

disable_selinux() {
    log_step "禁用 SELinux"

    local current_mode=$(getenforce)
    log_info "当前 SELinux 模式: ${current_mode}"

    if [[ "${current_mode}" != "Disabled" ]]; then
        setenforce 0 || log_warn "无法临时禁用 SELinux"
        
        if grep -q "^SELINUX=enforcing" /etc/selinux/config; then
            sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
            log_info "已设置 SELinux 为 disabled（需要重启生效）"
        elif grep -q "^SELINUX=permissive" /etc/selinux/config; then
            sed -i 's/^SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
            log_info "已设置 SELinux 为 disabled（需要重启生效）"
        fi
    else
        log_info "SELinux 已经被禁用"
    fi
}

################################################################################
# 函数：禁用防火墙
################################################################################

disable_firewall() {
    log_step "禁用防火墙"

    if systemctl is-active --quiet firewalld; then
        systemctl stop firewalld
        systemctl disable firewalld
        log_info "已停止并禁用 firewalld"
    else
        log_info "firewalld 未运行"
    fi

    if systemctl is-enabled --quiet firewalld 2>/dev/null; then
        systemctl disable firewalld
        log_info "已禁用 firewalld 开机自启"
    fi
}

################################################################################
# 函数：禁用 swap
################################################################################

disable_swap() {
    log_step "禁用 swap"

    if swapon -s | grep -q "/"; then
        swapoff -a
        log_info "已临时禁用所有 swap"
    else
        log_info "当前没有启用的 swap"
    fi

    # 永久禁用 swap
    if grep -q "^[^#].*swap" /etc/fstab; then
        cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d-%H%M%S)
        sed -i '/\sswap\s/s/^/#/' /etc/fstab
        log_info "已在 /etc/fstab 中注释 swap 条目"
    else
        log_info "/etc/fstab 中没有 swap 条目"
    fi
}

################################################################################
# 函数：配置内核参数
################################################################################

configure_kernel_params() {
    log_step "配置内核参数"

    # 创建 k8s.conf 配置文件
    cat > /etc/sysctl.d/k8s.conf <<EOF
# Kubernetes 内核参数配置
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
net.ipv6.conf.all.forwarding        = 1
vm.swappiness                       = 0
vm.overcommit_memory                = 1
vm.panic_on_oom                     = 0
fs.inotify.max_user_watches         = 89100
fs.file-max                         = 52706963
fs.nr_open                          = 52706963
net.ipv4.tcp_keepalive_time         = 600
net.ipv4.tcp_keepalive_probes       = 3
net.ipv4.tcp_keepalive_intvl        = 15
net.ipv4.neigh.default.gc_thresh1   = 4096
net.ipv4.neigh.default.gc_thresh2   = 6144
net.ipv4.neigh.default.gc_thresh3   = 8192
EOF

    # 加载 br_netfilter 模块
    modprobe br_netfilter || log_warn "无法加载 br_netfilter 模块"
    modprobe overlay || log_warn "无法加载 overlay 模块"
    
    # 确保模块开机自动加载
    cat > /etc/modules-load.d/k8s.conf <<EOF
br_netfilter
overlay
EOF

    # 应用内核参数
    sysctl -p /etc/sysctl.d/k8s.conf || log_warn "部分内核参数应用失败"
    
    log_info "内核参数配置完成"
}

################################################################################
# 函数：配置时间同步
################################################################################

configure_chrony() {
    log_step "配置时间同步"

    if [[ "${SKIP_CHRONY}" == true ]]; then
        log_info "跳过时间同步配置"
        return
    fi

    source /etc/os-release

    # 安装 chrony
    if ! command -v chronyc &> /dev/null; then
        log_info "安装 chrony..."
        yum install -y chrony || error_exit "安装 chrony 失败"
    else
        log_info "chrony 已安装"
    fi

    # 启动并启用 chrony
    systemctl enable chronyd
    systemctl start chronyd
    systemctl status chronyd --no-pager || log_warn "chronyd 状态检查失败"

    # 等待时间同步
    sleep 3
    chronyc tracking || log_warn "无法获取时间同步状态"
    
    log_info "时间同步配置完成"
}

################################################################################
# 函数：设置主机名
################################################################################

configure_hostname() {
    if [[ -n "${HOSTNAME}" ]]; then
        log_step "设置主机名: ${HOSTNAME}"
        hostnamectl set-hostname "${HOSTNAME}"
        log_info "主机名已设置为: $(hostname)"
    else
        log_info "未指定主机名，跳过设置"
    fi
}

################################################################################
# 函数：配置 hosts 文件
################################################################################

configure_hosts() {
    if [[ ${#HOSTS_ENTRIES[@]} -gt 0 ]]; then
        log_step "配置 /etc/hosts"
        
        # 备份 hosts 文件
        cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d-%H%M%S)
        
        # 添加集群节点条目
        for entry in "${HOSTS_ENTRIES[@]}"; do
            local ip=$(echo "${entry}" | awk '{print $1}')
            local host=$(echo "${entry}" | awk '{print $2}')
            
            if grep -q "${host}" /etc/hosts; then
                log_warn "主机 ${host} 已存在于 /etc/hosts，跳过"
            else
                echo "${entry}" >> /etc/hosts
                log_info "已添加: ${entry}"
            fi
        done
    else
        log_info "未指定 hosts 条目，跳过配置"
    fi
}

################################################################################
# 函数：安装基础工具
################################################################################

install_base_tools() {
    log_step "安装基础工具"

    local tools=("curl" "wget" "vim" "git" "socat" "conntrack" "ipset" "ipvsadm")
    
    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_info "安装 ${tool}..."
            yum install -y "${tool}" || log_warn "安装 ${tool} 失败"
        else
            log_info "${tool} 已安装"
        fi
    done
}

################################################################################
# 函数：配置 IPVS 模块
################################################################################

configure_ipvs() {
    log_step "配置 IPVS 模块"

    # IPVS 模块列表
    local ipvs_modules=(
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
        "nf_conntrack"
    )

    # 加载 IPVS 模块
    for module in "${ipvs_modules[@]}"; do
        modprobe "${module}" 2>/dev/null || log_warn "无法加载模块: ${module}"
    done

    # 确保模块开机自动加载
    cat > /etc/modules-load.d/ipvs.conf <<EOF
# IPVS 模块配置
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

    log_info "IPVS 模块配置完成"
}

################################################################################
# 函数：系统优化
################################################################################

system_optimization() {
    log_step "系统优化配置"

    # 配置 limits
    cat > /etc/security/limits.d/k8s.conf <<EOF
# Kubernetes 系统限制配置
* soft nofile 655360
* hard nofile 655360
* soft nproc 655360
* hard nproc 655360
* soft memlock unlimited
* hard memlock unlimited
EOF

    log_info "系统资源限制配置完成"
}

################################################################################
# 函数：验证配置
################################################################################

verify_configuration() {
    log_step "验证配置"

    local errors=0

    # 检查 SELinux
    if [[ "$(getenforce)" != "Disabled" ]] && [[ "$(getenforce)" != "Permissive" ]]; then
        log_error "SELinux 仍然启用"
        ((errors++))
    else
        log_info "✓ SELinux 已禁用"
    fi

    # 检查 swap
    if swapon -s | grep -q "/"; then
        log_error "swap 仍然启用"
        ((errors++))
    else
        log_info "✓ swap 已禁用"
    fi

    # 检查防火墙
    if systemctl is-active --quiet firewalld; then
        log_error "firewalld 仍在运行"
        ((errors++))
    else
        log_info "✓ firewalld 已停止"
    fi

    # 检查 br_netfilter 模块
    if ! lsmod | grep -q br_netfilter; then
        log_error "br_netfilter 模块未加载"
        ((errors++))
    else
        log_info "✓ br_netfilter 模块已加载"
    fi

    # 检查内核参数
    if [[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null)" != "1" ]]; then
        log_error "net.bridge.bridge-nf-call-iptables 未正确配置"
        ((errors++))
    else
        log_info "✓ 内核参数已正确配置"
    fi

    if [[ ${errors} -gt 0 ]]; then
        log_warn "验证发现 ${errors} 个问题，请检查"
    else
        log_info "✓ 所有配置验证通过"
    fi

    return ${errors}
}

################################################################################
# 函数：显示摘要
################################################################################

show_summary() {
    log_step "配置摘要"

    echo "" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "系统准备完成！" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "操作系统: $(source /etc/os-release; echo ${NAME} ${VERSION})" | tee -a "${LOG_FILE}"
    echo "主机名: $(hostname)" | tee -a "${LOG_FILE}"
    echo "IP 地址: $(hostname -I | awk '{print $1}')" | tee -a "${LOG_FILE}"
    echo "日志文件: ${LOG_FILE}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "下一步操作：" | tee -a "${LOG_FILE}"
    echo "  1. 如果 SELinux 配置有变更，建议重启系统" | tee -a "${LOG_FILE}"
    echo "  2. 运行 install-docker-k8s.sh 安装 Docker 和 Kubernetes" | tee -a "${LOG_FILE}"
    echo "========================================" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"

    # 检查是否需要重启
    if ! grep -q "^SELINUX=disabled" /etc/selinux/config; then
        if [[ "${SKIP_REBOOT_CHECK}" == false ]]; then
            log_warn "建议重启系统以使 SELinux 配置生效"
            read -p "是否立即重启？(y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "系统将在 10 秒后重启..."
                sleep 10
                reboot
            fi
        fi
    fi
}

################################################################################
# 主函数
################################################################################

main() {
    echo -e "${BLUE}"
    echo "========================================"
    echo "  Kubernetes 系统准备脚本"
    echo "  版本: 1.0.0"
    echo "========================================"
    echo -e "${NC}"

    parse_args "$@"
    check_environment
    disable_selinux
    disable_firewall
    disable_swap
    configure_kernel_params
    configure_ipvs
    configure_chrony
    configure_hostname
    configure_hosts
    install_base_tools
    system_optimization
    verify_configuration
    show_summary

    log_info "脚本执行完成！"
}

# 执行主函数
main "$@"
