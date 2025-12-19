#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_menu() { echo -e "${PURPLE}[MENU]${NC} $1"; }

# 配置文件
CONFIG_FILE="/etc/server_manager.conf"

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        log_info "请尝试: sudo bash $0"
        exit 1
    fi
}

# 检测系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        log_info "系统信息: $NAME $VERSION"
        return 0
    else
        log_error "无法检测操作系统"
        return 1
    fi
}

# 等待用户确认
confirm() {
    echo -n -e "${YELLOW}$1 (y/N): ${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# 1. 安装宝塔面板
install_bt_panel() {
    clear
    log_step "安装宝塔面板"
    log_step "============="
    echo ""
    
    log_info "使用 bt11.bthappy.com 提供的宝塔安装脚本"
    log_warn "注意：宝塔面板会安装较多组件，可能需要较长时间"
    echo ""
    
    if confirm "确定要安装宝塔面板吗？"; then
        log_step "开始安装宝塔面板..."
        
        # 使用提供的安装脚本
        if [ -f /usr/bin/curl ]; then
            curl -sSO https://bt11.bthappy.com/install/install_panel.sh
        else
            wget -O install_panel.sh https://bt11.bthappy.com/install/install_panel.sh
        fi
        
        if [ -f "install_panel.sh" ]; then
            log_info "下载安装脚本成功"
            echo -e "${YELLOW}正在执行宝塔面板安装脚本...${NC}"
            echo ""
            
            # 执行安装脚本
            bash install_panel.sh bt11.bthappy.com
            
            echo ""
            log_info "宝塔面板安装脚本执行完成"
            log_info "如果安装成功，请记下面板地址和账号密码"
            log_warn "建议立即修改默认密码和端口"
        else
            log_error "下载安装脚本失败"
            return 1
        fi
    else
        log_info "取消安装宝塔面板"
    fi
}

# 2. Docker更换国内安装源
change_docker_mirror() {
    clear
    log_step "Docker更换国内镜像源"
    log_step "====================="
    echo ""
    
    # 检查Docker是否安装
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先安装Docker"
        if confirm "是否现在安装Docker？"; then
            install_docker
            return 0
        else
            return 1
        fi
    fi
    
    log_info "当前Docker版本: $(docker --version | cut -d' ' -f3 | tr ',' ' ')"
    echo ""
    
    log_menu "选择镜像源:"
    log_info "1. 阿里云镜像源"
    log_info "2. 腾讯云镜像源"
    log_info "3. 华为云镜像源"
    log_info "4. 中科大镜像源"
    log_info "5. 网易镜像源"
    log_info "6. 百度云镜像源"
    log_info "7. 自定义镜像源"
    echo ""
    
    read -p "请选择镜像源 (1-7): " mirror_choice
    
    case $mirror_choice in
        1)
            MIRROR_URL="https://<your-id>.mirror.aliyuncs.com"
            log_warn "请将 <your-id> 替换为您的阿里云容器镜像服务实例ID"
            log_info "阿里云控制台地址: https://cr.console.aliyun.com"
            echo -n -e "${YELLOW}请输入阿里云镜像加速地址: ${NC}"
            read -r aliyun_mirror
            [ -n "$aliyun_mirror" ] && MIRROR_URL="$aliyun_mirror"
            ;;
        2)
            MIRROR_URL="https://mirror.ccs.tencentyun.com"
            ;;
        3)
            MIRROR_URL="https://<your-id>.swr.myhuaweicloud.com"
            log_warn "请将 <your-id> 替换为您的华为云SWR镜像仓库地址"
            echo -n -e "${YELLOW}请输入华为云镜像加速地址: ${NC}"
            read -r huawei_mirror
            [ -n "$huawei_mirror" ] && MIRROR_URL="$huawei_mirror"
            ;;
        4)
            MIRROR_URL="https://docker.mirrors.ustc.edu.cn"
            ;;
        5)
            MIRROR_URL="http://hub-mirror.c.163.com"
            ;;
        6)
            MIRROR_URL="https://mirror.baidubce.com"
            ;;
        7)
            echo -n -e "${YELLOW}请输入自定义镜像源地址: ${NC}"
            read -r custom_mirror
            MIRROR_URL="$custom_mirror"
            ;;
        *)
            log_error "无效选项"
            return 1
            ;;
    esac
    
    # 创建Docker配置目录
    mkdir -p /etc/docker
    
    # 检查是否已有配置
    if [ -f "/etc/docker/daemon.json" ]; then
        log_info "备份现有配置文件..."
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%Y%m%d%H%M%S)
    fi
    
    # 创建新配置
    cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": ["$MIRROR_URL"],
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
    
    log_info "Docker镜像源已设置为: $MIRROR_URL"
    
    # 重启Docker服务
    log_step "重启Docker服务使配置生效..."
    systemctl daemon-reload
    systemctl restart docker
    
    if systemctl is-active --quiet docker; then
        log_info "Docker服务重启成功"
        docker info | grep -A 5 "Registry Mirrors"
    else
        log_error "Docker服务重启失败"
        return 1
    fi
}

