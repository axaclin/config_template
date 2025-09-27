#!/bin/bash

# 安装依赖函数，自动检测并安装缺少的依赖
install_dependencies() {
    required_packages=()
    if ! command -v ufw &> /dev/null; then
        required_packages+=("ufw")
    fi
    if ! command -v firewall-cmd &> /dev/null; then
        required_packages+=("firewalld")
    fi
    if ! command -v netstat &> /dev/null; then
        required_packages+=("net-tools")
    fi
    if ! command -v ss &> /dev/null; then
        required_packages+=("iproute2")
    fi

    if [ ${#required_packages[@]} -gt 0 ]; then
        echo "缺少以下依赖: ${required_packages[@]}"
        read -p "是否要安装它们？(y/n): " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            sudo apt-get update
            sudo apt-get install -y "${required_packages[@]}"
        else
            echo "无法继续执行脚本，依赖项未安装。"
            exit 1
        fi
    fi
}

# 检测防火墙类型
check_firewall_type() {
    if command -v ufw &> /dev/null; then
        firewall_type="UFW"
    elif command -v firewall-cmd &> /dev/null; then
        firewall_type="Firewalld"
    else
        firewall_type="没有安装防火墙"
    fi
    echo "当前防火墙类型: $firewall_type"
}

# 查看端口开放占用情况
check_port_status() {
    if [ "$firewall_type" == "没有安装防火墙" ]; then
        echo "当前系统未开启防火墙，端口全开放。"
        ss -tuln
    else
        if [ "$firewall_type" == "UFW" ]; then
            ufw status verbose
        elif [ "$firewall_type" == "Firewalld" ]; then
            firewall-cmd --list-all
        fi
    fi
}

# 查询指定端口占用情况
check_specific_port() {
    read -p "请输入一个或多个端口（例如：80 443 或 80-100）： " ports
    echo "检查端口占用情况："
    for port in $ports; do
        if [[ "$port" == *"-"* ]]; then
            range_start=$(echo $port | cut -d'-' -f1)
            range_end=$(echo $port | cut -d'-' -f2)
            for p in $(seq $range_start $range_end); do
                ss -tuln | grep ":$p" || echo "端口 $p 未占用"
            done
        else
            ss -tuln | grep ":$port" || echo "端口 $port 未占用"
        fi
    done
}

# 开放指定端口
open_port() {
    read -p "请输入要开放的端口（例如：80 443 或 80-100）： " ports
    echo "正在开放端口：$ports"
    for port in $ports; do
        if [[ "$port" == *"-"* ]]; then
            range_start=$(echo $port | cut -d'-' -f1)
            range_end=$(echo $port | cut -d'-' -f2)
            for p in $(seq $range_start $range_end); do
                if [ "$firewall_type" == "UFW" ]; then
                    sudo ufw allow $p
                elif [ "$firewall_type" == "Firewalld" ]; then
                    sudo firewall-cmd --zone=public --add-port=$p/tcp --permanent
                    sudo firewall-cmd --reload
                fi
            done
        else
            if [ "$firewall_type" == "UFW" ]; then
                sudo ufw allow $port
            elif [ "$firewall_type" == "Firewalld" ]; then
                sudo firewall-cmd --zone=public --add-port=$port/tcp --permanent
                sudo firewall-cmd --reload
            fi
        fi
    done
}

# 关闭指定端口
close_port() {
    read -p "请输入要关闭的端口（例如：80 443 或 80-100）： " ports
    echo "正在关闭端口：$ports"
    for port in $ports; do
        if [[ "$port" == *"-"* ]]; then
            range_start=$(echo $port | cut -d'-' -f1)
            range_end=$(echo $port | cut -d'-' -f2)
            for p in $(seq $range_start $range_end); do
                if [ "$firewall_type" == "UFW" ]; then
                    sudo ufw deny $p
                elif [ "$firewall_type" == "Firewalld" ]; then
                    sudo firewall-cmd --zone=public --remove-port=$p/tcp --permanent
                    sudo firewall-cmd --reload
                fi
            done
        else
            if [ "$firewall_type" == "UFW" ]; then
                sudo ufw deny $port
            elif [ "$firewall_type" == "Firewalld" ]; then
                sudo firewall-cmd --zone=public --remove-port=$port/tcp --permanent
                sudo firewall-cmd --reload
            fi
        fi
    done
}

# 显示菜单
menu() {
    clear
    echo "=== 防火墙管理脚本 ==="
    echo "1. 查询系统防火墙类型"
    echo "2. 查看开放端口占用情况"
    echo "3. 查询指定端口占用情况"
    echo "4. 开放指定端口"
    echo "5. 关闭指定端口"
    echo "6. 退出"
    read -p "请选择操作 (1-6): " choice
    case $choice in
        1) 
            check_firewall_type
            ;;
        2)
            check_port_status
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
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效的选择，请重新选择。"
            ;;
    esac
    read -p "按 Enter 键返回菜单..."
}

# 安装依赖并开始执行
install_dependencies
while true; do
    menu
done
