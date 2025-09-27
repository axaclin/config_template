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
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 初始化变量
CURRENT_FIREWALL=""

# 函数：清空输入缓冲区
clear_input_buffer() {
    while read -t 0.1 -n 10000 discard; do
        : # 清空所有待处理的输入
    done
}

# 函数：安全读取输入
safe_read() {
    clear_input_buffer
    read "$@"
}

# 函数：显示菜单（减少清屏频率）
show_menu() {
    # 只在第一次显示菜单或需要时清屏
    if [ "${1:-}" = "clear" ]; then
        clear
    fi
    
    echo -e "${BLUE}"
    echo "=========================================="
    echo "          防火墙管理脚本 v2.1"
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
        echo -n "是否安装 $pkg？(y/n): "
        safe_read choice
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

# 函数：检测当前活动的防火墙
detect_active_firewall() {
    if [ -n "$CURRENT_FIREWALL" ]; then
        echo "$CURRENT_FIREWALL"
        return
    fi
    
    if systemctl is-active firewalld &> /dev/null; then
        CURRENT_FIREWALL="firewalld"
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        CURRENT_FIREWALL="ufw"
    elif iptables -L INPUT -n 2>/dev/null | grep -q -E "(ACCEPT|DROP|REJECT)"; then
        CURRENT_FIREWALL="iptables"
    else
        CURRENT_FIREWALL="none"
    fi
    
    echo "$CURRENT_FIREWALL"
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
            echo -e "  规则: $(ufw status | grep -c 'ALLOW') 条允许规则"
        else
            echo -e "  状态: ${YELLOW}未激活${NC}"
        fi
        found=1
    fi
    
    # 检查firewalld
    if systemctl is-active firewalld &> /dev/null; then
        echo -e "✓ Firewalld"
        echo -e "  状态: ${GREEN}运行中${NC}"
        echo -e "  区域: $(firewall-cmd --get-active-zones | grep -v '^ ' | wc -l) 个活动区域"
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
        rule_count=$(iptables -L -n | grep -E "(ACCEPT|DROP|REJECT)" | wc -l)
        if [ $rule_count -gt 0 ]; then
            echo -e "  状态: ${GREEN}有规则 ($rule_count 条)${NC}"
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
    local active_fw=$(detect_active_firewall)
    case $active_fw in
        "firewalld")
            echo -e "${GREEN}✓ Firewalld 正在运行${NC}"
            echo -e "  开放端口: $(firewall-cmd --list-ports 2>/dev/null | wc -w) 个"
            ;;
        "ufw")
            echo -e "${GREEN}✓ UFW 正在运行${NC}"
            echo -e "  开放端口: $(ufw status | grep ALLOW | wc -l) 个"
            ;;
        "iptables")
            echo -e "${GREEN}✓ iptables 正在使用${NC}"
            ;;
        "none")
            echo -e "${YELLOW}未检测到活动的防火墙，端口可能全部开放${NC}"
            ;;
    esac
    
    echo -e "\n按回车键返回菜单..."
    safe_read
}

# 函数：获取防火墙开放端口信息
get_firewall_ports() {
    local ports=()
    local active_fw=$(detect_active_firewall)
    
    case $active_fw in
        "firewalld")
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    ports+=("$line")
                fi
            done < <(firewall-cmd --list-ports 2>/dev/null)
            ;;
        "ufw")
            while IFS= read -r line; do
                if [[ $line =~ [0-9]+/(tcp|udp) ]]; then
                    ports+=("$line")
                fi
            done < <(ufw status | grep ALLOW)
            ;;
        "iptables")
            while IFS= read -r line; do
                if [[ $line =~ dpt:([0-9]+) ]]; then
                    port="${BASH_REMATCH[1]}"
                    if [[ $line =~ "(tcp|udp)" ]]; then
                        protocol="${BASH_REMATCH[1]}"
                    else
                        protocol="tcp/udp"
                    fi
                    ports+=("$port/$protocol")
                fi
            done < <(iptables -L INPUT -n 2>/dev/null | grep dpt:)
            ;;
    esac
    
    printf '%s\n' "${ports[@]}"
}

