#!/bin/bash
set -e

source ../vars.sh

SOURCE_DIR="${PACKAGE_DIR}/source"
RPM_DIR="${PACKAGE_DIR}/rpm"

RPM_BASE_OS_DIR="${RPM_DIR}/BaseOS"
RPM_APP_STREAM_DIR="${RPM_DIR}/AppStream"
RPM_KERNEL_DIR="${RPM_DIR}/kernel"
QEMU_DEVEL_DIR="${RPM_DIR}/qemu-devel"

CMD_LINE_STR_1="iommu.passthrough=1"
CMD_LINE_STR_2="transparent_hugepage=never"
CMD_LINE_STR_3="default_hugepagesz=2M"
CMD_LINE_STR="${CMD_LINE_STR_1} ${CMD_LINE_STR_2} ${CMD_LINE_STR_3}"

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
}

function prepare_yum_resource() {
    pushd "/etc/yum.repos.d"
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
    popd
    yum clean all
    yum makecache

    yum install -y numactl
    yum install -y python3
    yum install -y "${GCC_TOOLSET}"
    source "/opt/rh/${GCC_TOOLSET}/enable"
}

function check_kernel_version() {
    local kernel_version=$(uname -r)
    if [ "$kernel_version" != "$KERNEL_VERSION" ]; then
        echo "kernel is not ${KERNEL_VERSION}, install it"
        yum install --disablerepo=* -y "${RPM_KERNEL_DIR}/*"
        grubby --set-default="/boot/vmlinuz-${KERNEL_VERSION}"
        NEED_REBOOT="1"
        echo "kernel ${KERNEL_VERSION} installed successfully"
    else
        echo "kernel version check passed"
    fi
}

