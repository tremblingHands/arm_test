#!/bin/bash
set -e

source ../vars.sh

PREPARE_ENV=${1:-"host"}

SOURCE_DIR="${PACKAGE_DIR}/source"
RPM_DIR="${PACKAGE_DIR}/rpm"
PYTHON_DIR="${PACKAGE_DIR}/python"

RPM_BASE_OS_DIR="${RPM_DIR}/BaseOS"
RPM_APP_STREAM_DIR="${RPM_DIR}/AppStream"
RPM_KERNEL_DIR="${RPM_DIR}/kernel"
QEMU_DEVEL_DIR="${RPM_DIR}/qemu-devel"

CMD_LINE_STR_1="iommu.passthrough=1"
CMD_LINE_STR_2="transparent_hugepage=never"
CMD_LINE_STR_3="default_hugepagesz=2M"
CMD_LINE_STR="${CMD_LINE_STR_1} ${CMD_LINE_STR_2} ${CMD_LINE_STR_3}"

if [ "${PREPARE_ENV}" == "guest" ]; then
    CMD_LINE_STR="${CMD_LINE_STR} ${ISOLATION_CPU_CMDLINE}"
fi

SSH_KEY_WORDS="password:"

NEED_REBOOT=
NEED_WARN=

function settle_workdir() {
    if [ -d "${VM_DIR}/${CHOOSE_DIR}" ]; then
        mv ${VM_DIR}/${CHOOSE_DIR}/* ${VM_DIR}
        rm -rf ${VM_DIR}/aarch64 ${VM_DIR}/x86_64
    fi

    if [ -d "${RPM_DIR}/${CHOOSE_DIR}" ]; then
        mv ${RPM_DIR}/${CHOOSE_DIR}/* ${RPM_DIR}
        rm -rf ${RPM_DIR}/aarch64 ${RPM_DIR}/x86_64
    fi

    if [ -d "${PYTHON_DIR}/${CHOOSE_DIR}" ]; then
        mv ${PYTHON_DIR}/${CHOOSE_DIR}/* ${PYTHON_DIR}
        rm -rf ${PYTHON_DIR}/aarch64 ${PYTHON_DIR}/x86_64
    fi
}

function prepare_yum_resource() {
    pushd "/etc/yum.repos.d" 1>/dev/null
    if [ ! -f "local.repo" ]; then
        cp "${RPM_DIR}/local.repo" ./
        sed -i "s|BASEOS_FILEPATH|${RPM_BASE_OS_DIR}|g" local.repo
        sed -i "s|APPSTREAM_FILEPATH|${RPM_APP_STREAM_DIR}|g" local.repo
    fi
    mkdir -p repoback
    local all_repo=$(ls | (grep -v "local.repo" || true) | (grep -v "repoback" || true))
    for file in $(ls); do
        if [ "$file" != "local.repo" ] && [ "$file" != "repoback" ]; then
            mv ${file} repoback/
        fi
    done
    popd 1>/dev/null
    yum clean all 1>/dev/null
    yum makecache 1>/dev/null

    yum install -y numactl python3 "${GCC_TOOLSET}" expect 1>/dev/null
    pip3 install ${PYTHON_DIR}/pip* 1>/dev/null
    pip3 install ${PYTHON_DIR}/numpy* 1>/dev/null
    source "/opt/rh/${GCC_TOOLSET}/enable"

    echo "prepare yum resource successfully"
}

function check_kernel_version() {
    if [ "$SKIP_KERNEL_VERSION_CHECK" == "1" ]; then
        echo "skip check kernel version"
        return
    fi

    local kernel_version=$(uname -r)
    if [ "$kernel_version" != "$KERNEL_VERSION" ]; then
        echo "kernel is not ${KERNEL_VERSION}, install it"
        yum install -y ${RPM_KERNEL_DIR}/* 1>/dev/null
        grubby --set-default="/boot/vmlinuz-${KERNEL_VERSION}"
        NEED_REBOOT=1
        echo "kernel ${KERNEL_VERSION} installed successfully"
    else
        echo "kernel version check passed"
    fi
}

function check_cmdline() {
    local origin_grub_cmdline=$(cat /etc/default/grub | (grep GRUB_CMDLINE_LINUX || true) | sed 's|"||g')
    origin_grub_cmdline=${origin_grub_cmdline#*=}
    if [ "${HOST_ORIGINAL_CMDLINE}" == "host_original_cmdline_empty" ]; then
        sed -i "s|host_original_cmdline_empty|${origin_grub_cmdline}|g" ${SCRIPT_DIR}/vars.sh
        source ${SCRIPT_DIR}/vars.sh
    fi

    local grub_cmdline="${HOST_ORIGINAL_CMDLINE} ${CMD_LINE_STR}"

    local os_cmdline=$(cat /proc/cmdline | (grep "${CMD_LINE_STR}$" || true))

    if [ "$origin_grub_cmdline" != "$grub_cmdline" ]; then
        echo "/etc/default/grub needs update"
        sed "s|${origin_grub_cmdline}|${grub_cmdline}|g" -i /etc/default/grub
        grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg 1>/dev/null
        NEED_REBOOT=1
        echo "update /etc/default/grub successfully"
    fi

    if [ "$os_cmdline" != "" ]; then
        local iommu=$(dmesg | grep "Default domain type" | awk '{print $7}')
        local transparent_hugepage=$(cat /proc/meminfo | grep AnonHugePages | awk '{print $2}')
        local hugepage_size=$(cat /proc/meminfo | grep Hugepagesize | awk '{print $2}')
        if [ "$iommu" != "Passthrough" ]; then
            NEED_WARN=1
            echo "!!!!!! iommu is not in Passthrough mode"
        elif [ "$transparent_hugepage" != "0" ]; then
            NEED_WARN=1
            echo "!!!!!! AnonHugePages is not 0 kB"
        elif [ "$hugepage_size" == "" ]; then
            NEED_WARN=1
            echo "!!!!!! Hugepagesize is not 2048 kB"
        else
            echo "current os cmdline check passed"
        fi
    else
        NEED_REBOOT=1
        echo "need reboot to update os cmdline"
    fi
}

function check_SELinux() {
    local selinux_state=$(cat /etc/selinux/config | (grep "^SELINUX=" || true))
    selinux_state=${selinux_state#*SELINUX=}
    if [ "$selinux_state" != "disabled" ]; then
        sed -i "s|=${selinux_state}|=disabled|g" /etc/selinux/config
        NEED_REBOOT=1
        echo "SELinux disabled successfully"
    else
        echo "SELinux check passed"
    fi
}

function check_service() {
    local service_enabled=$(systemctl is-enabled irqbalance.service || true)
    local service_status=$(systemctl status irqbalance.service | grep Active | awk '{print $2}')
    if [ "$service_enabled" != "disabled" ]; then
        systemctl disable irqbalance.service
        NEED_REBOOT=1
        echo "disable service irqbalance successfully"
    elif [ "$service_status" == "active" ]; then
        systemctl stop irqbalance.service
        NEED_REBOOT=1
        echo "stop service irqbalance successfully"
    else
        echo "service irqbalance check passed"
    fi

    service_enabled=$(systemctl is-enabled firewalld.service || true)
    service_status=$(systemctl status firewalld.service | grep Active | awk '{print $2}')
    if [ "$service_enabled" != "disabled" ]; then
        systemctl disable firewalld.service
        NEED_REBOOT=1
        echo "disable service firewalld successfully"
    elif [ "$service_status" == "active" ]; then
        systemctl stop firewalld.service
        NEED_REBOOT=1
        echo "stop service firewalld successfully"
    else
        echo "service firewalld check passed"
    fi

    local docker_service=$(systemctl list-unit-files | (grep docker.service || true))
    if [ "$docker_service" != "" ]; then
        service_enabled=$(echo ${docker_service} | awk '{print $2}')
        service_status=$(systemctl status docker.service | grep Active | awk '{print $2}')
        if [ "$service_enabled" != "disabled" ]; then
            systemctl disable docker.service
            NEED_REBOOT=1
            echo "disable service docker successfully"
        elif [ "$service_status" == "active" ]; then
            systemctl stop docker.service
            NEED_REBOOT=1
            echo "stop service docker successfully"
        else
            echo "service docker check passed"
        fi
    else
        echo "service docker check passed"
    fi
}

function install_qemu() {
    yum remove -y qemu-kvm* 1>/dev/null 2>&1
    yum install -y libzstd-devel libcap-ng-devel glib2-devel pixman-devel zlib-devel bzip2 python3 libaio-devel numactl-devel 1>/dev/null
    yum install -y ${QEMU_DEVEL_DIR}/* 1>/dev/null

    tar -Jvxf ${SOURCE_DIR}/qemu-${QEMU_VERSION}.tar.xz -C ${WORKSPACE_DIR} 1>/dev/null
    pushd "${WORKSPACE_DIR}/qemu-${QEMU_VERSION}" 1>/dev/null
    ./configure --prefix="${QEMU_INSTALL_DIR}" --target-list="${ARCH}"-softmmu --enable-tcg --enable-modules --enable-linux-aio --enable-fdt \
        --enable-debug --enable-kvm --enable-zstd --enable-pie --enable-numa --enable-cap-ng --enable-vhost-user --enable-vhost-net --enable-vhost-kernel \
        --enable-vhost-user-blk-server --enable-vhost-vdpa --disable-slirp --disable-slirp-smbd --disable-rbd --disable-dmg --disable-qcow1 --disable-vdi \
        --disable-vvfat --disable-qed --disable-parallels --disable-capstone --disable-smartcard --disable-brlapi --disable-plugins --disable-gtk \
        --disable-libnfs --disable-bzip2 --disable-docs --disable-guest-agent --disable-mpath --disable-rdma --disable-linux-io-uring --disable-tpm \
        --disable-libssh --disable-virglrenderer --disable-libusb 1>/dev/null
    make -j 120 1>/dev/null
    make install 1>/dev/null
    ln -s ${QEMU_INSTALL_DIR}/bin/qemu-system-${ARCH} /usr/libexec/qemu-kvm
    popd 1>/dev/null

    rm -rf ${WORKSPACE_DIR}/qemu-${QEMU_VERSION}
}

function check_qemu() {
    if [ -f "/usr/libexec/qemu-kvm" ] && [ -L "/usr/libexec/qemu-kvm" ]; then
        echo "qemu check passed"
    else
        install_qemu
        echo "install qemu successfully"
    fi
}

function check_libvirt() {
    systemctl daemon-reload
    local libvirtd_unit=$(systemctl list-unit-files | (grep libvirtd || true))
    if [ "$libvirtd_unit" != "" ]; then
        systemctl restart libvirtd
        if [ -f "/usr/bin/virsh" ]; then
            local libvirtd_qemu_driver=$(virsh version | (grep QEMU || true))
            if [ "$libvirtd_qemu_driver" != "" ]; then
                echo "libvirt check passed"
                return
            fi
        fi
    fi
    yum install -y libvirt 1>/dev/null
    sed -i 's/#user/user/g' /etc/libvirt/qemu.conf
    sed -i 's/#group/group/g' /etc/libvirt/qemu.conf
    systemctl daemon-reload
    systemctl restart libvirtd
    echo "install libvirt successfully"
}

function install_spec_cpu() {
    local host_spec_config_submit=
    local guest_spec_config_submit="numactl --membind=0 --physcpubind=\$SPECCOPYNUM \$command"

    if [ "$VM_CPU_LIST_SECOND_START" != "none" ]; then
        host_spec_config_submit="[ \`expr \$SPECCOPYNUM % 2\` == 0 ] && numactl --membind=${VM_MEM_NUMA_NODE} --physcpubind=\`expr ${VM_CPU_LIST_FIRST_START} + \$SPECCOPYNUM / 2\` \$command  \|\| numactl --membind=${VM_MEM_NUMA_NODE} --physcpubind=\`expr ${VM_CPU_LIST_SECOND_START} + \$SPECCOPYNUM / 2\` \$command"
    else
        host_spec_config_submit="numactl --membind=${VM_MEM_NUMA_NODE} --physcpubind=\`expr ${VM_CPU_LIST_FIRST_START} + \$SPECCOPYNUM\` \$command"
    fi

    mkdir -p /mnt/spec-cpu-2017
    rm -rf ${SPEC_CPU_EXE_DIR}
    mkdir -p ${SPEC_CPU_EXE_DIR}
    mount -t iso9660 -o exec,loop ${SOURCE_DIR}/cpu2017-1.1.8.iso /mnt/spec-cpu-2017 1>/dev/null
    pushd "/mnt/spec-cpu-2017" 1>/dev/null
    ./install.sh -d ${SPEC_CPU_EXE_DIR} -f 1>/dev/null
    popd 1>/dev/null
    umount /mnt/spec-cpu-2017
    pushd "${SPEC_CPU_EXE_DIR}" 1>/dev/null
    cp ${SPEC_CONFIG_DIR}/${SPEC_CONFIG_PREFIX}-host.cfg config/

    if [ "${MACHINE}" == "ampere" ]; then
        cp ${SPEC_ADDITION_DIR}/ampere/flags/* config/flags/
        cp -R ${SPEC_ADDITION_DIR}/ampere/lib ./
        ln -s ${SPEC_CPU_EXE_DIR}/lib/libjemalloc.so.2 lib/libjemalloc.so
        sed -i "s|#SPEC_CPU_EXE_DIR#|${SPEC_CPU_EXE_DIR}|g" config/${SPEC_CONFIG_PREFIX}-host.cfg
    fi

    sed -i "s|#SUBMIT#|${host_spec_config_submit}|g" config/${SPEC_CONFIG_PREFIX}-host.cfg
    sed -i "s|#GCC_TOOLSET#|${GCC_TOOLSET}|g" config/${SPEC_CONFIG_PREFIX}-host.cfg
    yum install -y libnsl 1>/dev/null
    source shrc 1>/dev/null
    runcpu --config=${SPEC_CONFIG_PREFIX}-host.cfg --action=build --rebuild --tune=base intrate 1>/dev/null
    cp config/${SPEC_CONFIG_PREFIX}-host.cfg config/${SPEC_CONFIG_PREFIX}-guest.cfg
    sed -i "s|${host_spec_config_submit}|${guest_spec_config_submit}|g" config/${SPEC_CONFIG_PREFIX}-guest.cfg
    popd 1>/dev/null
}

function install_fio() {
    yum remove -y fio 1>/dev/null
    yum install -y nvme-cli numactl-devel libaio libaio-devel python3 1>/dev/null

    tar -zvxf ${SOURCE_DIR}/fio-${FIO_VERSION}.tar.gz -C ${FIO_DIR} 1>/dev/null
    pushd "${FIO_DIR}/fio-fio-${FIO_VERSION}" 1>/dev/null
    ./configure --prefix="${FIO_DIR}" 1>/dev/null
    make -j 128 1>/dev/null
    make install 1>/dev/null
    popd 1>/dev/null

    rm -rf ${FIO_DIR}/fio-fio-${FIO_VERSION}
}

function install_dhrystone() {
    tar -zvxf ${SOURCE_DIR}/dhrystone-master.tar.gz -C ${DHRYSTONE_DIR} 1>/dev/null
    pushd "${DHRYSTONE_DIR}/dhrystone-master" 1>/dev/null
    gcc -O3 -o ${DHRYSTONE_BIN} dhry21a.c dhry21b.c timers.c 1>/dev/null
    popd 1>/dev/null

    rm -rf ${DHRYSTONE_DIR}/dhrystone-master
}

function check_benchmark() {
    if [ -d "${SPEC_CPU_EXE_DIR}/benchspec/CPU/500.perlbench_r/exe" ]; then
        echo "benchmark SPEC_CPU_2017 already installed"
    else
        install_spec_cpu
        echo "install benchmark SPEC_CPU_2017 successfully"
    fi

    if [ -f "${FIO_BIN}" ]; then
        local fio_exist=$(${FIO_BIN} --version | (grep "${FIO_VERSION}" || true))
        if [ "$fio_exist" != "" ]; then
            echo "benchmark FIO already installed"
        fi
    else
        install_fio
        echo "install benchmark FIO successfully"
    fi

    if [ -f "${DHRYSTONE_BIN}" ]; then
        echo "benchmark Dhrystone already installed"
    else
        install_dhrystone
        echo "install benchmark Dhrystone successfully"
    fi
}

function check_page_size() {
    local page_size=$(getconf PAGESIZE)
    if [ "$page_size" != "4096" ]; then
        NEED_WARN=1
        echo "!!!!!! page size is not 4KB"
    else
        echo "page size check passed"
    fi
}

function check_numa_profile() {
    local numa_node_num=$(numactl -H | (grep available || true) | awk '{print $2}')
    if [ "$numa_node_num" != "$SOCKET_NUM" ]; then
        NEED_WARN=1
        echo "!!!!!! numa profile is not NPS1"
    else
        echo "numa profile check passed"
    fi
}

function check_thread_profile() {
    if [ "$ARCH" == "x86_64" ]; then
        local thread_num=$(lscpu | (grep Thread || true) | awk '{print $4}')
        if [ "$thread_num" != "2" ]; then
            NEED_WARN=1
            echo "!!!!!! hyper thread is disabled"
        else
            echo "x86_64 thread check passed"
        fi
    fi
}

function check_virt_profile() {
    if [ ! -e "/dev/kvm" ]; then
        NEED_WARN=1
        echo "!!!!!! kvm模块不可用, /dev/kvm文件不存在"
    elif [ ! -d "/sys/module/kvm" ]; then
        NEED_WARN=1
        echo "!!!!!! kvm模块不可用, /sys/module/kvm目录不存在"
    else
        echo "virt profile check passed"
    fi
}

function generate_vm_cpu_list() {
    local cpu_str=$(lscpu | grep "NUMA node${VM_MEM_NUMA_NODE} CPU(s)" | awk '{print $4}')
    local all_cpu_num=$(lscpu | grep "^CPU(s)" | awk '{print $2}')
    python3 help.py "${cpu_str}" ${VM_CPU_START_INDEX} ${VM_CPU_NUM} ${all_cpu_num} ${TEST_BIND_CPU_START_INDEX}

    source ${SCRIPT_DIR}/vars.sh

    echo "generate vm cpu list successfully"
}

function generate_device_profile() {
    local domain=$(echo $1 | awk -F ':' '{print $1}')
    local bus=$(echo $1 | awk -F ':' '{print $2}')
    local slot_fuction_num=$(echo $1 | awk -F ':' '{print $3}')
    local slot=$(echo $slot_fuction_num | awk -F '.' '{print $1}')
    local fuction=$(echo $slot_fuction_num | awk -F '.' '{print $2}')
    device_profile=$(cat ${VM_ORIGIN_DEVICE_PROFILE} | sed "s|#DOMAIN#|$domain|g" | sed "s|#BUS#|$bus|g" | sed "s|#SLOT#|$slot|g" | sed "s|#FUNCTION#|$fuction|g")
}

function create_basic_vm_profile() {
    local down_arch=""
    local machine=""
    local feature=""
    local os_image="${VM_DIR}/${CENTOS_VERSION}.img"

    if [ "$ARCH" == "x86_64" ]; then
        down_arch="i386"
        machine="pc"
    elif [ "$ARCH" == "aarch64" ]; then
        down_arch="arm"
        machine="virt"
        feature='    <gic version="3"/>'
    fi

    sed -i "s|#VMNAME#|${VM_NAME}|g" ${VM_ORIGIN_PROFILE}
    sed -i "s|#MEMNUMANODE#|${VM_MEM_NUMA_NODE}|g" ${VM_ORIGIN_PROFILE}
    sed -i "s|#ARCH#|${ARCH}|g" ${VM_ORIGIN_PROFILE}
    sed -i "s|#MACHINE#|${machine}|g" ${VM_ORIGIN_PROFILE}
    sed -i "s|#DOWNARCH#|${down_arch}|g" ${VM_ORIGIN_PROFILE}
    sed -i "s|#FEATURE#|${feature}|g" ${VM_ORIGIN_PROFILE}
    sed -i "s|#OSIMAGE#|${os_image}|g" ${VM_ORIGIN_PROFILE}

    local disk=""
    if [ "$VM_DISK" != "" ]; then
        local disk_pci=$(ls -l /sys/block/${VM_DISK}/device/device | awk '{print $11}' | awk -F '/' '{print $4}')
        generate_device_profile "${disk_pci}"
        disk=${device_profile}
    fi
    sed -i "s|#DISK#|${disk}|g" ${VM_ORIGIN_PROFILE}

    local nic=""
    if [ "$VM_DISK" != "" ]; then
        local nic_pci=$(ethtool -i ${VM_NIC} | grep "bus-info" | awk '{print $2}')
        generate_device_profile "${nic_pci}"
        nic=${device_profile}
    fi
    sed -i "s|#NIC#|${nic}|g" ${VM_ORIGIN_PROFILE}

    mv ${VM_ORIGIN_PROFILE} ${VM_BASIC_PROFILE}

    echo "create basic vm profile successfully"
}

function create_vm() {
    cp ${VM_BASIC_PROFILE} ${VM_PROFILE}

    sed -i "s|#MEMORYSIZE#|${VM_MEM_SIZE}|g" ${VM_PROFILE}
    sed -i "s|#CPUNUM#|${VM_CPU_NUM}|g" ${VM_PROFILE}
    sed -i "s|#EMUPINCPU#|${VM_EMU_PIN_CPU}|g" ${VM_PROFILE}
    sed -i "s|#IOPINCPU#|${VM_IO_PIN_CPU}|g" ${VM_PROFILE}
    sed -i "s|#CPUTUNE#|${VM_CPU_TUNE}|g" ${VM_PROFILE}

    virsh define ${VM_PROFILE} 1>/dev/null
    echo "create ${VM_NAME} successfully"
}

function start_vm() {
    local vm_state=$(virsh dominfo ${VM_NAME} 2>/dev/null | (grep State || true) | awk '{print $2}')
    if [ "$vm_state" != "running" ]; then
        numactl -m 0 echo ${HUGE_PAGE_NUM} >/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages_mempolicy
        virsh start ${VM_NAME} 1>/dev/null
    fi

    echo "start ${VM_NAME} successfully, now wait 30s for vm initialization"
    sleep 30
}

function stop_vm() {
    local vm_state=$(virsh dominfo ${VM_NAME} 2>/dev/null | (grep State || true) | awk '{print $2}')
    if [ "$vm_state" == "running" ]; then
        virsh shutdown ${VM_NAME} 1>/dev/null
        numactl -m 0 echo 0 >/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages_mempolicy
    fi

    echo "stop ${VM_NAME} successfully"
}

function prepare_benchmark_for_vm() {
    start_vm

    if [ "$GUEST_IP" == "guest_ip_empty" ]; then
        local guest_ip=$(virsh domifaddr ${VM_NAME} | grep "192" | awk '{print $4}' | cut -f 1 -d "/")
        if [ "$guest_ip" == "" ]; then
            echo "!!!!!!${VM_NAME} ip is empty"
            exit 1
        fi
        sed -i "s|guest_ip_empty|${guest_ip}|g" ${SCRIPT_DIR}/vars.sh
        GUEST_IP=${guest_ip}
    fi

    local raw_command="scp -o "StrictHostKeyChecking=no" -r ${BENCHMARK_DIR} root@${GUEST_IP}:${WORKSPACE_DIR}"
    interact_call "${raw_command}" "${SSH_KEY_WORDS}" "${VM_PASSWORD}" 1>/dev/null

    raw_command="scp -o "StrictHostKeyChecking=no" -r ${SCRIPT_DIR} root@${GUEST_IP}:${WORKSPACE_DIR}"
    interact_call "${raw_command}" "${SSH_KEY_WORDS}" "${VM_PASSWORD}" 1>/dev/null

    raw_command="scp -o "StrictHostKeyChecking=no" -r ${RUN_DIR} root@${GUEST_IP}:${WORKSPACE_DIR}"
    interact_call "${raw_command}" "${SSH_KEY_WORDS}" "${VM_PASSWORD}" 1>/dev/null

    sed -i "s|vm_state_ready_false|vm_state_ready_true|g" ${SCRIPT_DIR}/vars.sh

    echo "prepare benchmark for ${VM_NAME} successfully"
}

function env_check_and_build() {
    settle_workdir
    if [ "$SKIP_PREPARE_YUM_RESOURCE" == "1" ]; then
        echo "skip prepare yum resource"
    else
        prepare_yum_resource
    fi

    check_kernel_version
    check_cmdline
    check_SELinux
    check_service

    check_qemu
    check_libvirt

    check_page_size
    check_numa_profile
    check_thread_profile
    check_virt_profile

    if [ "$NEED_REBOOT" == "1" ]; then
        echo "Notice: someting need reboot"
        exit 1
    fi

    if [ "$NEED_WARN" == "1" ]; then
        echo "Notice: someting need manual handling"
        exit 1
    fi

    if [ "$NEED_CPUPOWER_OPS" == "1" ]; then
        cpupower frequency-set -g performance
        echo "cpupower mode updated successfully"
    fi

    if [ ! -f "${PREPARE_SCRIPT_DIR}/vm-cpu-list" ]; then
        generate_vm_cpu_list
    else
        echo "vm cpu list was already generated"
    fi

    check_benchmark

    if [ ! -f "${VM_BASIC_PROFILE}" ]; then
        create_basic_vm_profile
    else
        echo "basic vm profile was already created"
    fi

    local test_vm_state=$(virsh dominfo ${VM_NAME} 2>/dev/null | (grep State || true) | awk '{print $2}')
    if [ "$test_vm_state" == "" ]; then
        create_vm
    else
        echo "${VM_NAME} already created"
    fi

    if [ "${VM_STATE_READY}" == "vm_state_ready_false" ]; then
        prepare_benchmark_for_vm
    else
        echo "benchmark of ${VM_NAME} has been ready"
    fi

    if [ "${PREPARE_ENV}" == "host" ]; then
        stop_vm
    elif [ "${PREPARE_ENV}" == "guest" ]; then
        start_vm
    fi

    echo "prepare env for ${PREPARE_ENV} successfully"
}

env_check_and_build
