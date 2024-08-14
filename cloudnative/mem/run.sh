#!/bin/bash

os_version=$(cat /etc/redhat-release)
if [[ "$os_version" == *"release 7.9"* ]]; then
    echo "The OS Platform is $os_version"
elif [[ "$os_version" == *"release 8"* ]]; then
    echo "The OS Platform is $os_version"
else
    echo "Unknown OS Platform"
    exit 1
fi

architecture=$(uname -m)
echo "The Architecture is $architecture"

vendor=$(lscpu | grep "BIOS Vendor ID" | awk '{ print $4}')
echo "CPU Vendor is $vendor"

prepare_env() {
    yum install -y libtirpc libtirpc-devel
    if [[ "$os_version" == *"release 7.9"* ]]; then
        source /opt/rh/devtoolset-10/enable
    else
        source /opt/rh/gcc-toolset-10/enable
    fi
}

run_lmbench() {
    cd lmbench3
    make -j
    cd -

    if [ "$architecture" == "x86_64" ]; then
        lmbench_path="lmbench3/bin/x86_64-linux-gnu/lat_mem_rd"
    else
        lmbench_path="lmbench3/bin/lat_mem_rd"
    fi

    command="numactl -C $cpu -l $lmbench_path -P 1 -W 1 -N 1 -t 512 64"
    echo "Command: $command"
    
    echo "benchmark lmbench" >> "$result_file"
    echo "Command: $command" >> "$result_file"
    echo "latency" >> "$result_file"
    
    total=0
    for ((i=1; i<="$rounds"; i++))
    do
        current_time=$(date +"%Y%m%d_%H%M%S")
        output_file="$result_dir/lmbench_$current_time.txt"
        eval $command > "$output_file" 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Something wrong when running lmbench3, see output $output_file"
            exit 1
        fi
        val=$(grep -v '^$' "$output_file" | tail -n 1 | awk '{print $2}')
        total=$(echo "$total + $val" | bc)
        echo "$val" >> "$result_file"
    done
    
    average=$(echo "scale=4; $total / $rounds" | bc)
    echo "average_latency" >> "$result_file"
    echo "$average" >> "$result_file"
}

stream() {
    cd stream
    make -j
    cd -

    local core=$1
    export GOMP_CPU_AFFINITY="$core"
    command="numactl -C $core -l ./stream/stream_c.exe"
    echo "Command: $command"
    
    echo "benchmark stream" >> "$result_file"
    echo "Command: $command" >> "$result_file"
    echo "copy,scale,add,triad" >> "$result_file"
    
    total_copy=0
    total_scale=0
    total_add=0
    total_triad=0
    for ((i=1; i<="$rounds"; i++))
    do
        current_time=$(date +"%Y%m%d_%H%M%S")
        output_file="$result_dir/stream_$current_time.txt"
        eval $command > "$output_file" 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Something wrong when running stream, see output $output_file"
            exit 1
        fi
        val=$(grep -A 4 '^Function' "$output_file")
        val_copy=$(echo "$val" | awk 'NR==2 {print $2}')
        val_scale=$(echo "$val" | awk 'NR==3 {print $2}')
        val_add=$(echo "$val" | awk 'NR==4 {print $2}')
        val_triad=$(echo "$val" | awk 'NR==5 {print $2}')
        total_copy=$(echo "$total_copy + $val_copy" | bc)
        total_scale=$(echo "$total_scale + $val_scale" | bc)
        total_add=$(echo "$total_add + $val_add" | bc)
        total_triad=$(echo "$total_triad + $val_triad" | bc)
        echo "$val_copy,$val_scale,$val_add,$val_triad" >> "$result_file"
    done
    
    average_copy=$(echo "scale=4; $total_copy / $rounds" | bc)
    average_scale=$(echo "scale=4; $total_scale / $rounds" | bc)
    average_add=$(echo "scale=4; $total_add / $rounds" | bc)
    average_triad=$(echo "scale=4; $total_triad / $rounds" | bc)
    echo "" >> "$result_file"
    echo "average_copy,average_scale,average_add,average_triad" >> "$result_file"
    echo "$average_copy,$average_scale,$average_add,$average_triad" >> "$result_file"
}

run_stream() {
    cd stream
    make -j
    cd -
    stream "$cpu"
    stream "$multicpu"
}

