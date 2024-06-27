#!/bin/bash
###
# @Author: Berny Qi berny.qi@hj-micro.com
# @Date: 2023-02-27 14:33:37
# @LastEditors: Berny Qi
# @LastEditTime: 2023-03-28 15:55:16
###
set -e

SOCKET_SIZE=`lscpu | grep ^Socket\(s\) | awk '{print $2}'`
CORE_LIST=`numactl  -H | grep cpus | awk -F: '{print $2}'`
DATE=$(date "+%Y_%m_%d_%H_%M_%S")

# 2 socket
if [[ $SOCKET_SIZE -ne 1 ]]; then
  CORE_LIST=($CORE_LIST)
  NUM_CORES=${#CORE_LIST[@]} # core size of 2 sockets
  NUM_CORES=$((NUM_CORES / 2)) # core size of 1 socket
  CORES_CPU0=0 # 0,1,2...
  for ((i = 1; i < $NUM_CORES; i = $((i + 1)))); do
    CORES_CPU0=$CORES_CPU0,${CORE_LIST[$i]}
  done

  nodeListOfCPU0=0
  nodeListOfCPU1=$((NUMA_SIZE / 2))
  for ((i = 1; i < $((NUMA_SIZE / 2)); i = $((i + 1)))); do
    nodeListOfCPU0=$nodeListOfCPU0,$i
    nodeListOfCPU1=$nodeListOfCPU1,$((NUMA_SIZE / 2 + i))
  done

  # bandwidth of single core
  for ((k = 0; k < $NUM_CORES; k = $((k + 1)))); do
    numactl -C ${CORE_LIST[$k]} -l ./stream_c.exe >./results/$DATE/streamCore${CORE_LIST[$k]}.log
  done

  # BW of cpu0 access remote ddr.
  numactl -C $CORES_CPU0 -m $nodeListOfCPU1 ./stream_c.exe >./results/$DATE/streamCPU0CrossSocket.log

  # linearity of cpu0.
  for ((i = 0;; i = $((i + 1)))); do
    if [[ $((2**$i)) -lt 16 ]]; then
      THREAD_SIZE=$((2**$i))
    else
      THREAD_SIZE=$((THREAD_SIZE + 4))
    fi
    if [[ $THREAD_SIZE -gt $NUM_CORES ]];then
      break
    fi

    THREAD_LIST=${CORE_LIST[0]}
    for ((j = 0; j < ${THREAD_SIZE}; j = $((j + 1)))); do
      THREAD_LIST=${THREAD_LIST},${CORE_LIST[$j]}
    done
    numactl -C ${THREAD_LIST} -l ./stream_c.exe >./results/$DATE/streamServerLineratyThreads${THREAD_SIZE}.log
  done
fi



exit 0
