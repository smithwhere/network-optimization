#!/bin/bash
# 保存为 dns_cross_test.sh

# --- 配置区域 ---
# 要测试的 DNS 服务器
dns_list=("1.1.1.1" "8.8.8.8")

# 要测试的目标 URL (会自动提取域名)
url_list=(
    "http://www.gstatic.com/generate_204"
    "http://cp.cloudflare.com/generate_204"
)

# 每个目标测试多少次 TCP 握手
test_count=10
# ----------------

# 颜色与格式
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 检查依赖
if ! command -v bc &> /dev/null; then echo "请安装 bc (apt/yum install bc)"; exit 1; fi
if ! command -v dig &> /dev/null; then echo "请安装 dnsutils/bind-utils"; exit 1; fi

echo -e "${GREEN}======================================================${PLAIN}"
echo -e "${GREEN}   DNS 交叉路由性能测试 (解析耗时 + 握手延迟)${PLAIN}"
echo -e "${GREEN}======================================================${PLAIN}"
printf "%-10s | %-18s | %-15s | %-8s | %-8s | %-8s | %-8s\n" "DNS" "Target" "Resolved IP" "DNS Time" "TCP Avg" "Min" "Max"
echo "-------------------------------------------------------------------------------------------"

for url in "${url_list[@]}"; do
    # 从 URL 提取域名 (去掉 http:// 和路径)
    domain=$(echo "$url" | awk -F/ '{print $3}')
    
    for dns in "${dns_list[@]}"; do
        # 1. 专门测试 DNS 解析耗时 (单次查询)
        # 这里的 dig 强制使用指定的 DNS 服务器
        dns_start=$(date +%s%N)
        # 获取解析的 IP (只取最后一行，防止 CNAME 干扰)
        resolved_ip=$(dig @$dns $domain +short +tries=1 +time=2 | tail -n 1)
        dns_end=$(date +%s%N)
        
        # 计算 DNS 耗时 (ms)
        dns_time_ms=$(echo "scale=2; ($dns_end - $dns_start) / 1000000" | bc)

        # 检查是否解析成功
        if [[ -z "$resolved_ip" || ! "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            printf "%-10s | %-18s | %-15s | %-8s | %-8s\n" "$dns" "$domain" "${RED}Failed${PLAIN}" "N/A" "N/A"
            continue
        fi

        # 2. 对解析出的 IP 进行 TCP 握手测试 (循环 N 次)
        sum=0; max=0; min=99999; success=0
        
        for ((i=1; i<=test_count; i++)); do
            # 使用 curl --resolve 强制指定域名解析到刚才 dig 出来的 IP
            # 这样能精准模拟 "如果用了这个 DNS，连接速度会是多少"
            t_connect=$(curl -w "%{time_connect}" -o /dev/null -s --connect-timeout 2 --resolve $domain:80:$resolved_ip $url)
            
            # 检查 curl 是否成功
            if [ $(echo "$t_connect == 0" | bc) -eq 1 ]; then continue; fi

            # 转换为 ms
            t_ms=$(echo "$t_connect * 1000" | bc)
            
            # 统计
            sum=$(echo "$sum + $t_ms" | bc)
            if [ $(echo "$t_ms > $max" | bc) -eq 1 ]; then max=$t_ms; fi
            if [ $(echo "$t_ms < $min" | bc) -eq 1 ]; then min=$t_ms; fi
            ((success++))
        done

        # 计算结果
        if [ $success -gt 0 ]; then
            avg=$(echo "scale=1; $sum / $success" | bc)
            
            # 颜色标记：如果 TCP 延迟超过 100ms 标红，小于 30ms 标绿
            tcp_color=$PLAIN
            if [ $(echo "$avg > 100" | bc) -eq 1 ]; then tcp_color=$RED; 
            elif [ $(echo "$avg < 30" | bc) -eq 1 ]; then tcp_color=$GREEN; fi

            printf "%-10s | %-18s | %-15s | %-8s | ${tcp_color}%-8s${PLAIN} | %-8s | %-8s\n" \
            "$dns" "$domain" "$resolved_ip" "${dns_time_ms}ms" "${avg}ms" "${min}" "${max}"
        else
            printf "%-10s | %-18s | %-15s | %-8s | ${RED}%-8s${PLAIN}\n" "$dns" "$domain" "$resolved_ip" "${dns_time_ms}ms" "Timeout"
        fi
    done
    echo "-------------------------------------------------------------------------------------------"
done