#!/bin/bash
set -e

source ../vars.sh

TEST_ENV=${1:-"host"}
FIO_TEST_TYPE_STR=${2:-"all"}
TEST_ACTION_STR=${3:-"all"}
TIMES_A_CYCLE=${4:-"5"}

if [ "${TEST_ENV}" == "host" ]; then
    FIO_TEST_DISK=${VM_DISK}
elif [ "${TEST_ENV}" == "guest" ]; then
    FIO_TEST_DISK="nvme0n1"
fi

FIO_TEST_TYPE_ARRAY=

TEST_DATE_DIR="${FIO_RUN_DIR}/${DATE}"
LOG_DIR=
RESULT_DIR=

ALREADY_EXE_TIMES=

function generate_cpu_list() {
    if [ "${TEST_ENV}" == "host" ]; then
        if [ "${2}" == "lat" ]; then
            CPU_LIST=${TEST_HOST_LIST1}
        else
            CPU_LIST=${TEST_HOST_LIST8}
        fi
    elif [ "${TEST_ENV}" == "guest" ]; then
        if [ "${2}" == "lat" ]; then
            CPU_LIST=${TEST_GUEST_LIST1}
        else
            CPU_LIST=${TEST_GUEST_LIST8}
        fi
    fi

}

function generate_test_array() {
    case "$1" in
    iops)
        TEST_ARRAY=("randread" "randwrite")
        ;;
    bw)
        TEST_ARRAY=("read" "write")
        ;;
        #    lat)
        #        TEST_ARRAY=("randread" "randwrite")
        #        ;;
    esac
}

function warmup() {
    local fio_test=$1
    nvme format -f /dev/${FIO_TEST_DISK}
    sed -i 2s/DEVICE/${FIO_TEST_DISK}/g "${fio_test}-warm.fio"
    for ((i = 1; i <= 2; i++)); do
        ${FIO_BIN}"${fio_test}-warm.fio" >>"${WARM_LOG_DIR}/warmup-seq_${i}.log"
        sleep 10
    done
    sed -i 2s/${FIO_TEST_DISK}/DEVICE/g "${fio_test}-warm.fio"
}

