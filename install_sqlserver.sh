#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

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
        log_info "检测到系统: $NAME $VERSION"
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    
    # 检查系统是否支持
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_error "此脚本仅支持Ubuntu和Debian系统"
        exit 1
    fi
}

# 获取SA密码
get_sa_password() {
    while true; do
        echo -n -e "${YELLOW}请输入SQL Server SA用户的密码 (至少8个字符，包含大小写字母和数字): ${NC}"
        read -s password
        echo
        
        # 密码强度检查
        if [ ${#password} -lt 8 ]; then
            log_error "密码长度至少需要8个字符"
            continue
        fi
        
        # 检查是否包含数字
        if ! echo "$password" | grep -q '[0-9]'; then
            log_error "密码必须包含至少一个数字"
            continue
        fi
        
        # 检查是否包含大写字母
        if ! echo "$password" | grep -q '[A-Z]'; then
            log_error "密码必须包含至少一个大写字母"
            continue
        fi
        
        # 检查是否包含小写字母
        if ! echo "$password" | grep -q '[a-z]'; then
            log_error "密码必须包含至少一个小写字母"
            continue
        fi
        
        echo -n -e "${YELLOW}请确认密码: ${NC}"
        read -s password_confirm
        echo
        
        if [ "$password" = "$password_confirm" ]; then
            SA_PASSWORD=$password
            log_info "密码设置成功"
            break
        else
            log_error "两次输入的密码不一致，请重新输入"
        fi
    done
}

# 更新系统和安装必要工具
update_system() {
    log_step "更新系统包列表..."
    apt-get update -y
    
    log_step "安装必要工具..."
    apt-get install -y curl wget gnupg software-properties-common apt-transport-https ca-certificates
    
    # 安装lsb-release（如果不存在）
    if ! command -v lsb_release &> /dev/null; then
        apt-get install -y lsb-release
    fi
}

# 尝试原生安装SQL Server 2019
install_native_sqlserver() {
    log_step "尝试原生安装SQL Server 2019..."
    
    # 导入Microsoft GPG密钥（非交互式）
    log_step "导入Microsoft GPG密钥..."
    if [ -f '/usr/share/keyrings/microsoft-prod.gpg' ]; then
        rm -f /usr/share/keyrings/microsoft-prod.gpg
    fi
    
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-prod.gpg
    chmod 644 /usr/share/keyrings/microsoft-prod.gpg
    
    # 添加SQL Server仓库
    log_step "添加SQL Server仓库..."
    if [ -f '/etc/apt/sources.list.d/mssql-server-2019.list' ]; then
        rm -f /etc/apt/sources.list.d/mssql-server-2019.list
    fi
    
    if [ "$OS" = "ubuntu" ]; then
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/ubuntu/$VERSION/prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/mssql-server-2019.list
    elif [ "$OS" = "debian" ]; then
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/$(lsb_release -rs)/prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/mssql-server-2019.list
    fi
    
    # 更新包列表
    apt-get update -y
    
    # 安装SQL Server
    log_step "安装SQL Server 2019..."
    if apt-get install -y mssql-server; then
        log_info "SQL Server安装成功"
        return 0
    else
        log_error "原生安装SQL Server失败"
        return 1
    fi
}

# 配置SQL Server
configure_sqlserver() {
    log_step "配置SQL Server..."
    
    # 设置SA密码并接受EULA
    /opt/mssql/bin/mssql-conf setup << EOF
1
2
$SA_PASSWORD
$SA_PASSWORD
1
EOF
    
    # 启用远程访问
    log_step "启用远程访问..."
    /opt/mssql/bin/mssql-conf set telemetry.customerfeedback false
    /opt/mssql/bin/mssql-conf set network.tcpport 1433
    
    # 重启服务使配置生效
    systemctl restart mssql-server
    
    # 启用SQL Server服务开机自启
    systemctl enable mssql-server
    
    # 安装SQL Server命令行工具
    log_step "安装SQL Server命令行工具..."
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
    curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list > /etc/apt/sources.list.d/msprod.list
    apt-get update -y
    ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev
    
    # 添加工具到PATH
    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> /etc/profile
    source /etc/profile
    
    # 配置远程访问
    log_step "配置防火墙和远程访问..."
    
    # 开启防火墙端口（如果防火墙已启用）
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw allow 1433/tcp
        ufw reload
    fi
    
    # 使用sqlcmd配置远程访问
    /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -Q "
    EXEC sp_configure 'remote access', 1;
    RECONFIGURE;
    EXEC sp_configure 'remote query timeout', 0;
    RECONFIGURE;
    EXEC sp_configure 'remote admin connections', 1;
    RECONFIGURE;
    EXEC sp_configure 'show advanced options', 1;
    RECONFIGURE;
    EXEC sp_configure 'max server memory (MB)', 900;
    RECONFIGURE;
    "
}

# 安装Docker
install_docker() {
    log_step "安装Docker..."
    
    # 卸载旧版本
    apt-get remove -y docker docker-engine docker.io containerd runc
    
    # 安装依赖
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # 添加Docker官方GPG密钥
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 添加Docker仓库
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
    apt-get update -y
    
    # 安装Docker
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # 配置国内镜像源
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ]
}
EOF
    
    # 启动Docker服务
    systemctl start docker
    systemctl enable docker
}