# 安装Docker
install_docker() {
    log_step "安装Docker..."
    
    case $OS in
        ubuntu|debian)
            # 卸载旧版本
            apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            
            # 安装依赖
            apt-get update -y
            apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            
            # 添加Docker官方GPG密钥
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            
            # 添加Docker仓库
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
            
            # 安装Docker
            apt-get update -y
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            
            # 启动服务
            systemctl start docker
            systemctl enable docker
            ;;
        centos|rhel)
            # 卸载旧版本
            yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
            
            # 安装依赖
            yum install -y yum-utils device-mapper-persistent-data lvm2
            
            # 添加Docker仓库
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # 安装Docker
            yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            
            # 启动服务
            systemctl start docker
            systemctl enable docker
            ;;
        *)
            log_error "不支持的系统类型: $OS"
            return 1
            ;;
    esac
    
    # 将当前用户加入docker组
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker "$SUDO_USER"
        log_info "已将用户 $SUDO_USER 添加到docker组"
    fi
    
    log_info "Docker安装完成: $(docker --version)"
}

# 3. 1Panel面板安装
install_1panel() {
    clear
    log_step "安装 1Panel 面板"
    log_step "================="
    echo ""
    
    log_info "1Panel 是一个现代化、开源的 Linux 服务器运维管理面板"
    log_info "官方网站: https://1panel.cn"
    echo ""
    
    if confirm "确定要安装 1Panel 面板吗？"; then
        log_step "开始安装 1Panel..."
        
        log_info "使用官方快速安装脚本..."
        log_info "执行命令: bash -c \"\$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)\""
        echo ""
        
        echo -e "${YELLOW}正在执行 1Panel 安装脚本...${NC}"
        echo ""
        
        # 执行1Panel安装脚本
        bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
        
        echo ""
        log_info "1Panel 安装脚本执行完成"
        log_info "请根据安装完成后的提示信息访问面板"
    else
        log_info "取消安装 1Panel"
    fi
}

# 4. BBR加速脚本
install_bbr() {
    clear
    log_step "安装 BBR 网络加速"
    log_step "==================="
    echo ""
    
    log_info "BBR (Bottleneck Bandwidth and RTT) 是Google开发的TCP拥塞控制算法"
    log_info "可以显著提升网络连接速度，特别是在高延迟或丢包的网络环境中"
    echo ""
    
    if confirm "确定要安装/启用 BBR 吗？"; then
        # 检测内核版本
        KERNEL_VERSION=$(uname -r | cut -d. -f1-2)
        REQUIRED_VERSION="4.9"
        
        log_info "当前内核版本: $(uname -r)"
        
        if (( $(echo "$KERNEL_VERSION >= $REQUIRED_VERSION" | bc -l) )); then
            log_info "内核版本满足 BBR 要求"
        else
            log_warn "内核版本较低，建议升级内核以获得更好的 BBR 效果"
            if confirm "是否升级内核？"; then
                upgrade_kernel
            fi
        fi
        
        # 启用BBR
        log_step "配置 BBR 参数..."
        
        # 备份原有配置
        cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S)
        
        # 添加BBR配置
        cat >> /etc/sysctl.conf << EOF

# BBR Configuration
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3

# Network optimization
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
EOF
        
        # 应用配置
        sysctl -p
        
        # 检查是否启用成功
        log_step "验证 BBR 状态..."
        echo ""
        log_info "当前拥塞控制算法:"
        sysctl net.ipv4.tcp_congestion_control
        
        echo ""
        log_info "队列规则:"
        sysctl net.core.default_qdisc
        
        echo ""
        log_info "BBR 模块状态:"
        lsmod | grep bbr || log_warn "BBR 模块未加载，可能需要重启系统"
        
        echo ""
        log_warn "BBR 已配置，部分参数需要重启系统才能完全生效"
        if confirm "是否现在重启系统？"; then
            reboot
        fi
    else
        log_info "取消安装 BBR"
    fi
}

