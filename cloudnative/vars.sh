#!/bin/bash
set -e

SKIP_KERNEL_VERSION_CHECK=0
SKIP_PREPARE_YUM_RESOURCE=0
MACHINE=""
SOCKET_NUM=2
NEED_CPUPOWER_OPS=0

QEMU_VERSION="7.1.0"
QEMU_INSTALL_DIR="/usr/local/qemu"
FIO_VERSION="3.36"

TEST_BIND_CPU_START_INDEX=8

VM_NAME="testVM"
VM_CPU_NUM=32
VM_CPU_START_INDEX=8
VM_MEM_SIZE=64
VM_MEM_NUMA_NODE=0
VM_DISK=""
VM_NIC=""
VM_PASSWORD="123456"
HUGE_PAGE_NUM=38400
HOST_IP=""
GUEST_IP="guest_ip_empty"

DHRYSTONE_ARG_RUN_TIMES=1000000000

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

WORKSPACE_DIR="/home/virt-test"
BENCHMARK_DIR="${WORKSPACE_DIR}/benchmark"
PACKAGE_DIR="${WORKSPACE_DIR}/package"
SCRIPT_DIR="${WORKSPACE_DIR}/script"
VM_DIR="${WORKSPACE_DIR}/vm"
RUN_DIR="${WORKSPACE_DIR}/run"

SPEC_CPU_DIR="${BENCHMARK_DIR}/spec-cpu"
SPEC_CPU_EXE_DIR="${SPEC_CPU_DIR}/spec-cpu-2017"
SPEC_CONFIG_DIR="${SPEC_CPU_DIR}/config"
SPEC_ADDITION_DIR="${SPEC_CPU_DIR}/addition"
DHRYSTONE_DIR="${BENCHMARK_DIR}/dhrystone"
LMBENCH_DIR="${BENCHMARK_DIR}/lmbench"
STREAM_DIR="${BENCHMARK_DIR}/stream"
FIO_DIR="${BENCHMARK_DIR}/fio"
IPERF_DIR="${BENCHMARK_DIR}/iperf"
if [ "$MACHINE" == "ampere" ]; then
    SPEC_CONFIG_PREFIX="ampere"
else
    SPEC_CONFIG_PREFIX="gcc-linux-${ARCH}"
fi

PREPARE_SCRIPT_DIR="${SCRIPT_DIR}/prepare"
SPEC_CPU_SCRIPT_DIR="${SCRIPT_DIR}/spec-cpu"
DHRYSTONE_SCRIPT_DIR="${SCRIPT_DIR}/dhrystone"
LMBENCH_SCRIPT_DIR="${SCRIPT_DIR}/lmbench"
STREAM_SCRIPT_DIR="${SCRIPT_DIR}/stream"
FIO_SCRIPT_DIR="${SCRIPT_DIR}/fio"
IPERF_SCRIPT_DIR="${SCRIPT_DIR}/iperf"

SPEC_CPU_RUN_DIR="${RUN_DIR}/spec-cpu"
DHRYSTONE_RUN_DIR="${RUN_DIR}/dhrystone"
LMBENCH_RUN_DIR="${RUN_DIR}/lmbench"
STREAM_RUN_DIR="${RUN_DIR}/stream"
FIO_RUN_DIR="${RUN_DIR}/fio"
IPERF_RUN_DIR="${RUN_DIR}/iperf"

VM_ORIGIN_PROFILE="${VM_DIR}/vm.xml"
VM_ORIGIN_DEVICE_PROFILE="${VM_DIR}/device.xml"
VM_BASIC_PROFILE="${VM_DIR}/basic-vm.xml"
VM_PROFILE="${VM_DIR}/${CENTOS_VERSION}.xml"

DHRYSTONE_BIN="${DHRYSTONE_DIR}/dhrystone_O3_${ARCH}"
FIO_BIN="${FIO_DIR}/bin/fio"

VM_STATE_READY="vm_state_ready_false"

HOST_ORIGINAL_CMDLINE="host_original_cmdline_empty"

if [ -f "${PREPARE_SCRIPT_DIR}/vm-cpu-list" ]; then
    source ${PREPARE_SCRIPT_DIR}/vm-cpu-list
fi

DATE=$(date +"%Y%m%d%H%M")

function interact_call() {
    local raw_command=$1
    local key_words=$2
    local send_command=$3
    /usr/bin/expect <<-EOF
    set timeout 120
    spawn ${raw_command}
    expect "${key_words}"
    send "${send_command}\n"
    expect eof
EOF
}