# 使用Docker安装SQL Server
install_docker_sqlserver() {
    log_step "使用Docker安装SQL Server 2019..."
    
    # 拉取SQL Server 2019镜像
    log_step "拉取SQL Server 2019镜像..."
    docker pull mcr.microsoft.com/mssql/server:2019-latest
    
    # 创建数据目录
    mkdir -p /var/mssql/data
    mkdir -p /var/mssql/log
    mkdir -p /var/mssql/secrets
    
    # 设置目录权限
    chmod 777 -R /var/mssql
    
    # 运行SQL Server容器（为1H1G小服务器优化配置）
    log_step "启动SQL Server容器..."
    docker run -d \
        --name mssql-server \
        --restart unless-stopped \
        --memory="1g" \
        --memory-swap="1g" \
        --cpus="1" \
        -e "ACCEPT_EULA=Y" \
        -e "SA_PASSWORD=$SA_PASSWORD" \
        -e "MSSQL_PID=Express" \
        -e "MSSQL_MEMORY_LIMIT_MB=900" \
        -e "MSSQL_TCP_PORT=1433" \
        -p 1433:1433 \
        -v /var/mssql/data:/var/opt/mssql/data \
        -v /var/mssql/log:/var/opt/mssql/log \
        -v /var/mssql/secrets:/var/opt/mssql/secrets \
        mcr.microsoft.com/mssql/server:2019-latest
    
    # 等待容器启动
    sleep 10
    
    # 检查容器状态
    if docker ps | grep -q mssql-server; then
        log_info "Docker SQL Server容器启动成功"
        
        # 启用远程访问
        log_step "配置远程访问..."
        docker exec mssql-server /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -Q "
        EXEC sp_configure 'remote access', 1;
        RECONFIGURE;
        EXEC sp_configure 'remote query timeout', 0;
        RECONFIGURE;
        EXEC sp_configure 'remote admin connections', 1;
        RECONFIGURE;
        EXEC sp_configure 'show advanced options', 1;
        RECONFIGURE;
        "
        return 0
    else
        log_error "Docker SQL Server容器启动失败"
        docker logs mssql-server
        return 1
    fi
}

# 验证安装
verify_installation() {
    log_step "验证SQL Server安装..."
    
    sleep 5
    
    # 检查端口监听
    if ss -tlnp | grep -q ':1433'; then
        log_info "SQL Server正在监听端口 1433"
    else
        log_error "SQL Server未在端口 1433 上监听"
        return 1
    fi
    
    # 检查服务状态
    if command -v systemctl &> /dev/null && systemctl is-active --quiet mssql-server 2>/dev/null; then
        log_info "SQL Server服务正在运行"
        return 0
    elif docker ps | grep -q mssql-server; then
        log_info "Docker SQL Server容器正在运行"
        return 0
    else
        log_error "SQL Server服务未运行"
        return 1
    fi
}

# 显示安装结果
show_result() {
    echo ""
    log_step "="
    log_step "安装完成！"
    log_step "="
    echo ""
    
    log_info "SQL Server 2019 安装信息:"
    echo ""
    log_info "服务器地址: localhost 或 $(hostname -I | awk '{print $1}')"
    log_info "端口: 1433"
    log_info "用户名: SA"
    log_info "密码: 您设置的密码"
    echo ""
    log_info "连接字符串:"
    log_info "Server=localhost,1433;Database=master;User Id=SA;Password=您的密码;"
    echo ""
    log_info "管理命令:"
    
    if command -v systemctl &> /dev/null && systemctl list-unit-files | grep -q mssql-server; then
        log_info "启动服务: systemctl start mssql-server"
        log_info "停止服务: systemctl stop mssql-server"
        log_info "重启服务: systemctl restart mssql-server"
        log_info "查看状态: systemctl status mssql-server"
    elif docker ps | grep -q mssql-server; then
        log_info "启动容器: docker start mssql-server"
        log_info "停止容器: docker stop mssql-server"
        log_info "重启容器: docker restart mssql-server"
        log_info "查看日志: docker logs mssql-server"
        log_info "进入容器: docker exec -it mssql-server /bin/bash"
    fi
    
    echo ""
    log_info "数据文件位置:"
    if [ -d "/var/opt/mssql" ]; then
        log_info "/var/opt/mssql/data"
    elif [ -d "/var/mssql" ]; then
        log_info "/var/mssql/data"
    fi
    echo ""
}

# 主函数
main() {
    clear
    log_step "开始安装 SQL Server 2019"
    log_step "=========================="
    echo ""
    
    # 检查root权限
    check_root
    
    # 检测操作系统
    detect_os
    
    # 获取SA密码
    get_sa_password
    
    # 更新系统
    update_system
    
    # 尝试原生安装
    log_step "尝试方法一: 原生安装SQL Server 2019"
    if install_native_sqlserver; then
        # 配置原生SQL Server
        configure_sqlserver
    else
        log_warn "原生安装失败，尝试方法二: Docker安装"
        
        # 安装Docker
        install_docker
        
        # 使用Docker安装SQL Server
        if install_docker_sqlserver; then
            log_info "Docker安装成功"
        else
            log_error "所有安装方法均失败"
            exit 1
        fi
    fi
    
    # 验证安装
    if verify_installation; then
        show_result
    else
        log_error "安装验证失败，请检查日志"
        exit 1
    fi
}

# 执行主函数
main "$@"