# 升级内核
upgrade_kernel() {
    log_step "升级系统内核..."
    
    case $OS in
        ubuntu)
            # Ubuntu内核升级
            apt-get update -y
            apt-get install -y --install-recommends linux-generic-hwe-$(lsb_release -rs)
            ;;
        debian)
            # Debian内核升级
            apt-get update -y
            apt-get install -y linux-image-amd64
            ;;
        centos)
            # CentOS内核升级
            yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
            yum --enablerepo=elrepo-kernel install -y kernel-ml
            # 更新GRUB配置
            grub2-mkconfig -o /boot/grub2/grub.cfg
            grub2-set-default 0
            ;;
        *)
            log_error "不支持的系统类型: $OS"
            return 1
            ;;
    esac
    
    log_warn "内核升级完成，需要重启系统生效"
    log_info "当前内核: $(uname -r)"
    log_info "新内核将在重启后生效"
    
    if confirm "是否现在重启系统？"; then
        reboot
    fi
}

# 5. 安装常用工具
install_common_tools() {
    clear
    log_step "安装常用工具集"
    log_step "==============="
    echo ""
    
    log_menu "请选择要安装的工具类别:"
    log_info "1. 系统监控工具"
    log_info "2. 网络工具"
    log_info "3. 开发工具"
    log_info "4. 安全工具"
    log_info "5. 全部安装"
    log_info "0. 返回主菜单"
    echo ""
    
    read -p "请选择 (0-5): " tool_choice
    
    case $tool_choice in
        1)
            install_monitoring_tools
            ;;
        2)
            install_network_tools
            ;;
        3)
            install_dev_tools
            ;;
        4)
            install_security_tools
            ;;
        5)
            install_all_tools
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选项"
            return 1
            ;;
    esac
}

# 安装监控工具
install_monitoring_tools() {
    log_step "安装系统监控工具..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y htop iotop iftop nload nmon glances dstat sysstat netdata
            
            # 启动netdata
            systemctl enable netdata
            systemctl start netdata
            log_info "Netdata 监控面板: http://服务器IP:19999"
            ;;
        centos|rhel)
            yum install -y epel-release
            yum install -y htop iotop iftop nload nmon glances dstat sysstat
            ;;
    esac
    
    log_info "监控工具安装完成"
    log_info "常用命令:"
    log_info "  htop    - 进程监控"
    log_info "  iotop   - 磁盘IO监控"
    log_info "  iftop   - 网络流量监控"
    log_info "  nmon    - 系统性能监控"
    log_info "  glances - 综合监控面板"
}

# 安装网络工具
install_network_tools() {
    log_step "安装网络工具..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y net-tools traceroute mtr nmap tcpdump iperf3 curl wget dnsutils nginx apache2-utils
            ;;
        centos|rhel)
            yum install -y net-tools traceroute mtr nmap tcpdump iperf3 curl wget bind-utils nginx httpd-tools
            ;;
    esac
    
    log_info "网络工具安装完成"
}

# 安装开发工具
install_dev_tools() {
    log_step "安装开发工具..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y git vim nano build-essential python3 python3-pip nodejs npm golang jq yq
            
            # 安装Docker Compose
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            ;;
        centos|rhel)
            yum install -y git vim nano gcc-c++ make python3 python3-pip nodejs npm golang jq
            
            # 安装yq
            wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
            chmod +x /usr/local/bin/yq
            
            # 安装Docker Compose
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            ;;
    esac
    
    log_info "开发工具安装完成"
}

# 安装安全工具
install_security_tools() {
    log_step "安装安全工具..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y fail2ban ufw lynis rkhunter chkrootkit clamav
            
            # 配置fail2ban
            systemctl enable fail2ban
            systemctl start fail2ban
            
            # 配置UFW防火墙
            ufw --force enable
            ufw default deny incoming
            ufw default allow outgoing
            ufw allow ssh
            ufw allow 22/tcp
            ufw reload
            ;;
        centos|rhel)
            yum install -y fail2ban epel-release
            yum install -y lynis rkhunter chkrootkit clamav
            
            # 配置fail2ban
            systemctl enable fail2ban
            systemctl start fail2ban
            
            # 配置firewalld
            systemctl enable firewalld
            systemctl start firewalld
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --reload
            ;;
    esac
    
    log_info "安全工具安装完成"
    log_warn "建议立即修改SSH端口和配置密钥登录"
}

# 安装所有工具
install_all_tools() {
    install_monitoring_tools
    install_network_tools
    install_dev_tools
    install_security_tools
}

