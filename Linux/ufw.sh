#!/bin/bash

# 设置颜色
RESET="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
WHITE="\033[37m"
BOLD="\033[1m"

# 检查是否具有 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行此脚本。${RESET}"
    exit 1
fi

# 检查防火墙是否已安装
check_firewall() {
    if command -v ufw &>/dev/null; then
        echo -e "${GREEN}当前系统使用的是 UFW 防火墙${RESET}"
    elif command -v firewall-cmd &>/dev/null; then
        echo -e "${GREEN}当前系统使用的是 firewalld 防火墙${RESET}"
    elif command -v iptables &>/dev/null; then
        echo -e "${GREEN}当前系统使用的是 iptables 防火墙${RESET}"
    else
        echo -e "${RED}当前系统未安装已知防火墙程序。${RESET}"
        exit 1
    fi
}

# 显示当前防火墙类型
firewall_type() {
    check_firewall
    echo -e "${CYAN}已安装的防火墙类型：${RESET}"
    if command -v ufw &>/dev/null; then
        echo -e "${BLUE}UFW${RESET}"
    fi
    if command -v firewall-cmd &>/dev/null; then
        echo -e "${BLUE}firewalld${RESET}"
    fi
    if command -v iptables &>/dev/null; then
        echo -e "${BLUE}iptables${RESET}"
    fi
}

# 查看端口占用情况
port_status() {
    check_firewall
    echo -e "${CYAN}端口\t协议\t状态\t类型\t占用IP${RESET}"
    
    # 使用 `ss` 命令来检查端口占用情况，并用 column 格式化输出
    ss -tuln | grep -E '^tcp|^udp' | awk '{print $5 "\t" $1 "\t" $2 "\t" $3}' | sort | column -t
}

# 查看指定端口占用情况
check_specific_ports() {
    echo -e "${CYAN}请输入要查询的端口 (单个端口，多个端口用空格分开，或使用范围如 80-90):${RESET}"
    read -r input_ports
    ports=($input_ports)
    
    for port in "${ports[@]}"; do
        ss -tuln | grep ":$port" | awk '{print $5 "\t" $1 "\t" $2 "\t" $3}' | column -t
    done
}

# 开放指定端口
open_ports() {
    check_firewall
    echo -e "${CYAN}请输入要开放的端口 (单个端口，多个端口用空格分开，或使用范围如 80-90):${RESET}"
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
        echo -e "${GREEN}端口 $port 已开放${RESET}"
    done
}

# 关闭指定端口
close_ports() {
    check_firewall
    echo -e "${CYAN}请输入要关闭的端口 (单个端口，多个端口用空格分开，或使用范围如 80-90):${RESET}"
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
        echo -e "${RED}端口 $port 已关闭${RESET}"
    done
}

# 菜单显示
menu() {
    echo -e "${BOLD}${BLUE}======================== 防火墙管理脚本 ========================${RESET}"
    echo -e "${GREEN}1.${RESET} 查看系统防火墙类型"
    echo -e "${GREEN}2.${RESET} 查看端口开放状态"
    echo -e "${GREEN}3.${RESET} 查看指定端口占用情况"
    echo -e "${GREEN}4.${RESET} 开放指定端口"
    echo -e "${GREEN}5.${RESET} 关闭指定端口"
    echo -e "${RED}6.${RESET} 退出"
    echo -e "${BOLD}${BLUE}==============================================================${RESET}"
}

# 处理用户输入，确保没有空格
get_valid_input() {
    read -p "请输入选项 [1-6]: " choice
    # 去掉空格和换行符
    choice=$(echo "$choice" | tr -d '[:space:]')
    echo "$choice"
}

# 选择菜单项
while true; do
    menu
    choice=$(get_valid_input)

    # 调试输出：确认是否读取到用户输入
    echo "调试输出: 用户输入的选项是: '$choice'"  # 调试输出

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
            echo -e "${CYAN}退出脚本${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 1 到 6 的选项。${RESET}"
            ;;
    esac
done
