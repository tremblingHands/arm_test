#!/bin/bash

rounds=5
cpu=6
multicpu=0-31

if [ ! -z "$1" ]; then
    cpu=$1
fi

if [ ! -z "$2" ]; then
    multicpu=$2
fi

architecture=$(uname -m)

if [ "$architecture" == "x86_64" ]; then
    echo "The architecture is x86_64"
elif [ "$architecture" == "aarch64" ]; then
    echo "The architecture is aarch64"
else
    echo "Unknown architecture: $architecture"
    exit 1
fi

result_dir="results"

if [ ! -d "$result_dir" ]; then
    mkdir -p "$result_dir"
fi

current_time=$(date +"%Y%m%d_%H%M%S")
result_file="$result_dir/virt_mem$current_time.txt"

result_dir="$result_dir/virt_mem$current_time"
if [ ! -d "$result_dir" ]; then
    mkdir -p "$result_dir"
fi

prepare_env() {
    yum install -y libtirpc libtirpc-devel
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

prepare_env
run_lmbench
run_stream

