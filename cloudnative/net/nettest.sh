#!/bin/bash

# Check platform environment
check_env() {
    # check operating privileges
    if [ "$EUID" -ne 0 ]; then
        echo "Please use root to run this script!"
        exit 1
    fi
  
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
  
    # check performance mode
    current_governor=$(cpupower frequency-info --policy | grep "The governor" | awk '{print $4}')
  
    if [ "$current_governor" = "performance" ]; then
        echo "current status is performance mode as expected"
    else
        echo "current status is NOT performance mode"
        exit 1
    fi  


    # check irqbalance
    service_state=$(systemctl is-active irqbalance)

    if [ "$service_state" = "active" ]; then
        echo "irqbalance is active, it should be disabled!"
        exit 1
    else
        echo "irqbalance is inactive as expected" 
    fi

    # check kernel same page merging 
    service_state=$(systemctl is-active ksm)

    if [ "$service_state" = "active" ]; then
        echo "KSM is active, it should be disabled!"
        exit 1
    else
        echo "KSM is inactive as expected" 
    fi
}

# Install the dependency packages
install_deppackages() {
    # Install sysstat
    yum install -y sysstat
  
    # Install iperf3
    yum install -y iperf3
}

# start iperf3 server daemon to test PPS
pps_server_start() {
    for ((i=0;i<$1;i++))
    do
        tmpcpu=`expr $2 + $i`
        tmpport=`expr $3 + $i`
        echo "CPU=$tmpcpu  port=$tmpport"
        numactl -C $tmpcpu iperf3 -p $tmpport -s -D
    done
}

# start iperf3 client threads to test PPS
pps_client_start() {
    for ((i=0;i<$1;i++))
    do
        tmpcpu=`expr $2 + $i`
        tmpport=`expr $3 + $i`
        echo "CPU=$tmpcpu  port=$tmpport"
        numactl -C $tmpcpu iperf3 -c $4 -p $tmpport -u -b 10G -t 600 -l 16 > pps_tmp_$tmpport.log 2>&1 &  
    done
    
}

# collect PPS data and store it into resultfile
pps_collect() {
    sar -n DEV 1 60  > pps_result.data 2>&1   
}


# start iperf3 server threads to test bandwidth
bw_server_start() {
    numactl -C $1 iperf3 -p $2 -s -D
}

# start iperf3 client threads to test bandwidth
bw_client_start() {
    numactl -C $1 iperf3 -c $2 -p $3 -t 600 > bw_tmp.log 2>&1 &
}

# collect BW data and store it into resultfile
bw_collect() {
    sar -n DEV 1 60  > bw_result.data 2>&1   
}

# clean iperf3 processes 
clean() {
    # check all perf3 processes
    iperf3_pids=$(pgrep iperf3)

    if [ -z "$iperf3_pids" ]; then
        echo "there are no iperf3 processes running"
        return 0
    fi

    # kill all iperf3 processes
    echo "killing iperf3 processes: $iperf3_pids"
    kill $iperf3_pids

    # confirm all processes are killed
    sleep 1
    iperf3_pids=$(pgrep iperf3)

    if [ -z "$iperf3_pids" ]; then
        echo "all iperf3 processes are killed"
        return 0
    else
        echo "some iperf3 processes are not killed, try to kill them with -9"
        kill -9 $iperf3_pids
    fi

    # finally confirm
   sleep 1
   iperf3_pids=$(pgrep iperf3)

   if [ -z "$iperf3_pids" ]; then
      echo "all iperf3 processes are killed"
      return 0 
   else
      echo "some iperf3 processes cannot be killed with -9, please check the reason"
      exit 1
   fi
}

# show help information
show_help() {
    echo "Usage: nettest.sh [command] [arguments]"
    echo ""
    echo "Commands:"
    echo "-h: show help information and exit"
    echo "check_env: check platform environment" 
    echo "install_deppackages: installl dependent packages" 
    echo "pps_server_start <cpunum> <start_cpu> <start_port>: start iperf server daemon threads to test PPS" 
    echo "pps_client_start <cpunum> <start_cpu> <start_port> <server_ip>: start iperf client threads to test PPS " 
    echo "pps_collect: collect pps data and store it into result_pps.data file"
    echo "bw_server_start <cpu_list> <port>: start iperf server daemon threads to test bandwidth"
    echo "bw_client_start <cpu_list> <server_ip> <port>: start iperf client threads to test bandwidth"
    echo "bw_collect: collect bandwidth data and store it into result_bw.data"
    echo "clean: clean iperf3 threads"

}

# check input arguments
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

# get command and arguments
command=$1
shift

# conduct command
case "$command" in
    check_env)
        echo "### start to check environment..."
        check_env
        echo "### check environment end"
        ;;

    install_deppackages)
        echo "### start to install deppackages..."
        install_deppackages
        echo "### deppackages are installed successfully"
        ;;

    pps_server_start)
        echo "### starting iperf3 server daemon to test PPS..."
        if [ $# -ne 3 ]; then
           echo "Error, pps_server_start needs 3 parameters"
           show_help
           exit 1
        fi
        pps_server_start $1 $2 $3
        echo "### iperf3 server daemon successfully started"
        ;;

    pps_client_start)
        echo "### starting iperf3 client to test PPS..."
        if [ $# -ne 4 ]; then
           echo "Error, pps_client_start needs 4 parameters"
           show_help
           exit 1
        fi
        pps_client_start $1 $2 $3 $4
        echo "### iperf3 client threads successfully started"
        ;;
     
    pps_collect)
        echo "### starting to collect PPS data..."
        pps_collect
        echo "### PPS data successfully collected and stored into pps_result.data"
        ;;

    bw_server_start)
        echo "### starting iperf3 server daemon to test bandwidth..."
        if [ $# -ne 2 ]; then
           echo "Error, bw_server_start needs 2 parameters"
           show_help
           exit 1
        fi

        bw_server_start $1 $2
        echo "### iperf3 server daemon successfully started"
        ;;

    bw_client_start)
        echo "### starting iperf3 client to test bandwidth..."
        if [ $# -ne 3 ]; then
           echo "Error, bw_server_start needs 3 parameters"
           show_help
           exit 1
        fi
        bw_client_start $1 $2 $3
        echo "### iperf3 client threads successfully started"
        ;;
     
    bw_collect)
        echo "### starting to collect bw data..."
        bw_collect
        echo "### bw data successfully collected and stored into bw_result.data"
        ;;

    clean)
        echo "### starting to clean iperf threads ...."
        clean
        echo "### iperf threads are successfully cleaned"
        ;;

    -h)
        show_help
        ;;
    *)
        echo "Error: unknown command $command"
        show_help
        exit 1
        ;;
esac