# 6. 系统优化
optimize_system() {
    clear
    log_step "系统性能优化"
    log_step "============="
    echo ""
    
    log_menu "请选择优化选项:"
    log_info "1. 优化系统参数"
    log_info "2. 优化SSH配置"
    log_info "3. 优化文件描述符限制"
    log_info "4. 优化SWAP设置"
    log_info "5. 清理系统垃圾"
    log_info "6. 查看当前优化状态"
    log_info "0. 返回主菜单"
    echo ""
    
    read -p "请选择 (0-6): " optimize_choice
    
    case $optimize_choice in
        1)
            optimize_sysctl
            ;;
        2)
            optimize_ssh
            ;;
        3)
            optimize_file_limit
            ;;
        4)
            optimize_swap
            ;;
        5)
            cleanup_system
            ;;
        6)
            show_optimization_status
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选项"
            return 1
            ;;
    esac
}

# 优化系统参数
optimize_sysctl() {
    log_step "优化系统内核参数..."
    
    # 备份原有配置
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S)
    
    # 添加优化参数
    cat >> /etc/sysctl.conf << 'EOF'

# 系统性能优化
# 减少TIME_WAIT连接
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 1

# 增加TCP缓冲区大小
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 增加连接队列
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# 防御SYN洪水攻击
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# 加快ARP缓存过期
net.ipv4.neigh.default.gc_stale_time = 120

# 禁用IPv6（如果需要）
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1
# net.ipv6.conf.lo.disable_ipv6 = 1

EOF
    
    # 应用配置
    sysctl -p
    log_info "系统内核参数优化完成"
}

# 优化SSH配置
optimize_ssh() {
    log_step "优化SSH配置..."
    
    # 备份原有配置
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)
    
    echo ""
    log_menu "请选择SSH优化选项:"
    log_info "1. 仅密钥登录 (最安全)"
    log_info "2. 密钥+密码登录 (推荐)"
    log_info "3. 仅修改端口 (基础)"
    echo ""
    
    read -p "请选择 (1-3): " ssh_choice
    
    # 获取当前SSH端口
    CURRENT_PORT=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -1)
    CURRENT_PORT=${CURRENT_PORT:-22}
    
    echo -n -e "${YELLOW}请输入新的SSH端口 (当前: $CURRENT_PORT): ${NC}"
    read -r NEW_PORT
    NEW_PORT=${NEW_PORT:-$CURRENT_PORT}
    
    # 创建新的SSH配置
    cat > /etc/ssh/sshd_config << EOF
# SSH服务器配置
Port $NEW_PORT
ListenAddress 0.0.0.0
Protocol 2

# 认证设置
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# 密码策略
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# 连接设置
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10

# 安全设置
UsePAM yes
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes

# 日志设置
SyslogFacility AUTH
LogLevel INFO

# 其他设置
X11Forwarding no
AllowTcpForwarding yes
AllowAgentForwarding yes
Compression delayed
EOF
    
    # 根据选择调整配置
    case $ssh_choice in
        1)
            # 仅密钥登录
            sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
            log_info "已设置为仅密钥登录"
            ;;
        2)
            # 密钥+密码登录
            log_info "已设置为密钥+密码登录"
            ;;
        3)
            # 仅修改端口
            log_info "仅修改SSH端口"
            ;;
    esac
    
    # 重启SSH服务
    systemctl restart sshd
    
    # 配置防火墙
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw allow $NEW_PORT/tcp
        ufw reload
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$NEW_PORT/tcp
        firewall-cmd --reload
    fi
    
    log_info "SSH配置优化完成"
    log_info "新SSH端口: $NEW_PORT"
    log_warn "请确保已保存SSH密钥或记住新端口，以免被锁在服务器外"
}

# 优化文件描述符限制
optimize_file_limit() {
    log_step "优化文件描述符限制..."
    
    # 备份原有配置
    cp /etc/security/limits.conf /etc/security/limits.conf.bak.$(date +%Y%m%d%H%M%S)
    
    # 添加新的限制
    cat >> /etc/security/limits.conf << 'EOF'

# 系统文件描述符限制
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535

# MySQL优化（如果存在）
mysql soft nofile 65535
mysql hard nofile 65535

# Nginx优化（如果存在）
nginx soft nofile 65535
nginx hard nofile 65535

EOF
    
    # 添加系统级限制
    cat > /etc/sysctl.d/file-limits.conf << 'EOF'
fs.file-max = 2097152
fs.nr_open = 2097152
EOF
    
    sysctl -p /etc/sysctl.d/file-limits.conf
    
    log_info "文件描述符限制优化完成"
    log_info "需要重新登录才能生效"
}

