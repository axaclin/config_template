#!/bin/bash

# 检查是否具有 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本。"
    exit 1
fi

# 检查防火墙是否已安装
check_firewall() {
    if command -v ufw &>/dev/null; then
        echo "当前系统使用的是 UFW 防火墙"
    elif command -v firewall-cmd &>/dev/null; then
        echo "当前系统使用的是 firewalld 防火墙"
    elif command -v iptables &>/dev/null; then
        echo "当前系统使用的是 iptables 防火墙"
    else
        echo "当前系统未安装已知防火墙程序。"
        exit 1
    fi
}

# 显示当前防火墙类型
firewall_type() {
    check_firewall
    echo "已安装的防火墙类型："
    if command -v ufw &>/dev/null; then
        echo "UFW"
    fi
    if command -v firewall-cmd &>/dev/null; then
        echo "firewalld"
    fi
    if command -v iptables &>/dev/null; then
        echo "iptables"
    fi
}

# 查看端口占用情况
port_status() {
    check_firewall
    echo -e "端口\t协议\t状态\t类型\t占用IP"
    
    # 使用 `ss` 命令来检查端口占用情况
    ss -tuln | grep -E '^tcp|^udp' | awk '{print $5 "\t" $1 "\t" $2 "\t" $3}' | sort
}

# 查看指定端口占用情况
check_specific_ports() {
    echo "请输入要查询的端口 (单个端口，多个端口用空格分开，或使用范围如 80-90):"
    read -r input_ports
    ports=($input_ports)
    
    for port in "${ports[@]}"; do
        ss -tuln | grep ":$port" | awk '{print $5 "\t" $1 "\t" $2 "\t" $3}'
    done
}

# 开放指定端口
open_ports() {
    check_firewall
    echo "请输入要开放的端口 (单个端口，多个端口用空格分开，或使用范围如 80-90):"
    read -r input_ports
    ports=($input_ports)
    
    for port in "${ports[@]}"; do
        if command -v ufw &>/dev/null; then
            ufw allow $port
        elif command -v firewall-cmd &>/dev/null; then
            firewall-cmd --zone=public --add-port=$port/tcp --permanent
            firewall-cmd --reload
        elif command -v iptables &>/dev/null; then
            iptables -A INPUT -p tcp --dport $port -j ACCEPT
            iptables-save > /etc/iptables/rules.v4
        fi
        echo "端口 $port 已开放"
    done
}

# 关闭指定端口
close_ports() {
    check_firewall
    echo "请输入要关闭的端口 (单个端口，多个端口用空格分开，或使用范围如 80-90):"
    read -r input_ports
    ports=($input_ports)
    
    for port in "${ports[@]}"; do
        if command -v ufw &>/dev/null; then
            ufw deny $port
        elif command -v firewall-cmd &>/dev/null; then
            firewall-cmd --zone=public --remove-port=$port/tcp --permanent
            firewall-cmd --reload
        elif command -v iptables &>/dev/null; then
            iptables -D INPUT -p tcp --dport $port -j ACCEPT
            iptables-save > /etc/iptables/rules.v4
        fi
        echo "端口 $port 已关闭"
    done
}

# 菜单
while true; do
    echo "请选择操作:"
    echo "1. 查看系统防火墙类型"
    echo "2. 查看端口开放状态"
    echo "3. 查看指定端口占用情况"
    echo "4. 开放指定端口"
    echo "5. 关闭指定端口"
    echo "6. 退出"

    read -p "请输入选项 [1-6]: " choice

    case $choice in
        1)
            firewall_type
            ;;
        2)
            port_status
            ;;
        3)
            check_specific_ports
            ;;
        4)
            open_ports
            ;;
        5)
            close_ports
            ;;
        6)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效选项，请输入 1 到 6 的选项."
            ;;
    esac
done
