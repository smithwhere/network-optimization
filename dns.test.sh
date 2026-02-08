#!/bin/bash
# 保存为 dns_test_pro.sh

# --- 配置区域 ---
check_domain="www.google.com"
test_count=10
targets=("1.1.1.1" "8.8.8.8")
# ----------------

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKY='\033[0;36m'
PLAIN='\033[0m'

echo -e "${GREEN}--- DNS 深度优选脚本 (每项测试 $test_count 次) ---${PLAIN}"
echo -e "测试目标: ${YELLOW}$check_domain${PLAIN}"

# 检查依赖
if ! command -v bc &> /dev/null; then
    echo -e "${RED}错误: 需要安装 bc 计算器 (apt install bc / yum install bc)${PLAIN}"
    # 尝试自动安装 (可选)
    # exit 1
fi

for dns in "${targets[@]}"; do
    echo -e "\n------------------------------------------------"
    echo -e "正在测试 DNS: ${SKY}$dns${PLAIN}"
    
    # 获取一次解析结果用于显示 IP
    resolved_ip=$(dig @$dns +short $check_domain +time=1 +tries=1 | head -1)
    if [ -z "$resolved_ip" ]; then
        echo -e "${RED}无法解析或超时，跳过此 DNS${PLAIN}"
        continue
    fi
    echo -e "解析结果 IP : ${YELLOW}$resolved_ip${PLAIN}"
    
    # 初始化变量
    declare -a tcp_times
    sum=0
    max=0
    min=99999
    success_count=0

    # 开始循环测试
    echo -ne "进度: "
    for ((i=1; i<=test_count; i++)); do
        # 1. 测 TCP 握手 (更具参考价值)
        # 使用 curl --resolve 强制指定 IP
        t_start=$(date +%s%N)
        
        # 只测握手，超时设为 2秒
        curl_res=$(curl -w "%{time_connect}" -o /dev/null -s --connect-timeout 2 --resolve $check_domain:443:$resolved_ip https://$check_domain)
        
        # 检查是否成功 (curl 返回 0.000 表示失败)
        if [ $(echo "$curl_res == 0" | bc) -eq 1 ]; then
            echo -ne "${RED}x${PLAIN}"
            continue
        else
            echo -ne "${GREEN}.${PLAIN}"
        fi

        # 换算成 ms
        t_ms=$(echo "$curl_res * 1000" | bc)
        
        # 记录数据
        tcp_times+=($t_ms)
        sum=$(echo "$sum + $t_ms" | bc)
        
        # 更新 Max
        if [ $(echo "$t_ms > $max" | bc) -eq 1 ]; then max=$t_ms; fi
        
        # 更新 Min
        if [ $(echo "$t_ms < $min" | bc) -eq 1 ]; then min=$t_ms; fi
        
        ((success_count++))
    done
    echo "" # 换行

    # 计算统计数据
    if [ $success_count -gt 0 ]; then
        avg=$(echo "scale=2; $sum / $success_count" | bc)
        
        # 打印漂亮的统计表格
        echo -e "  -> ${GREEN}Min (最快): ${min} ms${PLAIN}"
        echo -e "  -> ${RED}Max (最慢): ${max} ms${PLAIN}"
        echo -e "  -> ${SKY}Avg (平均): ${avg} ms${PLAIN}"
        
        # 抖动值 (Max - Min)
        jitter=$(echo "$max - $min" | bc)
        echo -e "  -> 抖动 (稳定性): ${YELLOW}${jitter} ms${PLAIN}"
    else
        echo -e "  -> ${RED}全部连接失败${PLAIN}"
    fi
done
echo -e "\n------------------------------------------------"