#!/bin/bash
set -ex

source ../vars.sh

TEST_ENV=${1:-"host"}
TEST_DATE_DIR="${DHRYSTONE_RUN_DIR}/${DATE}"
LOG_FILE="${TEST_DATE_DIR}/log"
RESULT_FILE="${TEST_DATE_DIR}/result"

if [ "${TEST_ENV}" == "host" ]; then
    TEST_CPU=${TEST_HOST_LIST1}
elif [ "${TEST_ENV}" == "guest" ]; then
    TEST_CPU=${TEST_GUEST_LIST1}
fi

mkdir "${TEST_DATE_DIR}"
for ((i = 0; i < 3; i++)); do
    interact_call "${DHRYSTONE_BIN}" "benchmark:" "${DHRYSTONE_ARG_RUN_TIMES}" 1>>${LOG_FILE}
    sleep 10
done

cat ${LOG_FILE} | grep VAX | awk '{print $5}' 1>${RESULT_FILE}


echo "finish dhrystone test successfully"