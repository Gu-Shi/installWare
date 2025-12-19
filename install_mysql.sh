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
CONFIG_FILE="/etc/mysql_install.conf"
MYSQL_PORT=3306

# 检查是否已安装
check_installed() {
    INSTALLED=false
    INSTALL_TYPE=""
    
    # 检查原生安装
    if systemctl is-active --quiet mysql 2>/dev/null; then
        INSTALLED=true
        INSTALL_TYPE="native"
        log_info "检测到原生MySQL安装"
        return 0
    fi
    
    # 检查Docker安装
    if docker ps --format '{{.Names}}' | grep -q "^mysql57$"; then
        INSTALLED=true
        INSTALL_TYPE="docker"
        log_info "检测到Docker MySQL安装"
        return 0
    fi
    
    # 检查MySQL进程
    if pgrep -x mysqld >/dev/null 2>&1; then
        INSTALLED=true
        INSTALL_TYPE="unknown"
        log_info "检测到MySQL进程运行"
        return 0
    fi
    
    # 检查端口是否被占用
    if ss -tlnp | grep -q ":$MYSQL_PORT "; then
        log_warn "端口 $MYSQL_PORT 已被占用，可能已有MySQL服务"
        INSTALLED=true
        INSTALL_TYPE="port_used"
    fi
    
    return 1
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" << EOF
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
INSTALL_TYPE="$INSTALL_TYPE"
INSTALL_TIME="$(date)"
EOF
    chmod 600 "$CONFIG_FILE"
}

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# 显示管理菜单
show_management_menu() {
    clear
    log_step "MySQL 5.7 管理菜单"
    log_step "===================="
    echo ""
    
    log_menu "请选择操作:"
    echo ""
    log_info "1. 启动MySQL服务"
    log_info "2. 停止MySQL服务"
    log_info "3. 重启MySQL服务"
    log_info "4. 查看服务状态"
    log_info "5. 查看运行日志"
    log_info "6. 开放/关闭防火墙端口"
    log_info "7. 重置管理员密码"
    log_info "8. 备份数据库"
    log_info "9. 恢复数据库"
    log_info "10. 查看连接信息"
    log_info "11. 优化配置"
    log_info "12. 卸载MySQL"
    log_info "0. 退出"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}请输入选项 (0-12): ${NC}"
        read choice
        
        case $choice in
            1) start_mysql ;;
            2) stop_mysql ;;
            3) restart_mysql ;;
            4) show_status ;;
            5) show_logs ;;
            6) manage_firewall ;;
            7) reset_password ;;
            8) backup_database ;;
            9) restore_database ;;
            10) show_connection_info ;;
            11) optimize_config ;;
            12) uninstall_mysql ;;
            0) 
                echo ""
                log_info "退出管理菜单"
                exit 0
                ;;
            *) 
                log_error "无效选项，请重新输入"
                continue
                ;;
        esac
        
        echo ""
        echo -n -e "${YELLOW}按Enter键继续...${NC}"
        read
        show_management_menu
    done
}

# 启动MySQL
start_mysql() {
    log_step "启动MySQL服务..."
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        systemctl start mysql
        if systemctl is-active --quiet mysql; then
            log_info "原生MySQL启动成功"
        else
            log_error "原生MySQL启动失败"
        fi
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        docker start mysql57
        if docker ps | grep -q mysql57; then
            log_info "Docker MySQL启动成功"
        else
            log_error "Docker MySQL启动失败"
        fi
    else
        log_error "未知的安装类型"
    fi
}

# 停止MySQL
stop_mysql() {
    log_step "停止MySQL服务..."
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        systemctl stop mysql
        log_info "原生MySQL已停止"
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        docker stop mysql57
        log_info "Docker MySQL已停止"
    else
        log_error "未知的安装类型"
    fi
}

# 重启MySQL
restart_mysql() {
    log_step "重启MySQL服务..."
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        systemctl restart mysql
        if systemctl is-active --quiet mysql; then
            log_info "原生MySQL重启成功"
        else
            log_error "原生MySQL重启失败"
        fi
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        docker restart mysql57
        if docker ps | grep -q mysql57; then
            log_info "Docker MySQL重启成功"
        else
            log_error "Docker MySQL重启失败"
        fi
    else
        log_error "未知的安装类型"
    fi
}

# 查看状态
show_status() {
    log_step "MySQL服务状态:"
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        systemctl status mysql --no-pager -l
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        docker ps -f name=mysql57
        echo ""
        docker stats mysql57 --no-stream
    else
        log_error "未知的安装类型"
    fi
}

