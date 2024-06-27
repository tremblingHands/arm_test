eth=$1
host=$2
tcpport=61234

nginxmode=("httpshort" "httplong" "httpsshort" "httpslong" "httplonggzip")

nginx_conf=/usr/local/nginx/conf/nginx.conf
cpu_affinity=1
cpu_str_to_affinity(){
    #1 2 3 4...n
    cpu_str=$1
    nb_core=$2
    cnt=0
    affinity=""

    # each all number
    for cpu in $cpu_str; do
        if ((cnt >= nb_core)); then
            break
        fi
        ((cnt++))

        if [ $cpu -eq 0 ]; then  
            affinity="$affinity 1" 
        else  
            affinity="$affinity $(printf "1%0${cpu}d" 0)" 
        fi	
    done
    cpu_affinity=$affinity
echo "dbg cpu_str=$1"
echo "dbg nb_core=$2"
}
nginx_restart(){
    if ps -ef | grep -v grep | grep "nginx: worker process" >/dev/null
    then
        #nginx is running
        expect <<EOF
set timeout 30
spawn /usr/local/nginx/sbin/nginx -s stop
expect "Enter PEM pass phrase" { send "0000\\r" }
send '\\n"
expect eof
EOF
    fi
    sleep 1

    #nginx is not running
    expect <<EOF
set timeout 30
spawn /usr/local/nginx/sbin/nginx
expect "Enter PEM pass phrase" { send "0000\\r" }
send '\\n"
expect eof
EOF
    sleep 1
    ps axo pid,cmd,psr | grep nginx | grep -v grep|grep -v master
    ps axo pid,cmd,psr | grep nginx | grep -v grep|grep -v master|wc -l
}

get_nginx_server_info(){
    content=$2

    #check crc
    result=`nc -l $tcpport`
    if echo "$result" | grep -q "conf$1"; then
echo "dbg [$1] is ok"
    else
echo "dbg [$1]  is error"
        exit
    fi	
	
    #respone content
    while true
    do
        res=`echo "$content" | nc  $host $tcpport 2>&1`
        if echo "$res" | grep -q "refused"; then
            sleep 1
            continue 
        fi
        break	
    done
}

wait_test_start(){

    result=`nc -l $tcpport`
    if echo "$result" | grep -q "start$1"; then
echo "dbg [$1] is ok"
    else
echo "dbg [$1] is error"
        exit
    fi	
    
    while true
    do
        res=`echo "start$1" | nc  $host $tcpport 2>&1`
        if echo "$res" | grep -q "refused"; then
            sleep 1
            continue 
        fi
        break	
    done
}
wait_test_finish(){

    result=`nc -l $tcpport`
    if echo "$result" | grep -q "finish$1"; then
echo "dbg [$1] is ok"
    else
echo "dbg [$1] is error"
        exit
    fi

    while true
    do
        res=`echo "finish$1" | nc  $host $tcpport 2>&1`
        if echo "$res" | grep -q "refused"; then
            sleep 1
            continue 
        fi
        break	
    done
}

helphandle(){
    echo "./nginx.sh <eth0> <10.1.180.9> <Test mode>"
    echo "Test mode:"
    echo "    socketl   :Test the performance on socket local"
    echo "    socketr   :Test the performance on socket remote)"
    echo "    node      :Testing the impact of numa nodes on performance"
    echo "    server    :Test the performance of the entire server"
    echo "    all       :Test the performance of the socketl+socketr+node+server"
}

get_nic_node(){
    nic_pciaddr=`ethtool -i $eth |grep bus-info|awk '{print$2}'`
    nic_node=`lspci -s $nic_pciaddr -vv|grep node |awk '{print$3}'`
    echo $nic_node 
}

# set_nic_irq_to_socket(){
    # #stop irqbalance
    # systemctl stop irqbalance
	
    # #Get irq of nic
    # nic_pciaddr=`ethtool -i $eth |grep bus-info|awk '{print$2}'`
    # #in /proc/interrupts,Intel show ethx, Mellanox show 0000:25:00.1
    # nic_irqlist=`cat /proc/interrupts |grep -E "$eth|$nic_pciaddr"|awk '{print$1}'|sed 's/.$//'`
	
    # #Get CPU list from socket0 and socket1
	
    # #each every irq to set it on CPU of another hsocket
    # for irq in $nic_irqlist
    # do
        # #Get CPU corresponding to irq
        # cpu=`cat /proc/irq/$irq/smp_affinity_list`
    # done

# }

