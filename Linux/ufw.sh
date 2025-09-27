#!/bin/bash

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    echo "请以root权限运行此脚本: sudo $0"
    exit 1
fi

# 禁用所有颜色和特殊字符，只使用纯文本
# 创建简单的菜单函数
show_menu() {
    clear
    echo "========================================"
    echo "         防火墙管理脚本 - 简化版"
    echo "========================================"
    echo "1. 系统防火墙类型检查"
    echo "2. 开放端口占用情况" 
    echo "3. 指定端口占用情况"
    echo "4. 开放指定端口"
    echo "5. 关闭指定端口"
    echo "6. 退出脚本"
    echo "========================================"
}

# 等待用户输入函数
wait_for_input() {
    echo ""
    echo "按回车键返回主菜单..."
    read -r
}

# 防火墙类型检查
check_firewall() {
    echo "正在检查系统防火墙类型..."
    echo ""
    
    # 检查UFW
    if command -v ufw >/dev/null 2>&1; then
        echo "发现UFW防火墙"
        ufw status | head -n 5
    else
        echo "未安装UFW"
    fi
    
    echo ""
    
    # 检查firewalld
    if command -v firewall-cmd >/dev/null 2>&1; then
        echo "发现Firewalld防火墙"
        firewall-cmd --state 2>/dev/null || echo "Firewalld未运行"
    else
        echo "未安装Firewalld"
    fi
    
    echo ""
    
    # 检查iptables
    if command -v iptables >/dev/null 2>&1; then
        echo "发现iptables"
        iptables -L -n | head -n 10
    else
        echo "未安装iptables"
    fi
    
    wait_for_input
}

# 检查开放端口
check_open_ports() {
    echo "正在检查开放端口..."
    echo ""
    
    # 使用最简单的命令检查
    if command -v netstat >/dev/null 2>&1; then
        echo "使用netstat检查:"
        netstat -tuln | grep LISTEN | head -20
    elif command -v ss >/dev/null 2>&1; then
        echo "使用ss检查:"
        ss -tuln | grep LISTEN | head -20
    else
        echo "无法检查端口，请安装net-tools或iproute2"
    fi
    
    wait_for_input
}

# 检查指定端口
check_specific_port() {
    echo "检查指定端口占用情况"
    echo "请输入端口号(例如: 80 或 80,443 或 8000-8080):"
    read -r port_input
    
    if [ -z "$port_input" ]; then
        echo "输入为空"
        wait_for_input
        return
    fi
    
    echo "检查端口: $port_input"
    
    # 处理单个端口
    if [[ $port_input =~ ^[0-9]+$ ]]; then
        if command -v netstat >/dev/null 2>&1; then
            netstat -tuln | grep ":$port_input "
        elif command -v ss >/dev/null 2>&1; then
            ss -tuln | grep ":$port_input "
        fi
    # 处理多个端口
    elif [[ $port_input =~ ^[0-9]+(,[0-9]+)+$ ]]; then
        IFS=',' read -ra ports <<< "$port_input"
        for port in "${ports[@]}"; do
            echo "端口 $port:"
            if command -v netstat >/dev/null 2>&1; then
                netstat -tuln | grep ":$port " || echo "  未找到"
            elif command -v ss >/dev/null 2>&1; then
                ss -tuln | grep ":$port " || echo "  未找到"
            fi
        done
    # 处理端口范围
    elif [[ $port_input =~ ^[0-9]+-[0-9]+$ ]]; then
        IFS='-' read -r start end <<< "$port_input"
        for ((port=start; port<=end; port++)); do
            echo "端口 $port:"
            if command -v netstat >/dev/null 2>&1; then
                netstat -tuln | grep ":$port " || echo "  未找到"
            elif command -v ss >/dev/null 2>&1; then
                ss -tuln | grep ":$port " || echo "  未找到"
            fi
        done
    else
        echo "输入格式错误"
    fi
    
    wait_for_input
}

# 开放端口
open_port() {
    echo "开放指定端口"
    echo "请输入端口号(例如: 80 或 80/tcp):"
    read -r port_input
    
    if [ -z "$port_input" ]; then
        echo "输入为空"
        wait_for_input
        return
    fi
    
    # 尝试使用UFW
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        echo "使用UFW开放端口: $port_input"
        ufw allow "$port_input"
    # 尝试使用firewalld
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        echo "使用Firewalld开放端口: $port_input"
        firewall-cmd --permanent --add-port="$port_input"
        firewall-cmd --reload
    # 尝试使用iptables
    elif command -v iptables >/dev/null 2>&1; then
        echo "使用iptables开放端口: $port_input"
        if [[ $port_input =~ /tcp$ ]]; then
            iptables -A INPUT -p tcp --dport "${port_input%/*}" -j ACCEPT
        elif [[ $port_input =~ /udp$ ]]; then
            iptables -A INPUT -p udp --dport "${port_input%/*}" -j ACCEPT
        else
            iptables -A INPUT -p tcp --dport "$port_input" -j ACCEPT
            iptables -A INPUT -p udp --dport "$port_input" -j ACCEPT
        fi
    else
        echo "未找到可用的防火墙工具"
    fi
    
    wait_for_input
}

# 关闭端口
close_port() {
    echo "关闭指定端口"
    echo "请输入端口号(例如: 80 或 80/tcp):"
    read -r port_input
    
    if [ -z "$port_input" ]; then
        echo "输入为空"
        wait_for_input
        return
    fi
    
    # 尝试使用UFW
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        echo "使用UFW关闭端口: $port_input"
        ufw delete allow "$port_input"
    # 尝试使用firewalld
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        echo "使用Firewalld关闭端口: $port_input"
        firewall-cmd --permanent --remove-port="$port_input"
        firewall-cmd --reload
    # 尝试使用iptables
    elif command -v iptables >/dev/null 2>&1; then
        echo "使用iptables关闭端口: $port_input"
        if [[ $port_input =~ /tcp$ ]]; then
            iptables -D INPUT -p tcp --dport "${port_input%/*}" -j ACCEPT 2>/dev/null || echo "规则不存在"
        elif [[ $port_input =~ /udp$ ]]; then
            iptables -D INPUT -p udp --dport "${port_input%/*}" -j ACCEPT 2>/dev/null || echo "规则不存在"
        else
            iptables -D INPUT -p tcp --dport "$port_input" -j ACCEPT 2>/dev/null || echo "TCP规则不存在"
            iptables -D INPUT -p udp --dport "$port_input" -j ACCEPT 2>/dev/null || echo "UDP规则不存在"
        fi
    else
        echo "未找到可用的防火墙工具"
    fi
    
    wait_for_input
}

# 主循环
while true; do
    show_menu
    echo -n "请选择操作 [1-6]: "
    
    # 使用最简化的读取方式
    read -r choice
    
    case $choice in
        1)
            check_firewall
            ;;
        2)
            check_open_ports
            ;;
        3)
            check_specific_port
            ;;
        4)
            open_port
            ;;
        5)
            close_port
            ;;
        6)
            echo "再见!"
            exit 0
            ;;
        *)
            echo "无效选择: $choice"
            echo "请重新输入"
            sleep 2
            ;;
    esac
done