# 查看日志
show_logs() {
    log_step "MySQL日志:"
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        if [ -f "/var/log/mysql/error.log" ]; then
            tail -50 /var/log/mysql/error.log
        else
            journalctl -u mysql -n 50 --no-pager
        fi
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        docker logs mysql57 --tail 50
    else
        log_error "未知的安装类型"
    fi
}

# 管理防火墙
manage_firewall() {
    log_step "管理防火墙端口..."
    
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "active"; then
            echo ""
            log_info "当前防火墙状态:"
            ufw status | grep "$MYSQL_PORT"
            echo ""
            log_menu "请选择操作:"
            log_info "1. 开放端口 $MYSQL_PORT"
            log_info "2. 关闭端口 $MYSQL_PORT"
            log_info "3. 查看防火墙状态"
            echo ""
            
            read -p "请输入选项 (1-3): " fw_choice
            
            case $fw_choice in
                1)
                    ufw allow $MYSQL_PORT/tcp
                    ufw reload
                    log_info "已开放端口 $MYSQL_PORT"
                    ;;
                2)
                    ufw deny $MYSQL_PORT/tcp
                    ufw reload
                    log_info "已关闭端口 $MYSQL_PORT"
                    ;;
                3)
                    ufw status
                    ;;
                *)
                    log_error "无效选项"
                    ;;
            esac
        else
            log_info "防火墙未启用"
        fi
    else
        log_info "未安装UFW防火墙"
        
        # 检查iptables
        if command -v iptables >/dev/null 2>&1; then
            echo ""
            log_info "当前iptables规则:"
            iptables -L -n | grep "$MYSQL_PORT" || echo "未找到相关规则"
        fi
    fi
}

