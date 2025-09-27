#!/bin/bash

# 防火墙管理脚本
# 需要root权限运行

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 此脚本需要root权限运行" 
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查系统防火墙类型
check_firewall_type() {
    echo "====================================="
    echo "       系统防火墙类型检测"
    echo "====================================="
    echo
    
    local installed_firewalls=()
    local active_firewall="无"
    
    # 检查UFW
    if command -v ufw &> /dev/null; then
        installed_firewalls+=("UFW")
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            active_firewall="UFW"
        fi
    fi
    
    # 检查firewalld
    if command -v firewall-cmd &> /dev/null; then
        installed_firewalls+=("Firewalld")
        if systemctl is-active firewalld &> /dev/null 2>&1; then
            active_firewall="Firewalld"
        fi
    fi
    
    # 检查iptables
    if command -v iptables &> /dev/null; then
        installed_firewalls+=("iptables")
        # 检查是否有规则
        if iptables -L -n 2>/dev/null | grep -q -v "Chain INPUT (policy ACCEPT)" || iptables -L -n 2>/dev/null | grep -q "REJECT\|DROP"; then
            if [[ $active_firewall == "无" ]]; then
                active_firewall="iptables"
            fi
        fi
    fi
    
    # 显示结果
    echo "已安装的防火墙类型:"
    if [[ ${#installed_firewalls[@]} -eq 0 ]]; then
        echo "  未检测到任何防火墙"
    else
        for firewall in "${installed_firewalls[@]}"; do
            echo "  - $firewall"
        done
    fi
    
    echo
    echo "当前活动的防火墙: $active_firewall"
    echo
}

# 安装依赖
install_dependency() {
    local dep=$1
    echo "检测到缺少依赖: $dep"
    read -p "是否安装此依赖? (y/n): " choice
    
    case $choice in
        y|Y)
            echo "正在安装 $dep ..."
            if command -v apt-get &> /dev/null; then
                apt-get update > /dev/null 2>&1
                apt-get install -y $dep > /dev/null 2>&1
            elif command -v yum &> /dev/null; then
                yum install -y $dep > /dev/null 2>&1
            elif command -v dnf &> /dev/null; then
                dnf install -y $dep > /dev/null 2>&1
            else
                echo "无法确定包管理器，请手动安装 $dep"
                return 1
            fi
            
            if [ $? -eq 0 ]; then
                echo "$dep 安装成功!"
                return 0
            else
                echo "$dep 安装失败!"
                return 1
            fi
            ;;
        *)
            echo "跳过依赖安装，某些功能可能无法使用"
            return 1
            ;;
    esac
}

# 检查netstat或ss命令
check_net_tools() {
    if ! command -v netstat &> /dev/null && ! command -v ss &> /dev/null; then
        install_dependency "net-tools"
    fi
}

# 获取端口监听信息
get_port_listening_info() {
    if command -v ss &> /dev/null; then
        ss -tuln
    elif command -v netstat &> /dev/null; then
        netstat -tuln
    else
        echo "错误: 无法获取端口信息"
        return 1
    fi
}

# 检查端口是否被占用
is_port_used() {
    local port=$1
    if get_port_listening_info 2>/dev/null | grep -q ":$port "; then
        return 0
    else
        return 1
    fi
}

# 获取占用端口的进程信息
get_port_process() {
    local port=$1
    if command -v lsof &> /dev/null; then
        lsof -i :$port 2>/dev/null | awk 'NR==2 {print $1}'
    elif command -v fuser &> /dev/null; then
        fuser $port/tcp 2>/dev/null | cut -d: -f2
    else
        echo "未知"
    fi
}

# 显示所有端口开放状态
show_all_ports_status() {
    echo "====================================="
    echo "       系统端口开放状态"
    echo "====================================="
    echo
    
    # 检查防火墙状态
    local firewall_active=false
    
    if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        firewall_active=true
        echo "防火墙状态: UFW 已启用"
        echo "正在获取端口信息..."
        ports_info=$(ufw status numbered 2>/dev/null | grep -E "ALLOW|DENY")
    elif command -v firewall-cmd &> /dev/null && systemctl is-active firewalld &> /dev/null 2>&1; then
        firewall_active=true
        echo "防火墙状态: Firewalld 已启用"
        echo "正在获取端口信息..."
        ports_info=$(firewall-cmd --list-all 2>/dev/null | grep "ports:")
    else
        echo "防火墙状态: 未开启防火墙，端口全开放"
        echo
        echo "当前监听端口:"
        echo
        
        # 表头
        printf "%-8s %-12s %-10s %-8s %-15s\n" "端口" "协议" "状态" "类型" "进程"
        printf "%-8s %-12s %-10s %-8s %-15s\n" "------" "------------" "----------" "------" "---------------"
        
        get_port_listening_info 2>/dev/null | awk '
        NR>2 {
            if ($1 == "tcp" || $1 == "tcp6") protocol="TCP";
            else if ($1 == "udp" || $1 == "udp6") protocol="UDP";
            else protocol=$1;
            
            split($4, addr, ":");
            port=addr[length(addr)];
            type=($1 ~ /6/) ? "IPV6" : "IPV4";
            ip=addr[1];
            if (ip == "::") ip="*";
            if (ip == "0.0.0.0") ip="*";
            
            printf "%-8s %-12s %-10s %-8s %-15s\n", port, protocol, "监听", type, ip;
        }' | sort -k4,4 -k1,1n
        return
    fi
    
    if [[ -z "$ports_info" ]] || [[ "$ports_info" == "" ]]; then
        echo "没有找到开放的端口规则"
        return
    fi
    
    # 表头
    printf "%-8s %-12s %-10s %-8s %-15s\n" "端口" "协议" "状态" "类型" "进程"
    printf "%-8s %-12s %-10s %-8s %-15s\n" "------" "------------" "----------" "------" "---------------"
    
    # 简化显示防火墙规则
    if $firewall_active; then
        if command -v ufw &> /dev/null; then
            ufw status verbose 2>/dev/null | grep -E "^[0-9]+" | while read line; do
                port=$(echo "$line" | awk '{print $1}' | cut -d'/' -f1)
                protocol=$(echo "$line" | awk '{print $1}' | cut -d'/' -f2)
                if [[ -z "$protocol" ]]; then
                    protocol="tcp/udp"
                fi
                
                if is_port_used "$port"; then
                    status="占用"
                    process=$(get_port_process "$port")
                else
                    status="未占用"
                    process="-"
                fi
                
                printf "%-8s %-12s %-10s %-8s %-15s\n" "$port" "$protocol" "$status" "IPV4" "$process"
            done
        elif command -v firewall-cmd &> /dev/null; then
            firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | while read port_protocol; do
                if [[ -n "$port_protocol" ]]; then
                    port=$(echo "$port_protocol" | cut -d'/' -f1)
                    protocol=$(echo "$port_protocol" | cut -d'/' -f2)
                    
                    if is_port_used "$port"; then
                        status="占用"
                        process=$(get_port_process "$port")
                    else
                        status="未占用"
                        process="-"
                    fi
                    
                    printf "%-8s %-12s %-10s %-8s %-15s\n" "$port" "$protocol" "$status" "IPV4" "$process"
                fi
            done
        fi
    fi
}

# 查看指定端口占用情况
check_specific_ports() {
    echo "====================================="
    echo "       指定端口占用情况检查"
    echo "====================================="
    echo "输入示例:"
    echo "  - 单个端口: 80"
    echo "  - 多个端口: 80,443,22"
    echo "  - 端口范围: 8000-8080"
    echo
    
    read -p "请输入端口(支持单个、多个或范围): " port_input
    
    if [[ -z "$port_input" ]]; then
        echo "输入不能为空"
        return
    fi
    
    # 表头
    echo
    printf "%-8s %-12s %-10s %-15s\n" "端口" "协议" "状态" "进程"
    printf "%-8s %-12s %-10s %-15s\n" "------" "------------" "----------" "---------------"
    
    # 处理不同类型的输入
    if [[ "$port_input" =~ ^[0-9]+$ ]]; then
        # 单个端口
        check_single_port "$port_input"
    elif [[ "$port_input" =~ ^[0-9]+-[0-9]+$ ]]; then
        # 端口范围
        start_port=$(echo "$port_input" | cut -d'-' -f1)
        end_port=$(echo "$port_input" | cut -d'-' -f2)
        
        if [[ $start_port -gt $end_port ]]; then
            echo "错误: 起始端口不能大于结束端口"
            return
        fi
        
        for port in $(seq $start_port $end_port); do
            check_single_port "$port"
        done
    elif [[ "$port_input" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        # 多个端口
        IFS=',' read -ra ports <<< "$port_input"
        for port in "${ports[@]}"; do
            check_single_port "$port"
        done
    else
        echo "输入格式错误"
        return
    fi
}

# 检查单个端口
check_single_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        printf "%-8s %-12s %-10s %-15s\n" "$port" "-" "无效" "-"
        return
    fi
    
    if is_port_used "$port"; then
        local process=$(get_port_process "$port")
        local protocol="TCP/UDP"
        printf "%-8s %-12s %-10s %-15s\n" "$port" "$protocol" "占用" "$process"
    else
        printf "%-8s %-12s %-10s %-15s\n" "$port" "TCP/UDP" "未占用" "-"
    fi
}

# 开放指定端口
open_ports() {
    echo "====================================="
    echo "           开放指定端口"
    echo "====================================="
    echo "输入示例:"
    echo "  - 单个端口: 80"
    echo "  - 带协议端口: 80/tcp"
    echo "  - 多个端口: 80,443,22"
    echo "  - 端口范围: 8000-8080"
    echo
    
    read -p "请输入要开放的端口: " port_input
    
    if [[ -z "$port_input" ]]; then
        echo "输入不能为空"
        return
    fi
    
    # 确定防火墙类型并执行相应命令
    if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        # UFW
        echo "使用 UFW 开放端口..."
        if ufw allow "$port_input" 2>/dev/null; then
            ufw reload > /dev/null 2>&1
            echo "✓ 端口 $port_input 开放成功"
        else
            echo "✗ 端口开放失败"
        fi
    elif command -v firewall-cmd &> /dev/null && systemctl is-active firewalld &> /dev/null 2>&1; then
        # Firewalld
        echo "使用 Firewalld 开放端口..."
        if [[ "$port_input" =~ ^[0-9]+$ ]]; then
            # 单个端口，默认TCP
            if firewall-cmd --permanent --add-port="$port_input/tcp" 2>/dev/null; then
                firewall-cmd --reload > /dev/null 2>&1
                echo "✓ 端口 $port_input/tcp 开放成功"
            else
                echo "✗ 端口开放失败"
            fi
        else
            # 其他格式
            if firewall-cmd --permanent --add-port="$port_input" 2>/dev/null; then
                firewall-cmd --reload > /dev/null 2>&1
                echo "✓ 端口 $port_input 开放成功"
            else
                echo "✗ 端口开放失败"
            fi
        fi
    else
        echo "未检测到活动的防火墙"
        echo "请先启用UFW或Firewalld防火墙"
    fi
}

# 关闭指定端口
close_ports() {
    echo "====================================="
    echo "           关闭指定端口"
    echo "====================================="
    echo "输入示例:"
    echo "  - 单个端口: 80"
    echo "  - 带协议端口: 80/tcp"
    echo "  - 多个端口: 80,443,22"
    echo "  - 端口范围: 8000-8080"
    echo
    
    read -p "请输入要关闭的端口: " port_input
    
    if [[ -z "$port_input" ]]; then
        echo "输入不能为空"
        return
    fi
    
    # 确定防火墙类型并执行相应命令
    if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        # UFW
        echo "使用 UFW 关闭端口..."
        if ufw delete allow "$port_input" 2>/dev/null; then
            ufw reload > /dev/null 2>&1
            echo "✓ 端口 $port_input 关闭成功"
        else
            echo "✗ 端口关闭失败"
        fi
    elif command -v firewall-cmd &> /dev/null && systemctl is-active firewalld &> /dev/null 2>&1; then
        # Firewalld
        echo "使用 Firewalld 关闭端口..."
        if [[ "$port_input" =~ ^[0-9]+$ ]]; then
            # 单个端口，默认TCP
            if firewall-cmd --permanent --remove-port="$port_input/tcp" 2>/dev/null; then
                firewall-cmd --reload > /dev/null 2>&1
                echo "✓ 端口 $port_input/tcp 关闭成功"
            else
                echo "✗ 端口关闭失败"
            fi
        else
            # 其他格式
            if firewall-cmd --permanent --remove-port="$port_input" 2>/dev/null; then
                firewall-cmd --reload > /dev/null 2>&1
                echo "✓ 端口 $port_input 关闭成功"
            else
                echo "✗ 端口关闭失败"
            fi
        fi
    else
        echo "未检测到活动的防火墙"
    fi
}

# 显示菜单
show_menu() {
    echo "====================================="
    echo "        Linux防火墙管理脚本"
    echo "====================================="
    echo "1. 系统防火墙的类型"
    echo "2. 开放端口占用情况"
    echo "3. 指定端口占用情况"
    echo "4. 开放指定端口"
    echo "5. 关闭指定端口"
    echo "6. 退出"
    echo "====================================="
}

# 清理屏幕
clear_screen() {
    clear
}

# 主程序
main() {
    check_root
    check_net_tools
    
    # 初始清屏
    clear_screen
    
    while true; do
        show_menu
        echo
        read -p "请选择操作 [1-6]: " choice
        
        # 清空输入缓冲区，避免多输入问题
        while read -t 0.1 -n 1000 discard; do
            true
        done
        
        case $choice in
            1)
                clear_screen
                check_firewall_type
                ;;
            2)
                clear_screen
                show_all_ports_status
                ;;
            3)
                clear_screen
                check_specific_ports
                ;;
            4)
                clear_screen
                open_ports
                ;;
            5)
                clear_screen
                close_ports
                ;;
            6)
                echo "退出脚本"
                exit 0
                ;;
            *)
                echo "无效选择，请重新输入"
                # 不清屏，直接继续循环
                sleep 1
                # 只清除菜单部分，不清除错误信息
                clear_screen
                continue
                ;;
        esac
        
        echo
        read -p "按回车键返回主菜单..." -r
        clear_screen
    done
}

# 捕获Ctrl+C退出信号
trap 'echo -e "\n\n用户中断操作，退出脚本"; exit 1' INT

# 运行主程序
main
