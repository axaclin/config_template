#!/bin/bash

# 显示菜单
menu() {
    clear
    echo "==================== 防火墙端口检查菜单 ===================="
    echo "1. 获取当前系统使用的防火墙类型"
    echo "2. 查询所有开放端口及占用情况"
    echo "3. 查询指定端口占用情况"
    echo "4. 开放指定端口"
    echo "5. 关闭指定端口"
    echo "6. 退出"
    echo "=============================================================="
    read -p "请选择操作 (1-6): " choice
}

# 获取当前系统使用的防火墙类型
check_firewall_type() {
    echo "==================== 获取当前系统使用的防火墙类型 ===================="
    
    # 检查是否启用 ufw
    if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
        echo "当前系统使用的防火墙类型：UFW"
        read -p "按任意键返回菜单..." -n 1 -s
        return
    fi

    # 检查是否启用 firewalld
    if systemctl is-active --quiet firewalld; then
        echo "当前系统使用的防火墙类型：firewalld"
        read -p "按任意键返回菜单..." -n 1 -s
        return
    fi

    # 检查是否启用 iptables
    if systemctl is-active --quiet iptables; then
        echo "当前系统使用的防火墙类型：iptables"
        read -p "按任意键返回菜单..." -n 1 -s
        return
    fi

    # 检查是否启用 nftables
    if systemctl is-active --quiet nftables; then
        echo "当前系统使用的防火墙类型：nftables"
        read -p "按任意键返回菜单..." -n 1 -s
        return
    fi
    
    # 如果都未启用
    echo "未检测到活动的防火墙类型"
    read -p "按任意键返回菜单..." -n 1 -s
}

# 查询所有开放端口及占用情况
check_open_ports() {
    echo "==================== 查询所有开放端口及占用情况 ===================="

    # 获取已开放的端口
    open_ports=$(sudo ufw status | grep ALLOW | awk '{print $1}')

    if [ -z "$open_ports" ]; then
        echo "没有发现开放的端口。"
        read -p "按任意键返回菜单..." -n 1 -s
        return
    fi

    # 获取监听的端口，并按端口排序
    listening_ports=$(ss -tuln | awk '{print $5}' | cut -d: -f2 | sort -n | uniq)
    ipv4_ports=$(echo "$listening_ports" | grep -v ':.*:' | sort -n)
    ipv6_ports=$(echo "$listening_ports" | grep ':.*:' | sort -n)

    # 打印标题，居中对齐
    printf "%-15s %-10s %-10s %-30s\n" "端口" "协议" "状态" "来源"
    echo "-------------------------------------------------------------"

    # 检查 IPv4 端口
    echo "==> IPv4 端口："
    for port in $ipv4_ports; do
        # 获取占用端口的 IP 地址
        ip_address=$(ss -tulnp | grep ":$port" | awk '{print $6}' | cut -d':' -f1 | sort -u | grep -v '^\[' | grep -v '^\*')
        protocol=$(ss -tulnp | grep ":$port" | awk '{print $1}' | head -n 1)
        if [ -n "$ip_address" ]; then
            printf "%-15s %-10s %-10s %-30s\n" "$port/$protocol" "IPv4" "占用" "$ip_address"
        else
            printf "%-15s %-10s %-10s %-30s\n" "$port/$protocol" "IPv4" "未占用" "-"
        fi
    done

    # 检查 IPv6 端口
    echo "==> IPv6 端口："
    for port in $ipv6_ports; do
        # 获取占用端口的 IP 地址
        ip_address=$(ss -tulnp | grep ":$port" | awk '{print $6}' | cut -d':' -f1 | sort -u | grep -v '^\[' | grep -v '^\*')
        protocol=$(ss -tulnp | grep ":$port" | awk '{print $1}' | head -n 1)
        if [ -n "$ip_address" ]; then
            printf "%-15s %-10s %-10s %-30s\n" "$port/$protocol" "IPv6" "占用" "$ip_address"
        else
            printf "%-15s %-10s %-10s %-30s\n" "$port/$protocol" "IPv6" "未占用" "-"
        fi
    done

    read -p "按任意键返回菜单..." -n 1 -s
}