# 重置密码
reset_password() {
    log_step "重置MySQL root密码..."
    
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        log_warn "未找到保存的密码，请手动输入原密码"
        echo -n -e "${YELLOW}请输入当前root密码: ${NC}"
        read -s current_pass
        echo
    else
        current_pass="$MYSQL_ROOT_PASSWORD"
    fi
    
    echo -n -e "${YELLOW}请输入新密码: ${NC}"
    read -s new_pass1
    echo
    echo -n -e "${YELLOW}请确认新密码: ${NC}"
    read -s new_pass2
    echo
    
    if [ "$new_pass1" != "$new_pass2" ]; then
        log_error "两次输入的密码不一致"
        return 1
    fi
    
    if [ ${#new_pass1} -lt 8 ]; then
        log_error "密码长度至少需要8个字符"
        return 1
    fi
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        # 尝试使用mysqladmin
        if mysqladmin -u root -p"$current_pass" password "$new_pass1" 2>/dev/null; then
            MYSQL_ROOT_PASSWORD="$new_pass1"
            save_config
            log_info "密码重置成功"
        else
            log_error "密码重置失败，请检查原密码是否正确"
        fi
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        docker exec mysql57 mysql -u root -p"$current_pass" -e "ALTER USER 'root'@'%' IDENTIFIED BY '$new_pass1';" 2>/dev/null
        if [ $? -eq 0 ]; then
            MYSQL_ROOT_PASSWORD="$new_pass1"
            save_config
            log_info "密码重置成功"
        else
            log_error "密码重置失败，请检查原密码是否正确"
        fi
    else
        log_error "未知的安装类型"
    fi
}

# 备份数据库
backup_database() {
    log_step "备份MySQL数据库..."
    
    local backup_dir="/var/backups/mysql"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/backup_$timestamp.sql"
    
    mkdir -p "$backup_dir"
    
    echo -n -e "${YELLOW}请输入要备份的数据库名 (默认全部): ${NC}"
    read db_name
    
    echo -n -e "${YELLOW}请输入备份文件名 (默认: $backup_file): ${NC}"
    read custom_file
    [ -n "$custom_file" ] && backup_file="$backup_dir/$custom_file"
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        if [ -z "$db_name" ]; then
            mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases --routines --triggers > "$backup_file"
        else
            mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" "$db_name" --routines --triggers > "$backup_file"
        fi
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        if [ -z "$db_name" ]; then
            docker exec mysql57 mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases --routines --triggers > "$backup_file"
        else
            docker exec mysql57 mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" "$db_name" --routines --triggers > "$backup_file"
        fi
    else
        log_error "未知的安装类型"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        gzip "$backup_file"
        log_info "备份成功: ${backup_file}.gz"
        log_info "大小: $(du -h "${backup_file}.gz" | cut -f1)"
    else
        log_error "备份失败"
    fi
}

# 恢复数据库
restore_database() {
    log_step "恢复MySQL数据库..."
    
    local backup_dir="/var/backups/mysql"
    
    if [ ! -d "$backup_dir" ]; then
        log_error "备份目录不存在: $backup_dir"
        return 1
    fi
    
    echo "可用的备份文件:"
    ls -lh "$backup_dir"/*.sql.gz 2>/dev/null | nl || {
        log_error "未找到备份文件"
        return 1
    }
    
    echo -n -e "${YELLOW}请输入备份文件编号: ${NC}"
    read file_num
    
    local backup_files=($(ls "$backup_dir"/*.sql.gz 2>/dev/null))
    if [ -z "${backup_files[$((file_num-1))]}" ]; then
        log_error "无效的文件编号"
        return 1
    fi
    
    local backup_file="${backup_files[$((file_num-1))]}"
    local temp_file="/tmp/restore_$(date +%s).sql"
    
    log_info "正在解压备份文件: $backup_file"
    gunzip -c "$backup_file" > "$temp_file"
    
    echo -n -e "${YELLOW}是否先删除原有数据库? (y/N): ${NC}"
    read drop_option
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        if [[ "$drop_option" =~ ^[Yy]$ ]]; then
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" < "$temp_file"
        else
            # 只恢复数据，不删除现有数据库
            log_warn "注意：这可能会因重复数据而失败"
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" < "$temp_file"
        fi
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        docker cp "$temp_file" mysql57:/tmp/restore.sql
        if [[ "$drop_option" =~ ^[Yy]$ ]]; then
            docker exec mysql57 mysql -u root -p"$MYSQL_ROOT_PASSWORD" < /tmp/restore.sql
        else
            docker exec mysql57 mysql -u root -p"$MYSQL_ROOT_PASSWORD" < /tmp/restore.sql
        fi
        docker exec mysql57 rm -f /tmp/restore.sql
    fi
    
    rm -f "$temp_file"
    
    if [ $? -eq 0 ]; then
        log_info "数据库恢复成功"
    else
        log_error "数据库恢复失败"
    fi
}

# 显示连接信息
show_connection_info() {
    log_step "MySQL连接信息:"
    echo ""
    
    local ip_address=$(hostname -I | awk '{print $1}')
    
    log_info "服务器地址:"
    log_info "  - localhost"
    log_info "  - 127.0.0.1"
    [ -n "$ip_address" ] && log_info "  - $ip_address"
    echo ""
    
    log_info "端口: $MYSQL_PORT"
    log_info "用户名: root"
    [ -n "$MYSQL_ROOT_PASSWORD" ] && log_info "密码: (已保存)"
    echo ""
    
    log_info "连接字符串示例:"
    log_info "  mysql -h $ip_address -P $MYSQL_PORT -u root -p"
    log_info "  mysql://root:您的密码@$ip_address:$MYSQL_PORT/"
    echo ""
    
    log_info "当前连接数:"
    if [ "$INSTALL_TYPE" = "native" ]; then
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null || echo "无法获取"
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        docker exec mysql57 mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null || echo "无法获取"
    fi
}

# 优化配置
optimize_config() {
    log_step "优化MySQL配置..."
    
    echo ""
    log_menu "请选择优化选项:"
    log_info "1. 优化内存配置 (适合1H1G)"
    log_info "2. 优化性能配置"
    log_info "3. 优化安全配置"
    log_info "4. 查看当前配置"
    echo ""
    
    read -p "请输入选项 (1-4): " opt_choice
    
    case $opt_choice in
        1)
            log_step "优化内存配置..."
            if [ "$INSTALL_TYPE" = "native" ]; then
                cat > /etc/mysql/conf.d/optimize.cnf << EOF
[mysqld]
# 内存优化
key_buffer_size = 16M
innodb_buffer_pool_size = 128M
query_cache_size = 16M
tmp_table_size = 16M
max_heap_table_size = 16M
sort_buffer_size = 1M
read_buffer_size = 1M
read_rnd_buffer_size = 1M
join_buffer_size = 1M
thread_cache_size = 8
table_open_cache = 256
EOF
                systemctl restart mysql
                log_info "内存优化配置已应用"
            elif [ "$INSTALL_TYPE" = "docker" ]; then
                log_warn "Docker安装需要重新创建容器以应用配置"
                log_info "请使用卸载后重新安装来应用新配置"
            fi
            ;;
        2)
            log_step "优化性能配置..."
            # 类似的内存优化配置
            ;;
        3)
            log_step "优化安全配置..."
            if [ "$INSTALL_TYPE" = "native" ]; then
                mysql -u root -p"$MYSQL_ROOT_PASSWORD" << EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
                log_info "安全配置已优化"
            fi
            ;;
        4)
            log_step "当前配置:"
            if [ "$INSTALL_TYPE" = "native" ]; then
                mysqld --help --verbose | grep -A 1 "buffer\|cache\|size"
            elif [ "$INSTALL_TYPE" = "docker" ]; then
                docker exec mysql57 mysqld --help --verbose | grep -A 1 "buffer\|cache\|size"
            fi
            ;;
        *)
            log_error "无效选项"
            ;;
    esac
}

# 卸载MySQL
uninstall_mysql() {
    log_step "卸载MySQL..."
    
    echo -n -e "${RED}警告：这将卸载MySQL并删除所有数据！是否继续？ (y/N): ${NC}"
    read confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "取消卸载"
        return
    fi
    
    echo -n -e "${YELLOW}是否备份数据？ (Y/n): ${NC}"
    read backup_confirm
    
    if [[ ! "$backup_confirm" =~ ^[Nn]$ ]]; then
        backup_database
    fi
    
    if [ "$INSTALL_TYPE" = "native" ]; then
        log_step "卸载原生MySQL..."
        systemctl stop mysql
        apt-get remove --purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-*
        apt-get autoremove -y
        apt-get autoclean -y
        rm -rf /etc/mysql /var/lib/mysql /var/log/mysql*
        rm -f /etc/apt/sources.list.d/mysql*.list
    elif [ "$INSTALL_TYPE" = "docker" ]; then
        log_step "卸载Docker MySQL..."
        docker stop mysql57
        docker rm mysql57
        docker rmi mysql:5.7
        rm -rf /opt/mysql57
    fi
    
    rm -f "$CONFIG_FILE"
    log_info "MySQL卸载完成"
}

# 主安装函数
main_install() {
    clear
    log_step "开始安装 MySQL 5.7"
    log_step "===================="
    echo ""
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        log_info "请尝试: sudo bash $0"
        exit 1
    fi
    
    # 检测系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        log_info "检测到系统: $NAME $VERSION"
        if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
            log_error "此脚本仅支持Ubuntu和Debian系统"
            exit 1
        fi
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    
    # 检查是否已安装
    if check_installed; then
        log_info "MySQL已经安装"
        load_config || {
            log_warn "未找到保存的配置，可能需要重新设置密码"
        }
        show_management_menu
        exit 0
    fi
    
    # 获取MySQL root密码
    while true; do
        echo -n -e "${YELLOW}请输入MySQL root用户的密码 (至少8个字符): ${NC}"
        read -s password
        echo
        
        if [ ${#password} -lt 8 ]; then
            log_error "密码长度至少需要8个字符"
            continue
        fi
        
        echo -n -e "${YELLOW}请确认密码: ${NC}"
        read -s password_confirm
        echo
        
        if [ "$password" = "$password_confirm" ]; then
            MYSQL_ROOT_PASSWORD=$password
            log_info "密码设置成功"
            break
        else
            log_error "两次输入的密码不一致，请重新输入"
        fi
    done
    
    # 检查端口占用
    if ss -tlnp | grep -q ":$MYSQL_PORT "; then
        log_error "端口 $MYSQL_PORT 已被占用，无法安装"
        exit 1
    fi
    
    # 安装流程
    log_step "更新系统包列表..."
    apt-get update -y
    
    log_step "安装必要工具..."
    apt-get install -y curl wget gnupg lsb-release
    
    # 安装Docker
    install_docker() {
        log_step "安装Docker..."
        apt-get install -y apt-transport-https ca-certificates curl gnupg
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io
        
        # 配置镜像加速
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn", "https://hub-mirror.c.163.com"]
}
EOF
        systemctl restart docker
    }
    
    # 使用Docker安装MySQL 5.7
    log_step "使用Docker安装MySQL 5.7..."
    install_docker
    
    # 创建数据目录
    mkdir -p /opt/mysql57/data
    mkdir -p /opt/mysql57/conf
    
    # 创建配置文件
    cat > /opt/mysql57/conf/my.cnf << EOF
[mysqld]
user=mysql
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
default-storage-engine=INNODB
max_connections=100
key_buffer_size=16M
innodb_buffer_pool_size=128M
innodb_log_file_size=48M
bind-address=0.0.0.0
skip-name-resolve

[client]
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4
EOF
    
    # 拉取并运行容器
    docker pull mysql:5.7
    docker run -d \
        --name mysql57 \
        --restart unless-stopped \
        --memory="1g" \
        -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
        -p $MYSQL_PORT:3306 \
        -v /opt/mysql57/data:/var/lib/mysql \
        -v /opt/mysql57/conf/my.cnf:/etc/mysql/conf.d/my.cnf \
        mysql:5.7
    
    # 等待启动
    sleep 10
    
    # 检查安装结果
    if docker ps | grep -q mysql57; then
        INSTALL_TYPE="docker"
        save_config
        log_info "MySQL 5.7 安装成功！"
    else
        log_error "MySQL安装失败"
        exit 1
    fi
    
    # 显示安装信息
    show_connection_info
    
    # 进入管理菜单
    show_management_menu
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    main_install
fi