# 优化SWAP设置
optimize_swap() {
    log_step "优化SWAP设置..."
    
    echo ""
    log_menu "请选择SWAP操作:"
    log_info "1. 创建/增加SWAP"
    log_info "2. 优化SWAP参数"
    log_info "3. 查看当前SWAP"
    echo ""
    
    read -p "请选择 (1-3): " swap_choice
    
    case $swap_choice in
        1)
            echo -n -e "${YELLOW}请输入SWAP大小 (单位: GB，建议为内存的1-2倍): ${NC}"
            read -r swap_size
            swap_size=${swap_size:-2}
            
            # 检查现有SWAP
            if [ -f /swapfile ]; then
                log_warn "已存在swapfile，将删除并重新创建"
                swapoff /swapfile
                rm -f /swapfile
            fi
            
            # 创建SWAP文件
            log_step "创建 ${swap_size}GB SWAP文件..."
            fallocate -l ${swap_size}G /swapfile
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            
            # 添加到fstab
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
            
            log_info "SWAP创建完成: ${swap_size}GB"
            ;;
        2)
            # 优化SWAP参数
            cat >> /etc/sysctl.conf << 'EOF'

# SWAP优化
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2

EOF
            sysctl -p
            log_info "SWAP参数优化完成"
            ;;
        3)
            # 查看当前SWAP
            log_info "当前SWAP信息:"
            swapon --show
            echo ""
            free -h
            ;;
    esac
}