function performance_test() {
    local fio_test=$1
    local test_times=$2
    sed -i 2s/DEVICE/${FIO_TEST_DISK}/g "${fio_test}.fio"
    for i in $(seq 1 ${test_times}); do
        local already_test_times=0
        ((already_test_times = i + ALREADY_EXE_TIMES))
        for RWMODE in ${TEST_ARRAY[*]}; do
            sed -i 3s/RWMODE/${RWMODE}/g "${fio_test}.fio"
            sed -i 12s/CPU_LIST/${CPU_LIST}/g "${fio_test}.fio"
            echo "single test seq ${already_test_times} for ${RWMODE}, used_cpu is ${CPU_LIST}"
            ${FIO_BIN} "${fio_test}.fio" >>"${LOG_DIR}/${RWMODE}-seq_${already_test_times}.log"
            result=$(cat "${LOG_DIR}/${RWMODE}-seq_${already_test_times}.log" | grep " ${fio_test}" | grep avg)
            local units=$(echo ${result} | awk '{print $3}')
            units=${units%%/*}
            result=${result#*avg=}
            result=${result%%,*}
            if [ "${fio_test}" == "bw" ] && [ "$units" == "KiB" ]; then
                result=$(echo "scale=2; ${result}/1024" | bc)
            fi
            echo $result >>"${RESULT_DIR}/${RWMODE}.data"
            sleep 10
            sed -i 12s/${CPU_LIST}/CPU_LIST/g "${fio_test}.fio"
            sed -i 3s/${RWMODE}/RWMODE/g "${fio_test}.fio"
        done
    done
    sed -i 2s/${FIO_TEST_DISK}/DEVICE/g "${fio_test}.fio"
}

function periodic_test() {
    local numa_node_array=
    for fio_test_type in ${FIO_TEST_TYPE_ARRAY[*]}; do
        echo -e "\n########################## ${fio_test_type} test #############################"

        FIO_TEST_ROOT_DIR="${TEST_DATE_DIR}/${fio_test_type}"
        WARM_LOG_DIR="${FIO_TEST_ROOT_DIR}/warmup"
        LOG_DIR="${FIO_TEST_ROOT_DIR}/log"
        RESULT_DIR="${FIO_TEST_ROOT_DIR}/result"
        FINAL_RESULT="${FIO_TEST_ROOT_DIR}/final-result"
        mkdir -p ${WARM_LOG_DIR}
        mkdir -p ${LOG_DIR}
        mkdir -p ${RESULT_DIR}

        generate_cpu_list ${fio_test_type}
        if [ "${TEST_ACTION_STR}" == "all" ] || [ "${TEST_ACTION_STR}" == "warmup" ]; then
            echo "start warm up"
            warmup "${fio_test_type}"
        fi
        generate_test_array "$fio_test_type"

        pushd $FIO_SCRIPT_DIR >/dev/null
        echo -e "\n**********************"
        if [ "${TEST_ACTION_STR}" == "all" ] || [ "${TEST_ACTION_STR}" == "test" ]; then
            echo "start first ${TIMES_A_CYCLE} times performance test"
            ALREADY_EXE_TIMES=0
            performance_test "${fio_test_type}" "${TIMES_A_CYCLE}"
            ALREADY_EXE_TIMES=${TIMES_A_CYCLE}
            for ((k = 0; k <= 20; k++)); do
                local start_index=$(($k + 1))
                local pass=
                echo "check data stability from seq ${start_index}"
                for file in $(ls ${RESULT_DIR}); do
                    filename="${RESULT_DIR}/${file}"
                    local average_str=$(python3 help.py "$filename" $k ${TIMES_A_CYCLE})
                    pass=${average_str%=*}
                    local average=${average_str#*=}
                    if [ "${pass}" == "false" ]; then
                        echo "${file} failed"
                        rm -f ${FINAL_RESULT}
                        break
                    elif [ "${pass}" == "true" ]; then
                        echo "${file} passed"
                        echo "${file}: ${average}" >>${FINAL_RESULT}
                    else
                        echo "error when check ${file}"
                        break
                    fi
                done

                if [ "${pass}" == "true" ]; then
                    echo "all files check passed"
                    echo "start from ${start_index}" >>${FINAL_RESULT}
                    break
                elif [ "${pass}" == "false" ]; then
                    if [ "${k}" == "20" ]; then
                        echo "already executed 25 times, no more addtion"
                        break
                    fi
                    echo "add 1 time performance test"
                    performance_test "${fio_test_type}" 1
                    ((ALREADY_EXE_TIMES++))
                fi
            done
        fi
        popd >/dev/null
    done
}

function check_env_and_args() {
    NUMA_NODE_NUM=$(numactl -H | grep available | awk '{print $2}')
    echo "there are ${NUMA_NODE_NUM} numa nodes in machine"
    LOCAL_NUMA_NODE=$(cat /sys/block/${FIO_TEST_DISK}/device/numa_node)
    echo "device numa node is ${LOCAL_NUMA_NODE}"

    case "${FIO_TEST_TYPE_STR}" in
    all)
        FIO_TEST_TYPE_ARRAY=("iops" "bw")
        ;;
    iops)
        FIO_TEST_TYPE_ARRAY=("iops")
        ;;
    bw)
        FIO_TEST_TYPE_ARRAY=("bw")
        ;;
        #    lat)
        #        FIO_TEST_TYPE_ARRAY=("lat")
        #        ;;
    *)
        echo "unspported fio test type ${FIO_TEST_TYPE_STR}"
        exit 1
        ;;
    esac
}

function main() {
    check_env_and_args
    echo -e "\n====================================================================="
    local start_time=$(date +"%s")
    periodic_test
    local end_time=$(date +"%s")
    local cost_time=
    ((cost_time = end_time - start_time))
    echo "test time is $(($cost_time / 3600))hour $(($cost_time % 3600 / 60))min $(($cost_time % 60))s"
}

main
