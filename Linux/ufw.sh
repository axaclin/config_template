#!/bin/bash

# 检查脚本是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请以root权限运行此脚本"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函数：显示菜单
show_menu() {
    clear
    echo -e "${BLUE}"
    echo "=========================================="
    echo "          防火墙管理脚本 v2.2"
    echo "=========================================="
    echo -e "${NC}"
    echo "1. 系统防火墙类型检查"
    echo "2. 开放端口占用情况"
    echo "3. 指定端口占用情况"
    echo "4. 开放指定端口"
    echo "5. 关闭指定端口"
    echo "6. 退出"
    echo "=========================================="
}

# 函数：获取用户输入
get_user_input() {
    local prompt="$1"
    echo -n "$prompt"
    read input
    echo "$input"
}

# 函数：检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v $cmd &> /dev/null; then
        echo -e "${YELLOW}警告: 未找到 $cmd 命令${NC}"
        return 1
    fi
    return 0
}

# 函数：检测防火墙类型
check_firewall_type() {
    echo -e "${BLUE}正在检测系统防火墙类型...${NC}"
    echo ""
    
    # 检查UFW
    if check_command ufw; then
        echo -e "✓ UFW (Uncomplicated Firewall)"
        ufw_status=$(ufw status 2>/dev/null | grep "Status")
        if [[ $ufw_status == *"active"* ]]; then
            echo -e "  状态: ${GREEN}运行中${NC}"
        else
            echo -e "  状态: ${YELLOW}未激活${NC}"
        fi
    fi
    
    # 检查firewalld
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "✓ Firewalld"
        echo -e "  状态: ${GREEN}运行中${NC}"
    elif check_command firewall-cmd; then
        echo -e "✓ Firewalld"
        echo -e "  状态: ${YELLOW}未激活${NC}"
    fi
    
    # 检查iptables
    if check_command iptables; then
        echo -e "✓ iptables"
        rule_count=$(iptables -L -n | grep -E "(ACCEPT|DROP|REJECT)" | wc -l)
        if [ $rule_count -gt 0 ]; then
            echo -e "  状态: ${GREEN}有规则${NC}"
        else
            echo -e "  状态: ${YELLOW}无规则${NC}"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}按回车键返回菜单...${NC}"
    read
}

# 函数：检查端口占用情况
check_port_status() {
    echo -e "${BLUE}正在检查端口开放情况...${NC}"
    
    # 检查是否有活动的防火墙
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "${GREEN}检测到活动的防火墙: Firewalld${NC}"
        firewall-cmd --list-ports
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${GREEN}检测到活动的防火墙: UFW${NC}"
        ufw status
    elif iptables -L INPUT -n 2>/dev/null | grep -q -E "(ACCEPT|DROP|REJECT)"; then
        echo -e "${GREEN}检测到活动的防火墙: iptables${NC}"
        iptables -L -n
    else
        echo -e "${YELLOW}当前系统未开启防火墙，端口全开放${NC}"
        echo -e "${BLUE}当前监听端口:${NC}"
        if check_command ss; then
            ss -tuln | head -20
        elif check_command netstat; then
            netstat -tuln | head -20
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}按回车键返回菜单...${NC}"
    read
}

# 函数：检查指定端口
check_specific_ports() {
    echo -e "${BLUE}检查指定端口占用情况${NC}"
    echo -e "${YELLOW}输入示例:${NC}"
    echo "单个端口: 80"
    echo "多个端口: 80,443,22"
    echo "端口范围: 8000-8080"
    echo ""
    
    port_input=$(get_user_input "请输入端口号: ")
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        echo -e "${YELLOW}按回车键返回菜单...${NC}"
        read
        return
    fi
    
    echo -e "${GREEN}正在检查端口: $port_input${NC}"
    
    # 使用netstat或ss检查端口
    if check_command ss; then
        if [[ $port_input =~ ^[0-9]+$ ]]; then
            ss -tuln | grep ":$port_input "
        elif [[ $port_input =~ ^[0-9]+-[0-9]+$ ]]; then
            IFS='-' read -ra range <<< "$port_input"
            start=${range[0]}
            end=${range[1]}
            for ((port=start; port<=end; port++)); do
                echo "端口 $port:"
                ss -tuln | grep ":$port " || echo "  未监听"
            done
        elif [[ $port_input =~ ^[0-9]+(,[0-9]+)*$ ]]; then
            IFS=',' read -ra ports <<< "$port_input"
            for port in "${ports[@]}"; do
                echo "端口 $port:"
                ss -tuln | grep ":$port " || echo "  未监听"
            done
        fi
    elif check_command netstat; then
        if [[ $port_input =~ ^[0-9]+$ ]]; then
            netstat -tuln 2>/dev/null | grep ":$port_input "
        elif [[ $port_input =~ ^[0-9]+-[0-9]+$ ]]; then
            IFS='-' read -ra range <<< "$port_input"
            start=${range[0]}
            end=${range[1]}
            for ((port=start; port<=end; port++)); do
                echo "端口 $port:"
                netstat -tuln 2>/dev/null | grep ":$port " || echo "  未监听"
            done
        elif [[ $port_input =~ ^[0-9]+(,[0-9]+)*$ ]]; then
            IFS=',' read -ra ports <<< "$port_input"
            for port in "${ports[@]}"; do
                echo "端口 $port:"
                netstat -tuln 2>/dev/null | grep ":$port " || echo "  未监听"
            done
        fi
    else
        echo -e "${RED}未找到可用的端口检查工具${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}按回车键返回菜单...${NC}"
    read
}