# 函数：格式化输出表格
print_table() {
    local data=("$@")
    if [ ${#data[@]} -eq 0 ]; then
        echo -e "${YELLOW}无数据可显示${NC}"
        return
    fi
    
    local headers=("端口" "协议" "状态" "类型" "占用IP/进程")
    
    # 计算每列的最大宽度
    declare -a col_widths=(8 8 10 8 20) # 最小宽度
    
    for row in "${data[@]}"; do
        IFS='|' read -ra cols <<< "$row"
        for i in "${!cols[@]}"; do
            # 去除颜色代码计算实际长度
            local clean_text=$(echo -e "${cols[$i]}" | sed 's/\x1b\[[0-9;]*m//g')
            local len=${#clean_text}
            if [ $len -gt ${col_widths[$i]} ]; then
                col_widths[$i]=$len
            fi
        done
    done
    
    # 确保表头宽度足够
    for i in "${!headers[@]}"; do
        local len=${#headers[$i]}
        if [ $len -gt ${col_widths[$i]} ]; then
            col_widths[$i]=$len
        fi
    done
    
    # 打印表头
    echo ""
    printf "%-${col_widths[0]}s  %-${col_widths[1]}s  %-${col_widths[2]}s  %-${col_widths[3]}s  %-${col_widths[4]}s\n" \
           "${headers[0]}" "${headers[1]}" "${headers[2]}" "${headers[3]}" "${headers[4]}"
    
    # 打印分隔线
    local separator=""
    for width in "${col_widths[@]}"; do
        separator+=$(printf '%*s' $((width + 2)) | tr ' ' '-')
    done
    echo "$separator"
    
    # 打印数据行
    for row in "${data[@]}"; do
        IFS='|' read -ra cols <<< "$row"
        printf "%-${col_widths[0]}s  %-${col_widths[1]}s  %-${col_widths[2]}s  %-${col_widths[3]}s  %-${col_widths[4]}s\n" \
               "${cols[0]}" "${cols[1]}" "${cols[2]}" "${cols[3]}" "${cols[4]}"
    done
    echo ""
}

# 函数：检查端口是否被占用及进程信息
get_port_process_info() {
    local port=$1
    
    # 使用netstat或ss检查端口占用
    local process_info=""
    if command -v netstat &> /dev/null; then
        process_info=$(netstat -tulpn 2>/dev/null | grep ":${port} " | head -1 | awk '{print $7}')
    elif command -v ss &> /dev/null; then
        process_info=$(ss -tulpn 2>/dev/null | grep ":${port} " | head -1 | awk '{print $NF}')
    fi
    
    if [ -n "$process_info" ] && [ "$process_info" != "-" ]; then
        echo "$process_info"
    else
        echo "未占用"
    fi
}

# 函数：检查端口占用情况
check_port_status() {
    check_and_install "ss" "iproute2" || check_and_install "netstat" "net-tools" || {
        echo -e "\n按回车键返回菜单..."
        safe_read
        return 1
    }
    
    echo -e "${BLUE}正在检查端口开放情况...${NC}"
    
    # 检查是否有活动的防火墙
    local active_fw=$(detect_active_firewall)
    
    if [ "$active_fw" = "none" ]; then
        echo -e "${YELLOW}当前系统未开启防火墙，端口全开放${NC}"
        echo -e "${BLUE}当前监听端口:${NC}"
        if command -v ss &> /dev/null; then
            ss -tuln | head -20
        else
            netstat -tuln | head -20
        fi
        echo -e "${YELLOW}(仅显示前20个监听端口)${NC}"
        echo -e "\n按回车键返回菜单..."
        safe_read
        return
    fi
    
    echo -e "${GREEN}检测到活动的防火墙: $active_fw${NC}"
    
    # 获取防火墙开放的端口
    declare -a firewall_ports
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            firewall_ports+=("$line")
        fi
    done < <(get_firewall_ports)
    
    if [ ${#firewall_ports[@]} -eq 0 ]; then
        echo -e "${YELLOW}防火墙未配置任何开放端口规则${NC}"
        echo -e "\n按回车键返回菜单..."
        safe_read
        return
    fi
    
    declare -a port_data
    declare -a ipv4_data
    declare -a ipv6_data
    
    # 处理每个防火墙端口规则
    for port_rule in "${firewall_ports[@]}"; do
        local port protocol
        
        # 解析端口规则 (格式: 端口/协议)
        if [[ $port_rule =~ ^([0-9]+)/(tcp|udp)$ ]]; then
            port="${BASH_REMATCH[1]}"
            protocol="${BASH_REMATCH[2]}"
        elif [[ $port_rule =~ ^([0-9]+)-([0-9]+)/(tcp|udp)$ ]]; then
            # 端口范围处理（简化显示第一个端口）
            port="${BASH_REMATCH[1]}"
            protocol="${BASH_REMATCH[3]}"
        else
            continue
        fi
        
        # 检查端口是否被监听
        local status process_info
        if command -v ss &> /dev/null; then
            if ss -tuln | grep -q ":${port} "; then
                status="${GREEN}占用${NC}"
                process_info=$(get_port_process_info "$port")
            else
                status="${YELLOW}未占用${NC}"
                process_info="无"
            fi
        else
            if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
                status="${GREEN}占用${NC}"
                process_info=$(get_port_process_info "$port")
            else
                status="${YELLOW}未占用${NC}"
                process_info="无"
            fi
        fi
        
        # 检查IPv6支持（简化处理）
        local ip_type="IPv4"
        if command -v ss &> /dev/null && ss -tuln | grep -q "\\[::\\]:${port} "; then
            ip_type="IPv4/IPv6"
        fi
        
        local row="${port}|${protocol}|${status}|${ip_type}|${process_info}"
        
        if [[ $ip_type == *"IPv6"* ]]; then
            ipv6_data+=("$row")
        else
            ipv4_data+=("$row")
        fi
    done
    
    # 合并数据：IPv6在前，IPv4在后
    local all_data=("${ipv6_data[@]}" "${ipv4_data[@]}")
    
    if [ ${#all_data[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到端口信息${NC}"
    else
        print_table "${all_data[@]}"
        echo -e "${GREEN}总计: ${#all_data[@]} 个端口规则${NC}"
    fi
    
    echo -e "\n按回车键返回菜单..."
    safe_read
}

# 函数：检查指定端口
check_specific_ports() {
    echo -e "${BLUE}检查指定端口占用情况${NC}"
    echo -e "${YELLOW}输入示例:${NC}"
    echo "单个端口: 80"
    echo "多个端口: 80,443,22"
    echo "端口范围: 8000-8080"
    echo ""
    
    echo -n "请输入端口号: "
    safe_read port_input
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        echo -e "\n按回车键返回菜单..."
        safe_read
        return
    fi
    
    check_and_install "ss" "iproute2" || check_and_install "netstat" "net-tools" || {
        echo -e "\n按回车键返回菜单..."
        safe_read
        return 1
    }
    
    declare -a port_data
    
    # 处理端口输入
    if [[ $port_input =~ ^[0-9]+$ ]]; then
        # 单个端口
        ports=("$port_input")
    elif [[ $port_input =~ ^[0-9]+-[0-9]+$ ]]; then
        # 端口范围
        IFS='-' read -ra range <<< "$port_input"
        local start=${range[0]}
        local end=${range[1]}
        ports=()
        for ((port=start; port<=end; port++)); do
            ports+=("$port")
        done
    elif [[ $port_input =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        # 多个端口
        IFS=',' read -ra ports <<< "$port_input"
    else
        echo -e "${RED}输入格式错误${NC}"
        echo -e "\n按回车键返回菜单..."
        safe_read
        return
    fi
    
    echo -e "${GREEN}正在检查端口: ${ports[*]}${NC}"
    
    # 检查每个端口
    for port in "${ports[@]}"; do
        local status process_info protocol="tcp/udp" ip_type="IPv4"
        
        # 检查TCP端口
        local tcp_listening=false
        local udp_listening=false
        
        if command -v ss &> /dev/null; then
            if ss -tuln | grep -q ":${port} "; then
                if ss -tln | grep -q ":${port} "; then
                    tcp_listening=true
                fi
                if ss -uln | grep -q ":${port} "; then
                    udp_listening=true
                fi
            fi
        else
            if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
                if netstat -tln 2>/dev/null | grep -q ":${port} "; then
                    tcp_listening=true
                fi
                if netstat -uln 2>/dev/null | grep -q ":${port} "; then
                    udp_listening=true
                fi
            fi
        fi
        
        if $tcp_listening && $udp_listening; then
            status="${GREEN}占用${NC}"
            protocol="tcp/udp"
        elif $tcp_listening; then
            status="${GREEN}占用${NC}"
            protocol="tcp"
        elif $udp_listening; then
            status="${GREEN}占用${NC}"
            protocol="udp"
        else
            status="${YELLOW}未占用${NC}"
            protocol="tcp/udp"
        fi
        
        process_info=$(get_port_process_info "$port")
        
        # 检查IPv6
        if command -v ss &> /dev/null && ss -tuln | grep -q "\\[::\\]:${port} "; then
            ip_type="IPv4/IPv6"
        fi
        
        port_data+=("${port}|${protocol}|${status}|${ip_type}|${process_info}")
    done
    
    if [ ${#port_data[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到端口信息${NC}"
    else
        print_table "${port_data[@]}"
    fi
    
    # 显示详细的监听信息
    echo -e "${CYAN}详细监听信息:${NC}"
    for port in "${ports[@]}"; do
        echo -e "${BLUE}端口 $port:${NC}"
        if command -v ss &> /dev/null; then
            ss -tulpn | grep ":${port} " | while read line; do
                echo "  $line"
            done
        else
            netstat -tulpn 2>/dev/null | grep ":${port} " | while read line; do
                echo "  $line"
            done
        fi
        echo ""
    done
    
    echo -e "\n按回车键返回菜单..."
    safe_read
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
    
    echo -n "请输入端口号: "
    safe_read port_input
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        echo -e "\n按回车键返回菜单..."
        safe_read
        return
    fi
    
    # 检测当前使用的防火墙
    local active_fw=$(detect_active_firewall)
    local firewall_cmd=""
    
    case $active_fw in
        "firewalld")
            firewall_cmd="firewall-cmd"
            check_and_install "firewall-cmd" "firewalld" || {
                echo -e "\n按回车键返回菜单..."
                safe_read
                return 1
            }
            ;;
        "ufw")
            firewall_cmd="ufw"
            check_and_install "ufw" "ufw" || {
                echo -e "\n按回车键返回菜单..."
                safe_read
                return 1
            }
            ;;
        "iptables"|"none")
            echo -e "${YELLOW}未检测到活动的防火墙，将尝试使用iptables${NC}"
            firewall_cmd="iptables"
            check_and_install "iptables" "iptables" || {
                echo -e "\n按回车键返回菜单..."
                safe_read
                return 1
            }
            ;;
    esac
    
    echo -e "${GREEN}使用防火墙: $firewall_cmd${NC}"
    
    # 执行开放端口操作
    case $firewall_cmd in
        "firewall-cmd")
            if [[ $port_input =~ , ]]; then
                IFS=',' read -ra ports <<< "$port_input"
                for port in "${ports[@]}"; do
                    echo -e "开放端口: $port"
                    firewall-cmd --permanent --add-port=$port
                done
            else
                firewall-cmd --permanent --add-port=$port_input
            fi
            firewall-cmd --reload
            ;;
        "ufw")
            if [[ $port_input =~ , ]]; then
                IFS=',' read -ra ports <<< "$port_input"
                for port in "${ports[@]}"; do
                    echo -e "开放端口: $port"
                    ufw allow $port
                done
            else
                ufw allow $port_input
            fi
            ;;
        "iptables")
            echo -e "${YELLOW}iptables规则需要手动保存，重启后可能失效${NC}"
            if [[ $port_input =~ /tcp$ ]]; then
                port=${port_input%/*}
                iptables -A INPUT -p tcp --dport $port -j ACCEPT
            elif [[ $port_input =~ /udp$ ]]; then
                port=${port_input%/*}
                iptables -A INPUT -p udp --dport $port -j ACCEPT
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
    
    echo -e "\n按回车键返回菜单..."
    safe_read
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
    
    echo -n "请输入端口号: "
    safe_read port_input
    
    if [ -z "$port_input" ]; then
        echo -e "${RED}输入不能为空${NC}"
        echo -e "\n按回车键返回菜单..."
        safe_read
        return
    fi
    
    # 检测当前使用的防火墙
    local active_fw=$(detect_active_firewall)
    local firewall_cmd=""
    
    case $active_fw in
        "firewalld")
            firewall_cmd="firewall-cmd"
            check_and_install "firewall-cmd" "firewalld" || {
                echo -e "\n按回车键返回菜单..."
                safe_read
                return 1
            }
            ;;
        "ufw")
            firewall_cmd="ufw"
            check_and_install "ufw" "ufw" || {
                echo -e "\n按回车键返回菜单..."
                safe_read
                return 1
            }
            ;;
        "iptables"|"none")
            echo -e "${YELLOW}未检测到活动的防火墙，将尝试使用iptables${NC}"
            firewall_cmd="iptables"
            check_and_install "iptables" "iptables" || {
                echo -e "\n按回车键返回菜单..."
                safe_read
                return 1
            }
            ;;
    esac
    
    echo -e "${GREEN}使用防火墙: $firewall_cmd${NC}"
    
    # 执行关闭端口操作
    case $firewall_cmd in
        "firewall-cmd")
            if [[ $port_input =~ , ]]; then
                IFS=',' read -ra ports <<< "$port_input"
                for port in "${ports[@]}"; do
                    echo -e "关闭端口: $port"
                    firewall-cmd --permanent --remove-port=$port
                done
            else
                firewall-cmd --permanent --remove-port=$port_input
            fi
            firewall-cmd --reload
            ;;
        "ufw")
            if [[ $port_input =~ , ]]; then
                IFS=',' read -ra ports <<< "$port_input"
                for port in "${ports[@]}"; do
                    echo -e "关闭端口: $port"
                    ufw delete allow $port
                done
            else
                ufw delete allow $port_input
            fi
            ;;
        "iptables")
            echo -e "${YELLOW}iptables规则删除需要精确匹配${NC}"
            if [[ $port_input =~ /tcp$ ]]; then
                port=${port_input%/*}
                iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || echo "规则不存在或删除失败"
            elif [[ $port_input =~ /udp$ ]]; then
                port=${port_input%/*}
                iptables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null || echo "规则不存在或删除失败"
            else
                iptables -D INPUT -p tcp --dport $port_input -j ACCEPT 2>/dev/null || echo "TCP规则不存在或删除失败"
                iptables -D INPUT -p udp --dport $port_input -j ACCEPT 2>/dev/null || echo "UDP规则不存在或删除失败"
            fi
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}端口关闭成功${NC}"
    else
        echo -e "${RED}端口关闭失败${NC}"
    fi
    
    echo -e "\n按回车键返回菜单..."
    safe_read
}

# 主循环
while true; do
    show_menu "clear"  # 只在需要时清屏
    safe_read choice
    
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
