#!/bin/bash
set -e

SKIP_KERNEL_VERSION_CHECK=0
SOCKET_NUM=2
NEED_CPUPOWER_OPS=0
MACHINE=

QEMU_VERSION="7.1.0"
QEMU_DIR="/usr/local/qemu"
FIO_VERSION="3.36"


VM_MEM_NUMA_NODE=0
VM_CPU_START_INDEX=8
VM_CPU_NUM=32
VM_CPU_LIST="vm_cpu_list_empty"
VM_CPU_LIST_FIRST_START="vm_cpu_list_first_start_empty"
VM_CPU_LIST_SECOND_START="vm_cpu_list_second_start_empty"
ISOLATION_CPU_CMDLINE="isolation_cpu_cmdline_empty"


FIO_TEST_DEVICE=
IPERF_TEST_DEVICE=

ARCH=$(uname -i)
CENTOS_VERSION_STR=$(cat /etc/os-release | (grep PRETTY_NAME || true) | sed 's|"| |g' | awk '{print $2 $3 $4}')
if [ "$CENTOS_VERSION_STR" == "CentOSStream8" ]; then
    CENTOS_VERSION="centos-8-stream"
    KERNEL_VERSION="5.10.0_stream"
    GCC_TOOLSET="gcc-toolset-10"
elif [ "$CENTOS_VERSION_STR" == "CentOSLinux7" ]; then
    CENTOS_VERSION="centos-7"
    KERNEL_VERSION=""
    GCC_TOOLSET="devtoolset-10"
fi
CHOOSE_DIR="${ARCH}/${CENTOS_VERSION}"

WORKSPACE_DIR=$(
    path=$(pwd)
    dirname $path
)
BENCHMARK_DIR="${WORKSPACE_DIR}/benchmark"
PACKAGE_DIR="${WORKSPACE_DIR}/package"
SCRIPT_DIR="${WORKSPACE_DIR}/script"
VM_DIR="${WORKSPACE_DIR}/vm"

SPEC_CPU_DIR="${BENCHMARK_DIR}/spec-cpu"
SPEC_CPU_EXE_DIR="${SPEC_CPU_DIR}/spec-cpu-2017"
SPEC_CONFIG_DIR="${BENCHMARK_DIR}/spec-config"
SPEC_ADDITION_DIR="${BENCHMARK_DIR}/spec-addition"
DHRYSTONE_DIR="${BENCHMARK_DIR}/dhrystone"
LMBENCH_DIR="${BENCHMARK_DIR}/lmbench"
STREAM_DIR="${BENCHMARK_DIR}/stream"
FIO_DIR="${BENCHMARK_DIR}/fio"
IPERF_DIR="${BENCHMARK_DIR}/iperf"
if [ "$MACHINE" == "ampere" ]; then
    SPEC_CONFIG_PREFIX="ampere-"
else
    SPEC_CONFIG_PREFIX="gcc-linux-${ARCH}-"
fi

SPEC_CPU_SCRIPT_DIR="${SCRIPT_DIR}/spec-cpu"
DHRYSTONE_SCRIPT_DIR="${SCRIPT_DIR}/dhrystone"
LMBENCH_SCRIPT_DIR="${SCRIPT_DIR}/lmbench"
STREAM_SCRIPT_DIR="${SCRIPT_DIR}/stream"
FIO_SCRIPT_DIR="${SCRIPT_DIR}/fio"
IPERF_SCRIPT_DIR="${SCRIPT_DIR}/iperf"

DATE=$(date +"%Y%m%d%H%M")