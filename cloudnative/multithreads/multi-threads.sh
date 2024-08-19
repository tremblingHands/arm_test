#!/bin/bash

# Total RUN rounds
EXEC_ROUND=5

# Execution time in one round
EXEC_TIME=120

# Bind CPUS
EXEC_CPUS="8-15,136-147"

CSVFILE=result.csv

# Check operating privileges
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please use root to run this script!"
    exit 1
  fi
}

# Check platform environment
check_env() {
  # check OS version
  if [ -f /etc/redhat-release ]; then
    os_version=$(cat /etc/redhat-release)
    if [[ "$os_version" == *"CentOS Stream 8"* ]]; then
      echo "Platform OS is Centos Stream 8!"
      return 0
    else
      echo "Platform OS is $os_version, This script only supports Centos Stream 8!"
      exit 1
    fi
  else
    echo "This script only supports RedHat 8.0!"
    exit 1
  fi
}

# Install the dependency packages
install_deppackages() {
  # Install mysql
  yum install -y mysql 

  # Install mysql lib
  yum install -y mysql-devel.aarch64 
}

# Install sysbench 
install_sysbench() {
  # assume sysbench-1.0.20 has been copied to local dir
  cd ./sysbench-1.0.20/
  ./autogen.sh
  ./configure
  make 
  make install
}

# Conduct sysbench and collect performance data
run_test() {
  
  # delete the tmp logfile
  rm ./round* ./$CSVFILE -rf 
  
  # populate csv table headers
  echo " ,AVG Latency(ms),P95 Latency(ms)" > $CSVFILE
 
  for ((i=1;$i<=$EXEC_ROUND;i++))
  do
    echo "##### ROUND$i starting..."
    numactl -C $EXEC_CPUS -m 0 sysbench threads --threads=16 --thread-locks=8 --time=$EXEC_TIME --report-interval=5 run > round$i.log 2>&1
    avglat=`grep "avg:" round$i.log |awk '{print $2}'`
    p95lat=`grep "95th" round$i.log |awk '{print $3}'`
    echo "ROUND$i,$avglat,$p95lat" >> $CSVFILE
    
    echo "##### ROUND$i end"
  done 
    
}

# The main function
main() {
  #check_root
  #check_env
  #install_deppackages
  #install_sysbench
  run_test  
}

main

