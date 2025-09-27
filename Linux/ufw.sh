#!/bin/bash

# 检查是否有管理员权限
if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 检查是否安装了必要的工具
function check_dependencies() {
    required_tools=("ufw" "iptables" "ss" "netstat" "awk" "column")
    for tool in "${required_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            echo "$tool 未安装，是否安装？(y/n)"
            read install_choice
            if [[ $install_choice == "y" ]]; then
                apt-get install $tool -y
            else
                echo "缺少依赖项，退出脚本"
                exit 1
            fi
        fi
    done
}

# 获取当前防火墙类型
function get_firewall_type() {
    if command -v ufw &> /dev/null; then
        echo "UFW"
    elif command -v iptables &> /dev/null; then
        echo "iptables"
    else
        echo "未安装常见防火墙工具"
    fi
}

# 显示当前端口开放情况
function show_port_status() {
    firewall_type=$(get_firewall_type)

    if [[ "$firewall_type" == "未安装常见防火墙工具" ]]; then
        echo "当前系统未开启防火墙，端口全开放"
        return
    fi

    if [[ "$firewall_type" == "UFW" ]]; then
        sudo ufw status verbose | column -t
    elif [[ "$firewall_type" == "iptables" ]]; then
        sudo iptables -L -v -n --line-numbers | grep "ACCEPT" | column -t
    fi
}

# 查看指定端口占用情况
function show_specific_port_usage() {
    echo "请输入端口或端口范围（例如: 80 或 1000-2000）："
    read port_range
    ss -tuln | grep -E "$port_range" | column -t
}

# 开放指定端口
function open_port() {
    echo "请输入要开放的端口或端口范围（例如: 80 或 1000-2000）："
    read port_range
    firewall_type=$(get_firewall_type)
    
    if [[ "$firewall_type" == "UFW" ]]; then
        sudo ufw allow $port_range
    elif [[ "$firewall_type" == "iptables" ]]; then
        sudo iptables -A INPUT -p tcp --dport $port_range -j ACCEPT
    fi
}

# 关闭指定端口
function close_port() {
    echo "请输入要关闭的端口或端口范围（例如: 80 或 1000-2000）："
    read port_range
    firewall_type=$(get_firewall_type)
    
    if [[ "$firewall_type" == "UFW" ]]; then
        sudo ufw deny $port_range
    elif [[ "$firewall_type" == "iptables" ]]; then
        sudo iptables -D INPUT -p tcp --dport $port_range -j ACCEPT
    fi
}

# 菜单显示
function show_menu() {
    clear
    echo "----------------------------"
    echo " 防火墙管理脚本"
    echo "----------------------------"
    echo "1. 查看当前防火墙类型"
    echo "2. 查看开放端口占用情况"
    echo "3. 查看指定端口占用情况"
    echo "4. 开放指定端口"
    echo "5. 关闭指定端口"
    echo "6. 退出"
    echo "----------------------------"
    echo -n "请输入选择 [1-6]: "
    read choice

    case $choice in
        1)
            firewall_type=$(get_firewall_type)
            echo "当前防火墙类型是: $firewall_type"
            read -p "按任意键返回菜单..."
            ;;
        2)
            show_port_status
            read -p "按任意键返回菜单..."
            ;;
        3)
            show_specific_port_usage
            read -p "按任意键返回菜单..."
            ;;
        4)
            open_port
            read -p "按任意键返回菜单..."
            ;;
        5)
            close_port
            read -p "按任意键返回菜单..."
            ;;
        6)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效选项，请重新选择"
            read -p "按任意键返回菜单..."
            ;;
    esac
}

# 主程序
check_dependencies

while true; do
    show_menu
done
