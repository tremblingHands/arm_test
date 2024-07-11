#!/bin/bash
set -ex

source ../vars.sh

TEST_ENV=${1:-"host"}
COPIES=${2:-1}
POWER_NUMS=${3:-5}
TEST_DATE_DIR="${SPEC_CPU_RUN_DIR}/${DATE}"
LOG_FILE="${TEST_DATE_DIR}/log"
RESULT_FILE="${TEST_DATE_DIR}/result"

if [ "${TEST_ENV}" == "host" ]; then
	CONFIG_FILE="${SPEC_CONFIG_PREFIX}-host.cfg"
elif [ "${TEST_ENV}" == "guest" ]; then
	CONFIG_FILE="${SPEC_CONFIG_PREFIX}-guest.cfg"
fi

mkdir -p "${SPEC_CPU_RUN_DIR}/${DATE}"
cd $SPEC_CPU_EXE_DIR
ulimit -s unlimited
source shrc >/dev/null

i=0
while ((i <= $POWER_NUMS)); do
	rm -rf tmp/
	rm -rf benchspec/CPU/*/run/
	runcpu --config=${CONFIG_FILE} --iterations=3 --copies=${COPIES} --action=run --nobuild --tune=base --nopower --runmode=rate --tune=base --size=refrate --noreportable intrate 1>>${LOG_FILE}
	#echo $COPIES
	COPIES=$((COPIES * 2))
	i=$((i + 1))
	sleep 10
done

echo "finish spec-cpu test successfully"
