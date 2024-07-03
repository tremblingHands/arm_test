#!/bin/bash
set -ex

CONFIG_FILE=${1:-"ampere.cfg"}
COPIES=${2:-1}
POWER_NUMS=${3:-5}
ROOT_DIR=/home/virt/benchmark
SPEC_CPU_DIR=$ROOT_DIR/spec_cpu_2017

#mount /dev/vdb $MOUNT_DIR
cd $SPEC_CPU_DIR
ulimit -s unlimited
source shrc > /dev/null

i=0
while ((i <= $POWER_NUMS)); do
	rm -rf tmp/
	rm -rf benchspec/CPU/*/run/
	runcpu --config=$CONFIG_FILE --iterations=3 --copies=$COPIES --action=run --nobuild --tune=base --nopower --runmode=rate --tune=base --size=refrate --noreportable intrate
	#echo $COPIES
	COPIES=$[COPIES*2]
	i=$[i+1]
	sleep 10
done