# 清理系统垃圾
cleanup_system() {
    log_step "清理系统垃圾..."
    
    echo ""
    log_menu "请选择清理选项:"
    log_info "1. 清理APT/YUM缓存"
    log_info "2. 清理日志文件"
    log_info "3. 清理临时文件"
    log_info "4. 清理Docker资源"
    log_info "5. 清理孤儿包"
    log_info "6. 全部清理"
    echo ""
    
    read -p "请选择 (1-6): " cleanup_choice
    
    case $cleanup_choice in
        1)
            log_step "清理包管理器缓存..."
            case $OS in
                ubuntu|debian)
                    apt-get clean
                    apt-get autoremove -y
                    apt-get autoclean -y
                    ;;
                centos|rhel)
                    yum clean all
                    yum autoremove -y
                    ;;
            esac
            ;;
        2)
            log_step "清理日志文件..."
            # 保留最近7天的日志
            find /var/log -name "*.log" -type f -mtime +7 -delete
            find /var/log -name "*.gz" -type f -mtime +30 -delete
            # 清理journal日志
            journalctl --vacuum-time=7d
            ;;
        3)
            log_step "清理临时文件..."
            rm -rf /tmp/*
            rm -rf /var/tmp/*
            ;;
        4)
            log_step "清理Docker资源..."
            if command -v docker &> /dev/null; then
                docker system prune -a -f
                docker volume prune -f
            fi
            ;;
        5)
            log_step "清理孤儿包..."
            case $OS in
                ubuntu|debian)
                    apt-get autoremove --purge -y
                    ;;
                centos|rhel)
                    package-cleanup --quiet --leaves | xargs yum remove -y
                    ;;
            esac
            ;;
        6)
            # 全部清理
            cleanup_system_choice 1
            cleanup_system_choice 2
            cleanup_system_choice 3
            cleanup_system_choice 4
            cleanup_system_choice 5
            ;;
    esac
    
    log_info "系统清理完成"
    
    # 查看磁盘空间
    echo ""
    log_info "当前磁盘使用情况:"
    df -h
}

# 显示优化状态
show_optimization_status() {
    log_step "当前系统优化状态:"
    echo ""
    
    log_info "1. 内核参数:"
    sysctl net.ipv4.tcp_fin_timeout net.core.somaxconn vm.swappiness 2>/dev/null
    
    echo ""
    log_info "2. 文件描述符限制:"
    ulimit -n
    
    echo ""
    log_info "3. SWAP信息:"
    swapon --show
    echo ""
    free -h
    
    echo ""
    log_info "4. SSH端口:"
    grep -E "^Port" /etc/ssh/sshd_config 2>/dev/null || echo "使用默认端口 22"
    
    echo ""
    log_info "5. 系统负载:"
    uptime
    echo ""
    top -bn1 | head -5
}

# 7. 安全加固
security_hardening() {
    clear
    log_step "服务器安全加固"
    log_step "================"
    echo ""
    
    log_menu "请选择安全加固选项:"
    log_info "1. 修改SSH端口"
    log_info "2. 禁用root登录"
    log_info "3. 配置防火墙"
    log_info "4. 安装Fail2ban"
    log_info "5. 定期更新系统"
    log_info "6. 检查可疑进程"
    log_info "7. 安全扫描"
    log_info "0. 返回主菜单"
    echo ""
    
    read -p "请选择 (0-7): " security_choice
    
    case $security_choice in
        1)
            # 修改SSH端口已在优化中实现
            optimize_ssh
            ;;
        2)
            disable_root_login
            ;;
        3)
            configure_firewall
            ;;
        4)
            install_fail2ban
            ;;
        5)
            setup_auto_update
            ;;
        6)
            check_suspicious_processes
            ;;
        7)
            security_scan
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选项"
            return 1
            ;;
    esac
}

# 禁用root登录
disable_root_login() {
    log_step "禁用root SSH登录..."
    
    # 先创建普通用户
    echo -n -e "${YELLOW}请输入要创建的管理员用户名: ${NC}"
    read -r admin_user
    
    if id "$admin_user" &>/dev/null; then
        log_info "用户 $admin_user 已存在"
    else
        useradd -m -s /bin/bash "$admin_user"
        passwd "$admin_user"
        usermod -aG sudo "$admin_user"
        log_info "已创建用户 $admin_user 并加入sudo组"
    fi
    
    # 禁用root登录
    sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart sshd
    
    log_info "已禁用root SSH登录"
    log_warn "请确保使用 $admin_user 用户可以正常登录和sudo，再关闭当前root会话"
}

# 配置防火墙
configure_firewall() {
    log_step "配置系统防火墙..."
    
    case $OS in
        ubuntu|debian)
            if ! command -v ufw &> /dev/null; then
                apt-get install -y ufw
            fi
            
            # 启用UFW
            ufw --force enable
            
            # 设置默认策略
            ufw default deny incoming
            ufw default allow outgoing
            
            # 允许SSH
            SSH_PORT=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -1)
            SSH_PORT=${SSH_PORT:-22}
            ufw allow ${SSH_PORT}/tcp
            
            # 允许常用端口
            ufw allow 80/tcp   # HTTP
            ufw allow 443/tcp  # HTTPS
            ufw allow 53/udp   # DNS
            
            ufw reload
            ufw status verbose
            ;;
        centos|rhel)
            if ! command -v firewall-cmd &> /dev/null; then
                yum install -y firewalld
            fi
            
            systemctl enable firewalld
            systemctl start firewalld
            
            # 允许SSH
            SSH_PORT=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -1)
            SSH_PORT=${SSH_PORT:-22}
            firewall-cmd --permanent --add-port=${SSH_PORT}/tcp
            
            # 允许常用服务
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --permanent --add-service=dns
            
            firewall-cmd --reload
            firewall-cmd --list-all
            ;;
    esac
    
    log_info "防火墙配置完成"
}

# 安装Fail2ban
install_fail2ban() {
    log_step "安装和配置Fail2ban..."
    
    case $OS in
        ubuntu|debian)
            apt-get install -y fail2ban
            ;;
        centos|rhel)
            yum install -y fail2ban
            ;;
    esac
    
    # 配置Fail2ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 5

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_info "Fail2ban安装完成"
    fail2ban-client status
}

# 设置自动更新
setup_auto_update() {
    log_step "设置系统自动更新..."
    
    case $OS in
        ubuntu|debian)
            apt-get install -y unattended-upgrades
            
            # 配置自动更新
            cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}:${distro_codename}-updates";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF
            
            cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
            
            systemctl restart unattended-upgrades
            ;;
        centos|rhel)
            yum install -y yum-cron
            sed -i 's/apply_updates = no/apply_updates = yes/' /etc/yum/yum-cron.conf
            systemctl enable yum-cron
            systemctl start yum-cron
            ;;
    esac
    
    log_info "自动更新已配置"
}

# 检查可疑进程
check_suspicious_processes() {
    log_step "检查可疑进程..."
    
    echo ""
    log_info "1. 检查隐藏进程:"
    ps -ef | grep -E "\[|\]"
    
    echo ""
    log_info "2. 检查异常网络连接:"
    netstat -anp | grep -E "ESTABLISHED|LISTEN"
    
    echo ""
    log_info "3. 检查计划任务:"
    crontab -l
    ls -la /etc/cron.*/
    
    echo ""
    log_info "4. 检查SUID文件:"
    find / -perm -4000 -type f 2>/dev/null | head -20
    
    echo ""
    log_warn "以上只是基础检查，建议使用专业安全工具进行深度扫描"
}

# 安全扫描
security_scan() {
    log_step "运行安全扫描..."
    
    echo ""
    log_menu "选择安全扫描工具:"
    log_info "1. Lynis (系统审计)"
    log_info "2. Rkhunter (Rootkit检测)"
    log_info "3. ClamAV (病毒扫描)"
    echo ""
    
    read -p "请选择 (1-3): " scan_choice
    
    case $scan_choice in
        1)
            if ! command -v lynis &> /dev/null; then
                case $OS in
                    ubuntu|debian) apt-get install -y lynis ;;
                    centos|rhel) yum install -y lynis ;;
                esac
            fi
            lynis audit system
            ;;
        2)
            if ! command -v rkhunter &> /dev/null; then
                case $OS in
                    ubuntu|debian) apt-get install -y rkhunter ;;
                    centos|rhel) yum install -y rkhunter ;;
                esac
            fi
            rkhunter --check
            ;;
        3)
            if ! command -v clamscan &> /dev/null; then
                case $OS in
                    ubuntu|debian) apt-get install -y clamav ;;
                    centos|rhel) yum install -y clamav ;;
                esac
                freshclam  # 更新病毒库
            fi
            clamscan -r /home --bell -i
            ;;
    esac
}