nginx_on_one_socket_handle(){
	
    socket_cpulist=""
    rm /usr/local/nginx/conf/nginx.conf -f
    cp ./nginx.conf /usr/local/nginx/conf/nginx.conf

    #Get node where the NIC is located
    nic_node=$(get_nic_node)

    socket_num=`dmidecode -t processor | grep "Socket Designation" | wc -l`
    node_num=`numactl -H|grep cpus:|wc -l`
	
    if [ $socket_num -ne $node_num ]; then  
        #multiple nodes on the socket
		
        result=$((node_num / socket_num)) 
        #If the node where the NIC is located is less than result, it indicates that the NIC is in socket 0. Conversely, if the node is less than result, it indicates that the NIC is in socket1 
        if [ $nic_node -lt $result ]; then  
            #NIC on socket0  
            if [ "$1" = "local" ]; then 
                #Nginx and NIC are on the same socket 
                start_node=0
                end_node=$(($result-1))
            else  
                #Nginx and NIC are on the different socket
                start_node=$result
                end_node=$(($node_num-1))
            fi
        else  
            #NIC on socket1
            if [ "$1" = "local" ]; then
                #Nginx and NIC are on the same socket
                start_node=$result
                end_node=$(($node_num-1))
            else
                #Nginx and NIC are on the different socket
                start_node=0
                end_node=$(($result-1))
            fi
        fi
		
        #Get CPU list on curring socket 
        for ((node=$start_node; node<=$end_node; node+=1))
        do 
            cpulist=`numactl -H|grep "node $node cpus:"|awk -F: '{print $2}'`
            socket_cpulist="$socket_cpulist $cpulist"
        done
echo "dbg startnode=$start_node end_node=$end_node cpulist=$socket_cpulist"
    else
        #single nodes on the socket
        if [ "$1" = "local" ]; then 
            #Nginx and NIC are on the same socket
            node=$nic_node
        else  
            #Nginx and NIC are on the different socket
            node=$((1 - $nic_node))  
        fi
			
            #Get CPU list on curring socket
            socket_cpulist=`numactl -H|grep "node $node cpus:"|awk -F: '{print $2}'`
    fi
    #Get the current number of CPUs in the socket
    socket_cpucount=$(echo "$socket_cpulist" | awk -F' ' '{print NF}')	

    if [ "$1" = "local" ]; then
        #Nginx and NIC are on the same socket
        crc="localsocket"
    else
        #Nginx and NIC are on the different socket
        crc="remotesocket"
    fi

    get_nginx_server_info "getcpunumof$crc" $socket_cpucount
	
    #httpshort,httplong,httpsshort,httpslong,httplonggzip
    for mode in "${nginxmode[@]}"
    do
        if [ "$mode" = "httplonggzip" ]; then  
            #HTTP compression scenario, modify gzip in nginx. conf and set it to on
            sed -i 's/\(gzip\) .*/\1 on;/' ${nginx_conf} 
        else
            #HTTP uncompressed scenario, modify gzip in nginx. conf to off
            sed -i 's/\(gzip\) .*/\1 off;/' ${nginx_conf}
        fi

        #Test cores:1, 2, 4... 2^n m(the maximum number of cores) in the current numa node.
        for ((core=1; core<=$socket_cpucount; core*=2))
        do  
            cpu_str_to_affinity "$socket_cpulist" $core
            echo "core=$core cpu_affinity=$cpu_affinity"
            #Replace the value of worker_cpu_affinity in /usr/local/bin/nginx/conf/nginx.conf
            sed -i "s/\(worker_processes\) .*/\1 $core;/" ${nginx_conf} 
            sed -i "s/\(worker_cpu_affinity\) .*/\1 $cpu_affinity;/" ${nginx_conf} 
			
            #Restart Nginx
            nginx_restart
			
            wait_test_start "$mode-$crc-core$core"

            #Testing

            wait_test_finish "$mode-$crc-core$core"
        done
		
        #max is not 2^n
        if [ $((socket_cpucount * 2)) -ne $core ]; then  
            cpu_str_to_affinity "$socket_cpulist" $socket_cpucount
            #echo "cpu_affinity=$cpu_affinity"
            #Replace the value of worker_cpu_affinity in /usr/local/bin/nginx/conf/nginx.conf
            sed -i "s/\(worker_processes\) .*/\1 $core;/" ${nginx_conf} 
            sed -i "s/\(worker_cpu_affinity\) .*/\1 $cpu_affinity;/" ${nginx_conf} 
  
            #Restart Nginx
            nginx_restart

            wait_test_start "$mode-$crc-core$core"

            #Testing

            wait_test_finish "$mode-$crc-core$core"
        fi
    done
}