# 查询指定端口的占用情况
check_specific_ports() {
    echo "==================== 查询指定端口占用情况 ===================="
    echo "请输入一个或多个端口，端口之间用空格隔开，或者输入端口范围（例如：1000-2000）"
    echo "例如：22 80 443 或 1000-2000"
    read -p "请输入端口： " ports_input

    # 判断输入是否为端口范围
    if [[ "$ports_input" =~ ^[0-9]+-[0-9]+$ ]]; then
        # 处理端口范围
        start_port=$(echo $ports_input | cut -d- -f1)
        end_port=$(echo $ports_input | cut -d- -f2)

        echo "查询端口范围 $start_port 到 $end_port 的占用情况："
        for port in $(seq $start_port $end_port); do
            ip_address=$(ss -tulnp | grep ":$port" | awk '{print $6}' | cut -d':' -f1 | sort -u | grep -v '^\[' | grep -v '^\*')
            protocol=$(ss -tulnp | grep ":$port" | awk '{print $1}' | head -n 1)
            if [ -n "$ip_address" ]; then
                printf "%-15s %-10s %-10s %-30s\n" "$port/$protocol" "占用" "$ip_address"
            else
                printf "%-15s %-10s %-10s %-30s\n" "$port/$protocol" "未占用" "-"
            fi
        done
    else
        # 处理单个或多个端口
        for port in $ports_input; do
            ip_address=$(ss -tulnp | grep ":$port" | awk '{print $6}' | cut -d':' -f1 | sort -u | grep -v '^\[' | grep -v '^\*')
            protocol=$(ss -tulnp | grep ":$port" | awk '{print $1}' | head -n 1)
            if [ -n "$ip_address" ]; then
                printf "%-15s %-10s %-10s %-30s\n" "$port/$protocol" "占用" "$ip_address"
            else
                printf "%-15s %-10s %-10s %-30s\n" "$port/$protocol" "未占用" "-"
            fi
        done
    fi

    read -p "按任意键返回菜单..." -n 1 -s
}

# 开放指定端口
open_ports_function() {
    echo "==================== 开放指定端口 ===================="
    echo "请输入一个或多个端口，端口之间用空格隔开，或者输入端口范围（例如：1000-2000）"
    echo "例如：22 80 443 或 1000-2000"
    read -p "请输入端口： " ports_input

    # 获取当前使用的防火墙类型
    if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
        # 使用 UFW 开放端口
        echo "当前使用的防火墙是 UFW，正在开放端口..."
        sudo ufw allow $ports_input
    elif systemctl is-active --quiet firewalld; then
        # 使用 firewalld 开放端口
        echo "当前使用的防火墙是 firewalld，正在开放端口..."
        sudo firewall-cmd --permanent --add-port=$ports_input
        sudo firewall-cmd --reload
    elif systemctl is-active --quiet iptables; then
        # 使用 iptables 开放端口
        echo "当前使用的防火墙是 iptables，正在开放端口..."
        sudo iptables -A INPUT -p tcp --dport $ports_input -j ACCEPT
    elif systemctl is-active --quiet nftables; then
        # 使用 nftables 开放端口
        echo "当前使用的防火墙是 nftables，正在开放端口..."
        sudo nft add rule inet filter input tcp dport $ports_input accept
    else
        echo "未检测到活动的防火墙类型，无法开放端口"
    fi

    read -p "按任意键返回菜单..." -n 1 -s
}

# 关闭指定端口
close_ports_function() {
    echo "==================== 关闭指定端口 ===================="
    echo "请输入一个或多个端口，端口之间用空格隔开，或者输入端口范围（例如：1000-2000）"
    echo "例如：22 80 443 或 1000-2000"
    read -p "请输入端口： " ports_input

    # 获取当前使用的防火墙类型
    if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
        # 使用 UFW 关闭端口
        echo "当前使用的防火墙是 UFW，正在关闭端口..."
        sudo ufw deny $ports_input
    elif systemctl is-active --quiet firewalld; then
        # 使用 firewalld 关闭端口
        echo "当前使用的防火墙是 firewalld，正在关闭端口..."
        sudo firewall-cmd --permanent --remove-port=$ports_input
        sudo firewall-cmd --reload
    elif systemctl is-active --quiet iptables; then
        # 使用 iptables 关闭端口
        echo "当前使用的防火墙是 iptables，正在关闭端口..."
        sudo iptables -D INPUT -p tcp --dport $ports_input -j ACCEPT
    elif systemctl is-active --quiet nftables; then
        # 使用 nftables 关闭端口
        echo "当前使用的防火墙是 nftables，正在关闭端口..."
        sudo nft delete rule inet filter input tcp dport $ports_input accept
    else
        echo "未检测到活动的防火墙类型，无法关闭端口"
    fi

    read -p "按任意键返回菜单..." -n 1 -s
}

# 主程序循环
while true; do
    menu
    case $choice in
        1)
            check_firewall_type
            ;;
        2)
            check_open_ports
            ;;
        3)
            check_specific_ports
            ;;
        4)
            open_ports_function
            ;;
        5)
            close_ports_function
            ;;
        6)
            echo "退出程序。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新选择。"
            read -p "按任意键返回菜单..." -n 1 -s
            ;;
    esac
done