# 8. 监控报警
setup_monitoring() {
    clear
    log_step "监控报警设置"
    log_step "=============="
    echo ""
    
    log_menu "请选择监控方案:"
    log_info "1. 安装Netdata (实时监控)"
    log_info "2. 安装Prometheus + Grafana (专业监控)"
    log_info "3. 配置日志监控"
    log_info "4. 设置磁盘空间报警"
    log_info "0. 返回主菜单"
    echo ""
    
    read -p "请选择 (0-4): " monitor_choice
    
    case $monitor_choice in
        1)
            install_netdata
            ;;
        2)
            install_prometheus_grafana
            ;;
        3)
            setup_log_monitoring
            ;;
        4)
            setup_disk_alert
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选项"
            return 1
            ;;
    esac
}

# 安装Netdata
install_netdata() {
    log_step "安装Netdata实时监控..."
    
    # 使用一键安装脚本
    bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait
    
    # 配置邮件报警
    echo ""
    if confirm "是否配置Netdata邮件报警？"; then
        echo -n -e "${YELLOW}请输入收件邮箱: ${NC}"
        read -r email
        
        # 配置SMTP
        cat >> /etc/netdata/health_alarm_notify.conf << EOF
        
# Email配置
DEFAULT_RECIPIENT_EMAIL="$email"
SEND_EMAIL="YES"
EMAIL_SENDER="netdata@$(hostname)"
EMAIL_CHARSET="UTF-8"
EOF
        
        log_info "Netdata报警邮件已配置"
    fi
    
    log_info "Netdata安装完成"
    log_info "访问地址: http://服务器IP:19999"
    log_info "默认无需密码，建议设置访问密码"
}

# 安装Prometheus + Grafana
install_prometheus_grafana() {
    log_step "安装Prometheus + Grafana监控系统..."
    
    if confirm "这将安装完整的监控系统，需要较多资源，确定继续吗？"; then
        # 创建监控目录
        mkdir -p /opt/monitoring
        cd /opt/monitoring || exit
        
        # 下载docker-compose配置
        cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    ports:
      - "9090:9090"
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"
    networks:
      - monitoring
    depends_on:
      - prometheus

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
EOF
        
        # 创建Prometheus配置
        cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
EOF
        
        # 启动服务
        docker-compose up -d
        
        log_info "Prometheus + Grafana 安装完成"
        log_info "Prometheus: http://服务器IP:9090"
        log_info "Grafana: http://服务器IP:3000 (admin/admin123)"
        log_warn "请立即修改Grafana默认密码！"
    else
        log_info "取消安装"
    fi
}

# 配置日志监控
setup_log_monitoring() {
    log_step "配置日志监控..."
    
    # 安装logwatch
    case $OS in
        ubuntu|debian)
            apt-get install -y logwatch
            ;;
        centos|rhel)
            yum install -y logwatch
            ;;
    esac
    
    # 配置每日日志报告
    mkdir -p /etc/logwatch/conf
    cat > /etc/logwatch/conf/logwatch.conf << 'EOF'
LogDir = /var/log
TmpDir = /tmp
MailTo = root
MailFrom = Logwatch
Print = No
Range = yesterday
Detail = Low
Service = All
EOF
    
    # 添加每日任务
    echo "#!/bin/bash
/usr/sbin/logwatch --output mail --mailto root --detail high" > /etc/cron.daily/00logwatch
    chmod +x /etc/cron.daily/00logwatch
    
    log_info "日志监控配置完成"
    log_info "每日日志报告将发送到root邮箱"
}