socketlocalhandle(){
    nginx_on_one_socket_handle "local"
}
socketremotehandle(){
    nginx_on_one_socket_handle "remote"
	
    #Set irq to another socket
    # set_nic_irq_to_socket "remote"
    # nginx_on_one_socket_handle "local"
    # nginx_on_one_socket_handle "remote"
}
nodehandle(){
    echo "node Test"
    rm /usr/local/nginx/conf/nginx.conf -f
    cp ./nginx.conf /usr/local/nginx/conf/nginx.conf

    #Get count of node
    node_num=`numactl -H|grep cpus:|wc -l`
    get_nginx_server_info "getnodenum" $node_num
	
    #httpshort,httplong,httpsshort,httpslong,httplonggzip
    for mode in "${nginxmode[@]}"
    do
        if [ "$mode" = "httplonggzip" ]; then  
            #HTTP compression scenario, modify gzip in nginx. conf and set it to on
            sed -i 's/\(gzip\) .*/\1 on;/' ${nginx_conf} 
        else
            #HTTP uncompressed scenario, modify gzip in nginx. conf to off
            sed -i 's/\(gzip\) .*/\1 off;/' ${nginx_conf}
        fi

        #each every node
        for ((node=0; node<$node_num; node+=1))
        do  
            #Get CPU list onf node
            node_cpuid=`numactl -H|grep "node $node cpus:"|awk -F: '{print $2}'`
            cpuid_count=$(echo "$node_cpuid" | awk -F' ' '{print NF}')
			
            get_nginx_server_info "$mode-node$node" $cpuid_count
			
            #Test cores:1, 2, 4... 2^n m(the maximum number of cores) in the current numa node.
            for ((core=1; core<=$cpuid_count; core*=2))
            do  
                cpu_str_to_affinity "$node_cpuid" $core

                #Replace the value of worker_cpu_affinity in /usr/local/bin/nginx/conf/nginx.conf
                sed -i "s/\(worker_processes\) .*/\1 $core;/" ${nginx_conf} 
                sed -i "s/\(worker_cpu_affinity\) .*/\1 $cpu_affinity;/" ${nginx_conf} 
				
                #Restart Nginx
                nginx_restart
				
                wait_test_start "$mode-node$node-core$core"

                #Testing

                wait_test_finish "$mode-node$node-core$core"
            done
			
            #max is not 2^n
            if [ $((cpuid_count * 2)) -ne $core ]; then  
                cpu_str_to_affinity "$node_cpuid" $cpuid_count

                #Replace the value of worker_cpu_affinity in /usr/local/bin/nginx/conf/nginx.conf
                sed -i "s/\(worker_processes\) .*/\1 $core;/" ${nginx_conf} 
                sed -i "s/\(worker_cpu_affinity\) .*/\1 $cpu_affinity;/" ${nginx_conf} 
				
                #Restart Nginx
                nginx_restart

                wait_test_start "$mode-node$node-core$core"

                #Testing

                wait_test_finish "$mode-node$node-core$core"
            fi 
        done
    done
}
serverhandle(){
    echo "server Test"

    #httpshort,httplong,httpsshort,httpslong,httplonggzip
    for mode in "${nginxmode[@]}"
    do
        echo "Start test $mode"
        if [ "$mode" = "httplonggzip" ]; then
            #HTTP compression scenario, modify gzip in nginx. conf and set it to on
            sed -i 's/\(gzip\) .*/\1 on;/' ${nginx_conf} 
        else
            #HTTP uncompressed scenario, modify gzip in nginx. conf to off
            sed -i 's/\(gzip\) .*/\1 off;/' ${nginx_conf}
        fi
        sed -i 's/\(worker_processes\) .*/\1 auto;/' ${nginx_conf} 
        sed -i '/worker_cpu_affinity/d' ${nginx_conf}
cat ${nginx_conf}

        #Restart Nginx
        nginx_restart

        wait_test_start "$mode-server"

        #Testing

        wait_test_finish "$mode-server"
    done
}
statisticshandle(){
    echo "========statistics========"
    name=`uname -n`
    echo "server name:$name"
    get_nginx_server_info "getservername" $name
}


case $3 in
    socketl)
        socketlocalhandle
        ;;
    socketr)
        socketremotehandle
        ;;
    node)
        nodehandle
        ;;
    server)
        serverhandle
        ;;
    stats)
        statisticshandle
        ;;
    all)
        socketlocalhandle
        socketremotehandle
        nodehandle
        serverhandle
        statisticshandle
        ;;
    *)
        helphandle
        ;;
esac
