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
    echo "          防火墙管理脚本 v1.0"
    echo "=========================================="
    echo -e "${NC}"
    echo "1. 系统防火墙类型检查"
    echo "2. 开放端口占用情况"
    echo "3. 指定端口占用情况"
    echo "4. 开放指定端口"
    echo "5. 关闭指定端口"
    echo "6. 退出"
    echo "=========================================="
    echo -n "请选择操作 [1-6]: "
}

# 函数：检查命令是否存在，不存在则安装
check_and_install() {
    local cmd=$1
    local pkg=$2
    
    if ! command -v $cmd &> /dev/null; then
        echo -e "${YELLOW}未找到 $cmd，需要安装...${NC}"
        read -p "是否安装 $pkg？(y/n): " choice
        if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
            if command -v apt-get &> /dev/null; then
                apt-get update
                apt-get install -y $pkg
            elif command -v yum &> /dev/null; then
                yum install -y $pkg
            elif command -v dnf &> /dev/null; then
                dnf install -y $pkg
            else
                echo -e "${RED}无法自动安装，请手动安装 $pkg${NC}"
                return 1
            fi
        else
            return 1
        fi
    fi
    return 0
}

# 函数：检测防火墙类型
check_firewall_type() {
    echo -e "${BLUE}正在检测系统防火墙类型...${NC}"
    echo ""
    
    # 检查已安装的防火墙软件
    echo -e "${YELLOW}已安装的防火墙软件:${NC}"
    local found=0
    
    # 检查UFW
    if command -v ufw &> /dev/null; then
        echo -e "✓ UFW (Uncomplicated Firewall)"
        ufw_status=$(ufw status 2>/dev/null | grep "Status")
        if [[ $ufw_status == *"active"* ]]; then
            echo -e "  状态: ${GREEN}运行中${NC}"
        else
            echo -e "  状态: ${YELLOW}未激活${NC}"
        fi
        found=1
    fi
    
    # 检查firewalld
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "✓ Firewalld"
        echo -e "  状态: ${GREEN}运行中${NC}"
        found=1
    elif command -v firewall-cmd &> /dev/null; then
        echo -e "✓ Firewalld"
        echo -e "  状态: ${YELLOW}未激活${NC}"
        found=1
    fi
    
    # 检查iptables
    if command -v iptables &> /dev/null; then
        echo -e "✓ iptables"
        # 检查是否有规则
        if iptables -L | grep -q -v "Chain INPUT (policy ACCEPT)" || iptables -L | grep -q "target"; then
            echo -e "  状态: ${GREEN}有规则${NC}"
        else
            echo -e "  状态: ${YELLOW}无规则${NC}"
        fi
        found=1
    fi
    
    if [ $found -eq 0 ]; then
        echo -e "${YELLOW}未检测到常见的防火墙软件${NC}"
    fi
    
    echo ""
    
    # 检测当前正在使用的防火墙
    echo -e "${YELLOW}当前活动的防火墙:${NC}"
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "${GREEN}✓ Firewalld 正在运行${NC}"
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${GREEN}✓ UFW 正在运行${NC}"
    elif iptables -L 2>/dev/null | grep -q -v "Chain INPUT (policy ACCEPT)"; then
        echo -e "${GREEN}✓ iptables 正在使用${NC}"
    else
        echo -e "${YELLOW}未检测到活动的防火墙，端口可能全部开放${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 函数：格式化输出表格
print_table() {
    local data=("$@")
    local headers=("端口" "协议" "状态" "类型" "占用IP")
    
    # 计算每列的最大宽度
    declare -a col_widths=(6 6 8 6 15) # 最小宽度
    
    for row in "${data[@]}"; do
        IFS='|' read -ra cols <<< "$row"
        for i in "${!cols[@]}"; do
            local len=${#cols[$i]}
            if [ $len -gt ${col_widths[$i]} ]; then
                col_widths[$i]=$len
            fi
        done
    done
    
    # 打印表头
    echo ""
    printf "%-${col_widths[0]}s  %-${col_widths[1]}s  %-${col_widths[2]}s  %-${col_widths[3]}s  %-${col_widths[4]}s\n" \
           "${headers[0]}" "${headers[1]}" "${headers[2]}" "${headers[3]}" "${headers[4]}"
    
    # 打印分隔线
    local total_width=0
    for width in "${col_widths[@]}"; do
        total_width=$((total_width + width + 2))
    done
    printf '%*s\n' $total_width | tr ' ' '-'
    
    # 打印数据行
    for row in "${data[@]}"; do
        IFS='|' read -ra cols <<< "$row"
        printf "%-${col_widths[0]}s  %-${col_widths[1]}s  %-${col_widths[2]}s  %-${col_widths[3]}s  %-${col_widths[4]}s\n" \
               "${cols[0]}" "${cols[1]}" "${cols[2]}" "${cols[3]}" "${cols[4]}"
    done
    echo ""
}

# 函数：检查端口占用情况
check_port_status() {
    check_and_install "ss" "iproute2" || return 1
    
    echo -e "${BLUE}正在检查端口开放情况...${NC}"
    
    # 检查是否有活动的防火墙
    local active_firewall="none"
    if systemctl is-active firewalld &> /dev/null; then
        active_firewall="firewalld"
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        active_firewall="ufw"
    elif iptables -L 2>/dev/null | grep -q -v "Chain INPUT (policy ACCEPT)"; then
        active_firewall="iptables"
    fi
    
    if [ "$active_firewall" = "none" ]; then
        echo -e "${YELLOW}当前系统未开启防火墙，端口全开放${NC}"
        echo -e "${BLUE}当前监听端口:${NC}"
        ss -tuln | grep LISTEN | head -20
        echo -e "${YELLOW}(仅显示前20个监听端口)${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    echo -e "${GREEN}检测到活动的防火墙: $active_firewall${NC}"
    
    # 获取监听端口信息
    declare -a port_data
    declare -a ipv4_data
    declare -a ipv6_data
    
    # 使用ss命令获取详细的端口信息
    while IFS= read -r line; do
        if [[ $line =~ ^(tcp|udp)[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+([^:]+):([0-9]+)[[:space:]]+.*$ ]]; then
            local protocol=${BASH_REMATCH[1]}
            local ip=${BASH_REMATCH[2]}
            local port=${BASH_REMATCH[3]}
            local type="IPv4"
            
            # 判断IP类型
            if [[ $ip == *"["*"]"* ]]; then
                type="IPv6"
            fi
            
            # 检查端口是否被占用
            local status="未占用"
            if ss -tuln | grep -q ":$port "; then
                status="占用"
            fi
            
            local row="$port|$protocol|$status|$type|$ip"
            
            if [ "$type" = "IPv4" ]; then
                ipv4_data+=("$row")
            else
                ipv6_data+=("$row")
            fi
        fi
    done < <(ss -tuln)
    
    # 合并数据：IPv6在前，IPv4在后
    local all_data=("${ipv6_data[@]}" "${ipv4_data[@]}")
    
    if [ ${#all_data[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到端口信息${NC}"
    else
        print_table "${all_data[@]}"
    fi
    
    read -p "按回车键继续..."
}

# 函数：检查指定端口
check_specific_ports() {
    echo -e "${BLUE}检查指定端口占用情况${NC}"
    echo -e "${YELLOW}输入示例:${NC}"
    echo "单个端口: 80"
    echo "多个端口: 80,443,22"
    echo "端口范围: 8000-8080"
    echo ""
    
    read -p "请输入端口号: " port_input
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    check_and_install "ss" "iproute2" || return 1
    
    # 处理端口输入
    if [[ $port_input =~ ^[0-9]+$ ]]; then
        # 单个端口
        echo -e "${GREEN}检查端口 $port_input:${NC}"
        ss -tuln | grep ":$port_input "
    elif [[ $port_input =~ ^[0-9]+-[0-9]+$ ]]; then
        # 端口范围
        IFS='-' read -ra ports <<< "$port_input"
        local start=${ports[0]}
        local end=${ports[1]}
        echo -e "${GREEN}检查端口范围 $start-$end:${NC}"
        for ((port=start; port<=end; port++)); do
            result=$(ss -tuln | grep ":$port ")
            if [ -n "$result" ]; then
                echo "端口 $port: $result"
            fi
        done
    elif [[ $port_input =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        # 多个端口
        IFS=',' read -ra ports <<< "$port_input"
        echo -e "${GREEN}检查多个端口:${NC}"
        for port in "${ports[@]}"; do
            result=$(ss -tuln | grep ":$port ")
            if [ -n "$result" ]; then
                echo "端口 $port: $result"
            else
                echo "端口 $port: 未监听"
            fi
        done
    else
        echo -e "${RED}输入格式错误${NC}"
    fi
    
    read -p "按回车键继续..."
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
    
    read -p "请输入端口号: " port_input
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    # 检测当前使用的防火墙
    local firewall_cmd=""
    if systemctl is-active firewalld &> /dev/null; then
        firewall_cmd="firewall-cmd"
        check_and_install "firewall-cmd" "firewalld" || return 1
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        firewall_cmd="ufw"
        check_and_install "ufw" "ufw" || return 1
    else
        echo -e "${YELLOW}未检测到活动的防火墙，将使用iptables${NC}"
        firewall_cmd="iptables"
        check_and_install "iptables" "iptables" || return 1
    fi
    
    echo -e "${GREEN}使用防火墙: $firewall_cmd${NC}"
    
    # 执行开放端口操作
    case $firewall_cmd in
        "firewall-cmd")
            firewall-cmd --permanent --add-port=$port_input
            firewall-cmd --reload
            ;;
        "ufw")
            ufw allow $port_input
            ;;
        "iptables")
            # 简化处理，实际应该更复杂
            if [[ $port_input =~ /tcp$ ]]; then
                iptables -A INPUT -p tcp --dport ${port_input%/*} -j ACCEPT
            elif [[ $port_input =~ /udp$ ]]; then
                iptables -A INPUT -p udp --dport ${port_input%/*} -j ACCEPT
            else
                iptables -A INPUT -p tcp --dport $port_input -j ACCEPT
                iptables -A INPUT -p udp --dport $port_input -j ACCEPT
            fi
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}端口开放成功${NC}"
    else
        echo -e "${RED}端口开放失败${NC}"
    fi
    
    read -p "按回车键继续..."
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
    
    read -p "请输入端口号: " port_input
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    # 检测当前使用的防火墙
    local firewall_cmd=""
    if systemctl is-active firewalld &> /dev/null; then
        firewall_cmd="firewall-cmd"
        check_and_install "firewall-cmd" "firewalld" || return 1
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        firewall_cmd="ufw"
        check_and_install "ufw" "ufw" || return 1
    else
        echo -e "${YELLOW}未检测到活动的防火墙，将使用iptables${NC}"
        firewall_cmd="iptables"
        check_and_install "iptables" "iptables" || return 1
    fi
    
    echo -e "${GREEN}使用防火墙: $firewall_cmd${NC}"
    
    # 执行关闭端口操作
    case $firewall_cmd in
        "firewall-cmd")
            firewall-cmd --permanent --remove-port=$port_input
            firewall-cmd --reload
            ;;
        "ufw")
            ufw delete allow $port_input
            ;;
        "iptables")
            # 简化处理
            if [[ $port_input =~ /tcp$ ]]; then
                iptables -D INPUT -p tcp --dport ${port_input%/*} -j ACCEPT
            elif [[ $port_input =~ /udp$ ]]; then
                iptables -D INPUT -p udp --dport ${port_input%/*} -j ACCEPT
            else
                iptables -D INPUT -p tcp --dport $port_input -j ACCEPT
                iptables -D INPUT -p udp --dport $port_input -j ACCEPT
            fi
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}端口关闭成功${NC}"
    else
        echo -e "${RED}端口关闭失败${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 主循环
while true; do
    show_menu
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
