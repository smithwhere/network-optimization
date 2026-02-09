#!/bin/bash
export LC_ALL=C

# ================= 最佳实践参数 =================
COUNT=20
INTERVAL=1.0

DNS_SERVERS=("1.1.1.1" "8.8.8.8")
DOMAINS=("gstatic.com" "cp.cloudflare.com" "youtube.com" "reddit.com" "intel.com" "store.steampowered.com" "steamcommunity.com")
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

check_env() {
    local pkgs=""
    if ! command -v dig &> /dev/null; then pkgs="$pkgs dnsutils"; fi
    if ! command -v curl &> /dev/null; then pkgs="$pkgs curl"; fi
    if ! command -v bc &> /dev/null; then pkgs="$pkgs bc"; fi
    if ! command -v awk &> /dev/null; then pkgs="$pkgs gawk"; fi

    if [ ! -z "$pkgs" ]; then
        echo -e "${CYAN}安装必要依赖: $pkgs ...${NC}"
        if [ "$EUID" -ne 0 ]; then sudo apt-get update -qq && sudo apt-get install -y -qq $pkgs; else apt-get update -qq && apt-get install -y -qq $pkgs; fi
    fi
}

# 使用 AWK 计算 平均值 和 标准差(抖动)
calc_stats_advanced() {
    local data=("$@")
    if [ ${#data[@]} -eq 0 ]; then echo "Fail"; return; fi
    
    # 传递数组给 awk 进行统计计算
    echo "${data[@]}" | awk '{
        sum=0; sumsq=0; min=$1; max=$1;
        for(i=1;i<=NF;i++) {
            sum+=$i; 
            sumsq+=$i*$i;
            if($i<min) min=$i;
            if($i>max) max=$i;
        }
        avg = sum/NF;
        # 计算标准差 (Standard Deviation)
        if(NF > 1) {
            variance = (sumsq - (sum*sum)/NF) / (NF-1);
            if(variance < 0) variance = 0; # 防止浮点误差
            stddev = sqrt(variance);
        } else {
            stddev = 0;
        }
        
        printf "Avg:%.1f ms | Jitter:%.1f", avg, stddev
    }'
}

main() {
    check_env
    clear
    echo -e "================================================================"
    echo -e " DNS 深度质量分析 (Count: $COUNT | Interval: ${INTERVAL}s)"
    echo -e " ${CYAN}Jitter (抖动值)${NC} 越小越好。如果 Jitter > 10ms 说明线路不稳定。"
    echo -e "================================================================"
    
    # 表头
    printf "%-14s | %-15s | %-32s | %-32s\n" "Domain" "DNS Server" "DNS Resolution" "TCP Connect"
    echo "---------------------------------------------------------------------------------------------------"

    for domain in "${DOMAINS[@]}"; do
        for dns in "${DNS_SERVERS[@]}"; do
            dns_times=()
            tcp_times=()

            printf "%-14s | %-15s | Collecting samples..." "$domain" "$dns"

            for ((i=1; i<=COUNT; i++)); do
                # DNS
                t_start=$(date +%s.%N)
                dig_out=$(dig -4 @$dns $domain +short +time=2 +tries=1 2>&1)
                t_end=$(date +%s.%N)

                if [ ! -z "$dig_out" ] && [[ "$dig_out" != *"timed out"* ]]; then
                    d_time=$(echo "($t_end - $t_start) * 1000" | bc -l)
                    dns_times+=($d_time)

                    target_ip=$(echo "$dig_out" | grep -E '^[0-9.]+$' | head -n 1)
                    if [ ! -z "$target_ip" ]; then
                        c_time=$(curl -4 -o /dev/null -s -w "%{time_connect}" --resolve "$domain:443:$target_ip" "https://$domain" --connect-timeout 2)
                        c_time_ms=$(echo "$c_time * 1000" | bc -l)
                        if (( $(echo "$c_time_ms > 0" | bc -l) )); then tcp_times+=($c_time_ms); fi
                    fi
                fi
                sleep $INTERVAL
            done

            d_res=$(calc_stats_advanced "${dns_times[@]}")
            t_res=$(calc_stats_advanced "${tcp_times[@]}")
            
            # 打印最终结果
            printf "\r%-14s | %-15s | %-32s | %-32s\n" "$domain" "$dns" "$d_res" "$t_res"
        done
        echo "---------------------------------------------------------------------------------------------------"
    done
}

main