function check_cmdline() {
    local os_cmdline=$(cat /proc/cmdline | (grep "${CMD_LINE_STR}" || true))
    if [ "$os_cmdline" == "" ]; then
        echo "os cmdline needs update"
        local grub_cmdline=$(cat /etc/default/grub | (grep GRUB_CMDLINE_LINUX || true) | sed 's|"||g')
        origin_grub_cmdline=${grub_cmdline#*=}
        grub_cmdline=${grub_cmdline#*=}
        local str1=$(echo ${grub_cmdline} | (grep "${CMD_LINE_STR_1}" || true))
        local str2=$(echo ${grub_cmdline} | (grep "${CMD_LINE_STR_2}" || true))
        local str3=$(echo ${grub_cmdline} | (grep "${CMD_LINE_STR_3}" || true))
        if [ "$str1" == "" ]; then
            grub_cmdline="${grub_cmdline} ${CMD_LINE_STR_1}"
        fi
        if [ "$str2" == "" ]; then
            grub_cmdline="${grub_cmdline} ${CMD_LINE_STR_2}"
        fi
        if [ "$str3" == "" ]; then
            grub_cmdline="${grub_cmdline} ${CMD_LINE_STR_3}"
        fi
        sed "s|${origin_grub_cmdline}|${grub_cmdline}|g" -i /etc/default/grub
        grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
        NEED_REBOOT=1
        echo "os cmdline updated successfully"
    else
        local iommu=$(dmesg | grep "Default domain type" | awk '{print $7}')
        local transparent_hugepage=$(cat /proc/meminfo | grep AnonHugePages | awk '{print $2}')
        local hugepage_size=$(cat /proc/meminfo | grep Hugepagesize | awk '{print $2}')
        if [ "$iommu" != "Passthrough" ]; then
            echo "!!!!!! iommu is not in Passthrough mode"
        elif [ "$transparent_hugepage" != "0" ]; then
            echo "!!!!!! AnonHugePages is not 0 kB"
        elif [ "$hugepage_size" == "" ]; then
            echo "!!!!!! Hugepagesize is not 2048 kB"
        else
            echo "os cmdline check passed"
        fi
    fi
}

function check_SELinux() {
    local selinux_state=$(cat /etc/selinux/config | (grep "^SELINUX=" || true))
    selinux_state=${selinux_state#*SELINUX=}
    if [ "$selinux_state" != "disabled" ]; then
        sed -i "s|=${selinux_state}|=disabled|g" /etc/selinux/config
        echo "SELinux disabled successfully"
    else
        echo "SELinux check passed"
    fi
}

function check_service() {
    local is_enabled=$(systemctl is-enabled irqbalance.service)
    if [ "$is_enabled" != "disabled" ]; then
        systemctl disable irqbalance.service
        echo "service irqbalance disabled successfully"
        NEED_REBOOT=1
    else
        echo "service irqbalance check passed"
    fi

    local is_enabled=$(systemctl is-enabled firewalld.service)
    if [ "$is_enabled" != "disabled" ]; then
        systemctl disable firewalld.service
        echo "service firewalld disabled successfully"
        NEED_REBOOT=1
    else
        echo "service firewalld check passed"
    fi
}

function install_qemu() {
    yum remove -y qemu-kvm*
    yum install libzstd-devel libcap-ng-devel glib2-devel libfdt-devel pixman-devel zlib-devel bzip2 python3 libaio-devel numactl-devel -y

    tar -Jvxf ${SOURCE_DIR}/qemu-${QEMU_VERSION}.tar.xz -C ${WORKSPACE_DIR}
    pushd "${WORKSPACE_DIR}/qemu-${QEMU_VERSION}"
    ./configure --prefix="${QEMU_DIR}" --target-list="${ARCH}"-softmmu --enable-tcg --enable-modules --enable-linux-aio --enable-fdt \
        --enable-debug --enable-kvm --enable-zstd --enable-pie --enable-numa --enable-cap-ng --enable-vhost-user --enable-vhost-net --enable-vhost-kernel \
        --enable-vhost-user-blk-server --enable-vhost-vdpa --disable-slirp --disable-slirp-smbd --disable-rbd --disable-dmg --disable-qcow1 --disable-vdi \
        --disable-vvfat --disable-qed --disable-parallels --disable-capstone --disable-smartcard --disable-brlapi --disable-plugins --disable-gtk \
        --disable-libnfs --disable-bzip2 --disable-docs --disable-guest-agent --disable-mpath --disable-rdma --disable-linux-io-uring --disable-tpm \
        --disable-libssh --disable-virglrenderer --disable-libusb
    make -j 120
    make install
    ln -s ${QEMU_DIR}/bin/qemu-system-${ARCH} /usr/libexec/qemu-kvm
    popd
}

function check_qemu() {
    if [ -f "/usr/libexec/qemu-kvm" ] && [ -L "/usr/libexec/qemu-kvm" ]; then
        echo "qemu check passed"
    else
        install_qemu
        echo "qemu installed successfully"
    fi
}

function check_libvirt() {
    systemctl daemon-reload
    local libvirtd_unit=$(systemctl list-unit-files | (grep libvirtd || true))
    if [ "$libvirtd_unit" != "" ]; then
        if [ -f "/usr/bin/virsh" ]; then
            local libvirtd_qemu_driver=$(virsh version | (grep QEMU || true))
            if [ "$libvirtd_qemu_driver" != "" ]; then
                echo "libvirt check passed"
                return
            fi
        fi
    fi
    yum install -y libvirt
    sed -i 's/#user/user/g' /etc/libvirt/qemu.conf
    sed -i 's/#group/group/g' /etc/libvirt/qemu.conf
    echo "libvirt installed successfully"
}

function install_spec_cpu() {
    local host_spec_config_submit=
    local guest_spec_config_submit='numactl --membind=0 --physcpubind=$SPECCOPYNUM'

    if [ "$ARCH" == "x86_64" ]; then
        host_spec_config_submit="[ \`expr $SPECCOPYNUM % 2\` == 0 ] && numactl --membind=${VM_MEM_NUMA_NODE} --physcpubind=\`expr 8 + \$SPECCOPYNUM / 2\` \$command  || numactl --membind=${VM_MEM_NUMA_NODE} --physcpubind=\`expr 136 + \$SPECCOPYNUM / 2\` \$command"
    else
        host_spec_config_submit=
    fi

    mkdir -p /mnt/spec-cpu-2017
    rm -rf ${SPEC_CPU_EXE_DIR}
    mkdir -p ${SPEC_CPU_EXE_DIR}
    mount -t iso9660 -o exec,loop ${SOURCE_DIR}/cpu2017-1.1.8.iso /mnt/spec-cpu-2017
    pushd "/mnt/spec-cpu-2017"
    ./install.sh -d ${SPEC_CPU_EXE_DIR} -f
    cp ${SPEC_CONFIG_DIR}/${SPEC_CONFIG_PREFIX}-host.cfg ${SPEC_CPU_EXE_DIR}/config/
    if [ "${MACHINE}" == "ampere" ]; then
        cp ${SPEC_ADDITION_DIR}/ampere/flags/* ${SPEC_CPU_EXE_DIR}/config/flags/
        cp -R ${SPEC_ADDITION_DIR}/ampere/lib ${SPEC_CPU_EXE_DIR}/
        ln -s ${SPEC_CPU_EXE_DIR}/lib/libjemalloc.so.2 ${SPEC_CPU_EXE_DIR}/lib/libjemalloc.so
    fi
    popd
    pushd "${SPEC_CPU_EXE_DIR}"
    #SUBMIT#
    sed -i "s|#GCC_TOOLSET#|${GCC_TOOLSET}|g" ${SPEC_CPU_EXE_DIR}/config/${SPEC_CONFIG_PREFIX}-host.cfg
    source shrc
    runcpu --config=${SPEC_CONFIG_PREFIX}-host.cfg --action=build --rebuild --tune=base intrate 1>"${SPEC_CPU_LOG_DIR}/build.log" 2>&1
    cp config/${SPEC_CONFIG_PREFIX}-host.cfg config/${SPEC_CONFIG_PREFIX}-guest.cfg
    #更新guest config
    popd
}

function install_fio() {
    yum remove -y fio
    # 安装python包numpy
    tar -zvxf ${SOURCE_DIR}/fio-${FIO_VERSION}.tar.gz -C ${FIO_DIR}
    pushd "${FIO_DIR}/fio-fio-${FIO_VERSION}"
    ./configure
    make -j 128
    make install
    popd

}

function check_benchmark() {
    if [ -d "${SPEC_CPU_DIR}/benchspec/CPU/500.perlbench_r/exe" ]; then
        echo "benchmark SPEC_CPU_2017 check passed"
    else
        install_spec_cpu
    fi

    if [ -f "/usr/local/fio/bin/fio" ]; then
        local fio_exist=$(fio --version | (grep "${FIO_VERSION}" || true))
        if [ "$fio_exist" != "" ]; then
            echo "benchmark FIO check passed"
        fi
    else
        install_fio
    fi
}

function check_numa_profile() {
    local numa_node_num=$(numactl -H | (grep available || true) | awk '{print $2}')
    if [ "$numa_node_num" != "$SOCKET_NUM" ]; then
        echo "!!!!!! numa profile is not NPS1"
    else
        echo "numa profile check passed"
    fi
}

function check_thread_profile() {
    if [ "$ARCH" == "x86_64" ]; then
        local thread_num=$(lscpu | (grep Thread || true) | awk '{print $4}')
        if [ "$thread_num" != "2" ]; then
            echo "!!!!!! hyper thread is disabled"
        else
            echo "x86_64 thread check passed"
        fi
    fi
}

function check_virt_profile() {
    if [ ! -e "/dev/kvm" ]; then
        echo "!!!!!! kvm模块不可用，/dev/kvm文件不存在"
    elif [ ! -d "/sys/module/kvm" ]; then
        echo "!!!!!! kvm模块不可用，/sys/module/kvm目录不存在"
    else
        echo "virt profile check passed"
    fi
}

function generate_vm_cpu_list() {
    local cpu_str=$(numactl -H | grep "^NUMA node${VM_MEM_NUMA_NODE} CPU(s)" | awk '{print $2}')
    local all_cpu_num=$(lscpu | grep "^CPU(s)" | awk '{print $2}') 
    local help_output=$(python3 help.py "${cpu_str}" ${VM_CPU_START_INDEX} ${VM_CPU_NUM} ${all_cpu_num})
    VM_CPU_LIST_FIRST_START=$(echo $output | sed "s|#|\n|g" | grep "VM_CPU_LIST_FIRST_START" | awk '{print $2}')
    VM_CPU_LIST_SECOND_START=$(echo $output | sed "s|#|\n|g" | grep "VM_CPU_LIST_SECOND_START" | awk '{print $2}')
    VM_CPU_LIST=$(echo $output | sed "s|#|\n|g" | grep "VM_CPU_LIST" | awk '{print $2}')
    ISOLATION_CPU_CMDLINE=$(echo $output | sed "s|#|\n|g" | grep "ISOLATION_CPU_CMDLINE" | awk '{print $2}')
    sed -i "s|vm_cpu_list_first_start_empty|${VM_CPU_LIST_FIRST_START}|g" ${SCRIPT_DIR}/vars.sh
    sed -i "s|vm_cpu_list_second_start_empty|${VM_CPU_LIST_SECOND_START}|g" ${SCRIPT_DIR}/vars.sh
    sed -i "s|vm_cpu_list_empty|${VM_CPU_LIST}|g" ${SCRIPT_DIR}/vars.sh
    sed -i "s|isolation_cpu_cmdline_empty|${ISOLATION_CPU_CMDLINE}|g" ${SCRIPT_DIR}/vars.sh
}

function env_check_and_build() {
    settle_workdir
    prepare_yum_resource

    if [ "$SKIP_KERNEL_VERSION_CHECK" == "1" ]; then
        echo "skip check kernel version"
    else
        check_kernel_version
    fi
    check_cmdline
    check_SELinux
    check_service

    check_qemu
    check_libvirt

    check_numa_profile
    check_thread_profile
    check_virt_profile
    #检查pagesize

    # 在检查通过的情况下继续下一步动作
    if [ "$NEED_CPUPOWER_OPS" == "1" ]; then
        cpupower frequency-set -g performance
        echo "cpupower mode updated successfully"
    fi

    if [ "$VM_CPU_LIST" == "vm_cpu_list_empty" ]; then
        generate_vm_cpu_list
    fi

    check_benchmark
}

env_check_and_build