set_multicore() {
    node_arr=()
    IFS=',' read -r -a ranges <<< "`cat /sys/devices/system/node/node0/cpulist`"
    for range in "${ranges[@]}"; do
        if [[ "$range" == *-* ]]; then
            # 如果是范围，如 "1-4"
            start=${range%-*}  # 获取范围起点
            end=${range#*-}    # 获取范围终点
            for ((i=start; i<=end; i++)); do
                node_arr+=("$i")
            done
        else
            # 如果是单个值，如 "8"
            node_arr+=("$range")
        fi
    done

    #echo "cpu list on numa node0"
    #for i in "${!node_arr[@]}"; do
    #    echo "node_arr[$i] = ${node_arr[$i]}"
    #done

    cpu_arr=()
    count=32
    for i in "${node_arr[@]}"; do
        cpu_arr+=(`cat /sys/devices/system/cpu/cpu$i/topology/core_cpus_list`)
        count=$count-1
        if [ "$architecture" == "x86_64" ]; then
            count=$count-1
        fi
        if [[ "$count" -le 0 ]]; then
            break
        fi
    done

    #echo "cpu pair on numa node0"
    #for i in "${!cpu_arr[@]}"; do
    #    echo "cpu_arr[$i] = ${cpu_arr[$i]}"
    #done

    multicpu=$(printf "%s," "${cpu_arr[@]}")
    multicpu=${multicpu%,}
    #echo $multicpu
}

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --cpu <cpu>            Specify the CPU core for single-core memory testing (default: 8)"
    echo "  -mc, --multicpu <range>    Specify the CPU core list for multi-core memory testing (default: 0-31)"
    echo "  --host                     Indicates that the test is running on a host environment"
    echo "                             Auto configure test CPU cores"
    echo "  --virt                     Indicates that the test is running on a virtual machine"
    echo "                             Auto configure test CPU cores"
    echo "                             Sets single-core=8 and multi-core=[0-31]"
    echo "  -r, --round <rounds>       Specify the number of memory test rounds (default: 5)"
    echo "  -o, --output <result_dir>  Specify the data results path (default: results)"
    echo "  -h, --help                 Show this help message and exit"
    exit 0
}

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--cpu)
            cpu="$2"
            shift 2
            ;;
        -mc|--multicpu)
            multicpu="$2"
            shift 2
            ;;
        --host)
            if [[ -z "$cpu" ]]; then
                if [[ "$architecture" == "x86_64" ]]; then
                    if [[ "$vendor" == "AMD" ]]; then
                        cpu=12
                    else
                        cpu=16
                    fi
                elif [[ "$architecture" == "aarch64" ]]; then
                    cpu=16
                else
                    echo "Unsupported architecture: $architecture"
                    exit 1
                fi
            fi

            if [[ -z "$multicpu" ]]; then
                if [[ "$architecture" == "x86_64" ]]; then
                    set_multicore
                elif [[ "$architecture" == "aarch64" ]]; then
                    multicpu="0-31"
                else
                    echo "Unsupported architecture: $architecture"
                    exit 1
                fi
            fi
            shift
            ;;
        --virt)
            if [[ -z "$cpu" ]]; then
                cpu=8
            fi

            if [[ -z "$multicpu" ]]; then
                multicpu="0-31"
            fi
            shift
            ;;
        -o|--output)
            result_dir="$2"
            shift 2
            ;;
        -r|--round)
            rounds="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown parameter passed: $1"
            echo "Use -h or --help to see usage information."
            exit 1
            ;;
    esac
done


if [[ -z "$rounds" ]]; then
    rounds=5
fi

if [[ -z "$cpu" ]]; then
    cpu=8
fi

if [[ -z "$multicpu" ]]; then
    multicpu="0-31"
fi

echo "single-core: $cpu"
echo "multi-core: $multicpu"
echo "Rounds: $rounds"

if [[ -z "$result_dir" ]]; then
    result_dir="results"
fi

if [ ! -d "$result_dir" ]; then
    mkdir -p "$result_dir"
fi

current_time=$(date +"%Y%m%d_%H%M%S")
result_file="$result_dir/virt_mem$current_time.txt"

result_dir="$result_dir/virt_mem$current_time"
if [ ! -d "$result_dir" ]; then
    mkdir -p "$result_dir"
fi

echo "results directory: $result_dir"

prepare_env
run_lmbench
run_stream

echo "results file: $result_file"