# 设置磁盘空间报警
setup_disk_alert() {
    log_step "设置磁盘空间报警..."
    
    # 创建监控脚本
    cat > /usr/local/bin/disk_alert.sh << 'EOF'
#!/bin/bash

THRESHOLD=90
EMAIL="root@localhost"

for disk in $(df -P | grep '^/dev' | awk '{print $1}'); do
    usage=$(df -P "$disk" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$usage" -gt "$THRESHOLD" ]; then
        subject="磁盘空间告警: $disk 使用率 ${usage}%"
        message="服务器: $(hostname)
磁盘: $disk
使用率: ${usage}%
时间: $(date)
建议: 请及时清理磁盘空间"
        
        echo "$message" | mail -s "$subject" "$EMAIL"
        echo "$(date): $subject" >> /var/log/disk_alert.log
    fi
done
EOF
    
    chmod +x /usr/local/bin/disk_alert.sh
    
    # 添加到cron，每5分钟检查一次
    echo "*/5 * * * * root /usr/local/bin/disk_alert.sh" > /etc/cron.d/disk_alert
    
    log_info "磁盘空间报警配置完成"
    log_info "当磁盘使用率超过90%时，将发送邮件到root"
}

# 显示主菜单
show_main_menu() {
    clear
    log_step "Linux 服务器通用管理脚本"
    log_step "=========================="
    echo ""
    log_info "系统信息: $(uname -srm)"
    log_info "主机名: $(hostname)"
    log_info "IP地址: $(hostname -I 2>/dev/null | awk '{print $1}' || echo '未知')"
    log_info "负载: $(uptime | awk -F'load average:' '{print $2}')"
    echo ""
    
    log_menu "主菜单选项:"
    echo ""
    log_info "1. 安装宝塔面板"
    log_info "2. Docker更换国内安装源"
    log_info "3. 安装 1Panel 面板"
    log_info "4. BBR 网络加速"
    log_info "5. 安装常用工具集"
    log_info "6. 系统性能优化"
    log_info "7. 服务器安全加固"
    log_info "8. 监控报警设置"
    log_info "9. 查看系统状态"
    log_info "10. 清理系统垃圾"
    log_info "0. 退出脚本"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}请输入选项 (0-10): ${NC}"
        read choice
        
        case $choice in
            1) install_bt_panel ;;
            2) change_docker_mirror ;;
            3) install_1panel ;;
            4) install_bbr ;;
            5) install_common_tools ;;
            6) optimize_system ;;
            7) security_hardening ;;
            8) setup_monitoring ;;
            9) show_system_status ;;
            10) cleanup_system ;;
            0)
                echo ""
                log_info "感谢使用！"
                exit 0
                ;;
            *)
                log_error "无效选项，请重新输入"
                continue
                ;;
        esac
        
        echo ""
        echo -n -e "${YELLOW}按Enter键返回主菜单...${NC}"
        read
        show_main_menu
    done
}

# 显示系统状态
show_system_status() {
    clear
    log_step "系统状态概览"
    log_step "============="
    echo ""
    
    log_info "1. 系统信息:"
    echo "    主机名: $(hostname)"
    echo "    内核版本: $(uname -r)"
    echo "    系统版本: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "    运行时间: $(uptime -p)"
    echo ""
    
    log_info "2. CPU信息:"
    echo "    CPU型号: $(lscpu | grep "Model name" | cut -d':' -f2 | sed 's/^ *//')"
    echo "    CPU核心: $(nproc) 核"
    echo "    负载情况: $(uptime | awk -F'load average:' '{print $2}')"
    echo ""
    
    log_info "3. 内存信息:"
    free -h | sed 's/^/    /'
    echo ""
    
    log_info "4. 磁盘信息:"
    df -h --output=source,fstype,size,used,avail,pcent,target | sed 's/^/    /'
    echo ""
    
    log_info "5. 网络信息:"
    echo "    IP地址: $(hostname -I 2>/dev/null | awk '{print $1}' || echo '未知')"
    echo "    公网IP: $(curl -s ifconfig.me 2>/dev/null || echo '无法获取')"
    echo "    网络连接: $(netstat -an | grep ESTABLISHED | wc -l) 个已建立连接"
    echo ""
    
    log_info "6. 服务状态:"
    echo "    SSH: $(systemctl is-active sshd 2>/dev/null || echo '未安装')"
    echo "    Docker: $(systemctl is-active docker 2>/dev/null || echo '未安装')"
    echo "    Nginx: $(systemctl is-active nginx 2>/dev/null || echo '未安装')"
    echo ""
    
    log_info "7. 安全状态:"
    echo "    Fail2ban: $(systemctl is-active fail2ban 2>/dev/null || echo '未安装')"
    echo "    UFW/Firewalld: $(systemctl is-active ufw 2>/dev/null || systemctl is-active firewalld 2>/dev/null || echo '未启用')"
    echo "    最后登录: $(last -n 3 | head -3)"
}

# 主函数
main() {
    # 检查root权限
    check_root
    
    # 检测系统
    if ! detect_os; then
        exit 1
    fi
    
    # 显示主菜单
    show_main_menu
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    main
fi