# 函数：开放端口
open_ports() {
    echo -e "${BLUE}开放指定端口${NC}"
    echo -e "${YELLOW}输入示例:${NC}"
    echo "单个端口: 80"
    echo "带协议端口: 80/tcp"
    echo "多个端口: 80,443,22"
    echo "端口范围: 8000-8080/tcp"
    echo ""
    
    port_input=$(get_user_input "请输入端口号: ")
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        echo -e "${YELLOW}按回车键返回菜单...${NC}"
        read
        return
    fi
    
    # 检测当前使用的防火墙
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "${GREEN}使用防火墙: Firewalld${NC}"
        firewall-cmd --permanent --add-port=$port_input
        firewall-cmd --reload
        result=$?
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${GREEN}使用防火墙: UFW${NC}"
        ufw allow $port_input
        result=$?
    elif check_command iptables; then
        echo -e "${GREEN}使用防火墙: iptables${NC}"
        if [[ $port_input =~ /tcp$ ]]; then
            iptables -A INPUT -p tcp --dport ${port_input%/*} -j ACCEPT
        elif [[ $port_input =~ /udp$ ]]; then
            iptables -A INPUT -p udp --dport ${port_input%/*} -j ACCEPT
        else
            iptables -A INPUT -p tcp --dport $port_input -j ACCEPT
            iptables -A INPUT -p udp --dport $port_input -j ACCEPT
        fi
        result=$?
    else
        echo -e "${RED}未找到可用的防火墙工具${NC}"
        result=1
    fi
    
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}端口开放成功${NC}"
    else
        echo -e "${RED}端口开放失败${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}按回车键返回菜单...${NC}"
    read
}

# 函数：关闭端口
close_ports() {
    echo -e "${BLUE}关闭指定端口${NC}"
    echo -e "${YELLOW}输入示例:${NC}"
    echo "单个端口: 80"
    echo "带协议端口: 80/tcp"
    echo "多个端口: 80,443,22"
    echo "端口范围: 8000-8080/tcp"
    echo ""
    
    port_input=$(get_user_input "请输入端口号: ")
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        echo -e "${YELLOW}按回车键返回菜单...${NC}"
        read
        return
    fi
    
    # 检测当前使用的防火墙
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "${GREEN}使用防火墙: Firewalld${NC}"
        firewall-cmd --permanent --remove-port=$port_input
        firewall-cmd --reload
        result=$?
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${GREEN}使用防火墙: UFW${NC}"
        ufw delete allow $port_input
        result=$?
    elif check_command iptables; then
        echo -e "${GREEN}使用防火墙: iptables${NC}"
        if [[ $port_input =~ /tcp$ ]]; then
            iptables -D INPUT -p tcp --dport ${port_input%/*} -j ACCEPT 2>/dev/null
        elif [[ $port_input =~ /udp$ ]]; then
            iptables -D INPUT -p udp --dport ${port_input%/*} -j ACCEPT 2>/dev/null
        else
            iptables -D INPUT -p tcp --dport $port_input -j ACCEPT 2>/dev/null
            iptables -D INPUT -p udp --dport $port_input -j ACCEPT 2>/dev/null
        fi
        result=$?
    else
        echo -e "${RED}未找到可用的防火墙工具${NC}"
        result=1
    fi
    
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}端口关闭成功${NC}"
    else
        echo -e "${RED}端口关闭失败${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}按回车键返回菜单...${NC}"
    read
}

# 主循环
while true; do
    show_menu
    echo -n "请选择操作 [1-6]: "
    read choice
    
    case $choice in
        1)
            check_firewall_type
            ;;
        2)
            check_port_status
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
            echo -e "${GREEN}再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重新输入${NC}"
            sleep 2
            ;;
    esac
done
