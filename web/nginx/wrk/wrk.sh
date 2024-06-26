#!/bin/bash

host=$1
time=30
tcpport=61234
nginx_result=./result.txt
result=""

nginxmode=("httpshort" "httplong" "httpsshort" "httpslong" "httplonggzip")
wrkcmd=(
"./wrk -t 32 -c 1000 -d $time --latency -H \"Connection: Close\" http://$host/0kb.bin"
"./wrk -t 32 -c 1000 -d $time --latency http://$host/0kb.bin"
"./wrk -t 32 -c 1000 -d $time --latency -H \"Connection: Close\" https://$host/0kb.bin"
"./wrk -t 32 -c 1000 -d $time --latency https://$host/0kb.bin"
"./wrk -t 32 -c 1000 -d $time --latency -H \"Accept-Encoding: gzip\" http://$host/9kb.bin"
)
#wrkcmd=(
#"./wrk -t32 -c1024 -d1s --timeout=60s --latency -H \"Connection: Close\" -s test.lua http://$host"
#"./wrk -t32 -c1024 -d1s --timeout=60s --latency -s test.lua http://$host"
#"./wrk -t32 -c1024 -d1s --timeout=60s --latency -H \"Connection: Close\" -s test.lua https://$host"
#"./wrk -t32 -c1024 -d1s --timeout=60s --latency -s test.lua https://$host"
#"./wrk -t32 -c1024 -d1s --timeout=60s --latency -H \"Accept-Encoding: gzip\" -s test.lua http://$host"
#)

get_nginx_server_info(){

    while true
    do
        res=$(echo "conf$1" | nc  $host $tcpport 2>&1)
        if echo "$res" | grep -q "refused"; then
            sleep 1
            continue 
        fi
        break	
    done
    
    #The return value contains configuration information
    result=$(nc -l $tcpport 2>&1)
}

request_test_start(){

    while true
    do
        res=$(echo "start$1" | nc $host $tcpport 2>&1)
        if echo "$res" | grep -q "refused"; then
echo "dbg sleep 1"
            sleep 1
            continue 
        fi
        break	
    done

    result=$(nc -l $tcpport 2>&1)
    if echo "$result" | grep -q "start$1"; then
echo "dbg [$1] is ok"
echo "start $1 " >>${nginx_result}
        return
    else
echo "dbg [$1] is error"
echo "start $1-error " >>${nginx_result}
        exit
    fi	
}
request_test_finish(){

    while true
    do
        res=$(echo "finish$1" | nc $host $tcpport 2>&1)
        if echo "$res" | grep -q "refused"; then
echo "dbg sleep 1"
            sleep 1
            continue 
        fi
        break	
    done

    result=$(nc -l $tcpport 2>&1)
    if echo "$result" | grep -q "finish$1"; then
echo "dbg [$1] is ok"
echo "finish $1" >>${nginx_result}
        return
    else
echo "dbg [$1] is error"
echo "finish $1-error " >>${nginx_result}
        exit
    fi	
}

helphandle(){
    echo "./wrk.sh <10.1.180.15> <Test mode>"
    echo "Test mode:"
    echo "    socketl   :Test the performance on socket local"
    echo "    socketr   :Test the performance on socket remote"
    echo "    node      :Testing the impact of numa nodes on performance"
    echo "    server    :Test the performance of the entire server"
    echo "    stats     :Statistical test results"
    echo "    all       :Test the performance of the socketl+socketr+node+server+stats"
}

socketlocalhandle(){
    echo "========localsocket Test========"

    #performance and performance linearity of Nginx on a single CPU.
    crc="localsocket"

    #Get count of CPU on local socket
    get_nginx_server_info "getcpunumoflocalsocket"
    socket_cpucount=$result

    #httpshort,httplong,httpsshort,httpslong,httplonggzip
    for (( i=0; i<${#wrkcmd[@]}; i++ ));
    do
        cmdt=${wrkcmd[i]}
        mode=${nginxmode[i]}

        #Test cores:1, 2, 4... 2^n m(the maximum number of cores) in the current socket.
        for ((core=1; core<=$socket_cpucount; core*=2))
        do  
            #wait remote nginx is start
            request_test_start "$mode-$crc-core$core"

            #Testing
            echo "$cmdt" >> ${nginx_result}
echo "dgb start $cmdt"
            while true; do
                eval "$cmdt >> ${nginx_result}"
                ret=$?
                if [ $ret -eq 0 ]; then
                    break
                else
echo "dgb start again $cmdt"
                    sleep 1
                    continue
                fi
            done
echo "dgb stop $cmdt"

            #tell remote testing is finish		
            request_test_finish "$mode-$crc-core$core"
        done

        #max is not 2^n
        if [ $((socket_cpucount * 2)) -ne $core ]; then  
            #wait remote nginx is start
            request_test_start "$mode-$crc-core$core"

            #Testing
            echo "$cmdt" >> ${nginx_result}
echo "dgb start $cmdt"
            while true; do
                eval "$cmdt >> ${nginx_result}"
                ret=$?
                if [ $ret -eq 0 ]; then
                    break
                else
echo "dgb start again $cmdt"
                    sleep 1
                    continue
                fi
            done
echo "dgb stop $cmdt"

            #tell remote testing is finish		
            request_test_finish "$mode-$crc-core$core"
        fi
    done
}

socketremotehandle(){
    echo "========remotesocket Test========"

    #Get count of CPU on remote socket
    crc="remotesocket"

    get_nginx_server_info "getcpunumofremotesocket"
    socket_cpucount=$result

    #httpshort,httplong,httpsshort,httpslong,httplonggzip
    for (( i=0; i<${#wrkcmd[@]}; i++ ));
    do
        cmdt=${wrkcmd[i]}
        mode=${nginxmode[i]}

        #Test cores:1, 2, 4... 2^n m(the maximum number of cores) in the current socket.
        for ((core=1; core<=$socket_cpucount; core*=2))
        do  
            #wait remote nginx is start
            request_test_start "$mode-$crc-core$core"

            #Testing
            echo "$cmdt" >> ${nginx_result}
echo "dgb start $cmdt"
            while true; do
                eval "$cmdt >> ${nginx_result}"
                ret=$?
                if [ $ret -eq 0 ]; then
                    break
                else
echo "dgb start again $cmdt"
                    sleep 1
                    continue
                fi
            done
echo "dgb stop $cmdt"

            #tell remote testing is finish		
            request_test_finish "$mode-$crc-core$core"
        done

        #max is not 2^n
        if [ $((socket_cpucount * 2)) -ne $core ]; then  
            #wait remote nginx is start
            request_test_start "$mode-$crc-core$core"

            #Testing
            echo "$cmdt" >> ${nginx_result}
echo "dgb start $cmdt"
            while true; do
                eval "$cmdt >> ${nginx_result}"
                ret=$?
                if [ $ret -eq 0 ]; then
                    break
                else
echo "dgb start again $cmdt"
                    sleep 1
                    continue
                fi
            done
echo "dgb stop $cmdt"

            #tell remote testing is finish		
            request_test_finish "$mode-$crc-core$core"
        fi
    done
}

nodehandle(){
    echo "========node Test========"
    #Get count of node on two socket
    get_nginx_server_info "getnodenum"
    node_num=$result
    echo "nginx server node_num=$result"

    #httpshort,httplong,httpsshort,httpslong,httplonggzip
    for (( i=0; i<${#wrkcmd[@]}; i++ ));
    do
        cmdt=${wrkcmd[i]}
        mode=${nginxmode[i]}

        #each all node
        for ((node=0; node<$node_num; node+=1))
        do  
            #Get count of CPUs on current node
            get_nginx_server_info "$mode-node$node"
            cpuid_count=$result

            #Test cores:1, 2, 4... 2^n m(the maximum number of cores) in the current numa node.
            for ((core=1; core<=$cpuid_count; core*=2))
            do  
                #wait remote nginx is start
                request_test_start "$mode-node$node-core$core"

                #Testing
echo "dgb start $cmdt"
                echo "$cmdt" >> ${nginx_result}
                while true; do
                    eval "$cmdt >> ${nginx_result}"
                    ret=$?
                    if [ $ret -eq 0 ]; then
                        break
                    else
echo "dgb start again $cmdt"
                        sleep 1
                        continue
                    fi
                done
echo "dgb stop $cmdt"
                #tell remote testing is finish		
                request_test_finish "$mode-node$node-core$core"
            done

            #max is not 2^n
            if [ $((cpuid_count * 2)) -ne $core ]; then  
                #wait remote nginx is start
                request_test_start "$mode-node$node-core$core"

                #Testing
echo "dgb start $cmdt"
                echo "$cmdt" >> ${nginx_result}
                while true; do  
                    eval "$cmdt >> ${nginx_result}"
                    ret=$?   
                    if [ $ret -eq 0 ]; then
                        break
                    else  
echo "dgb start again $cmdt"
                        sleep 1
                        continue
                    fi  
                done  
echo "dgb stop $cmdt"

                #tell remote testing is finish		
                request_test_finish "$mode-node$node-core$core"
            fi
        done
    done
}
serverhandle(){
    echo "========server Test========" >> ${nginx_result}

    #httpshort,httplong,httpsshort,httpslong,httplonggzip
    #for cmdt in "${wrkcmd[@]}"
    for (( i=0; i<${#wrkcmd[@]}; i++ ));   
    do
        cmdt=${wrkcmd[i]}
        mode=${nginxmode[i]}

        #wait remote nginx is start
        request_test_start "$mode-server"

        #Testing
        echo "$cmdt" >> ${nginx_result}
        eval "$cmdt >> ${nginx_result}"

        #tell remote testing is finish		
        request_test_finish "$mode-server"
    done
}
statisticshandle(){
    echo "========statistics========" 
    get_nginx_server_info "getservername"
    name=$result
    echo "server name:$name"
    #cat result.txt |grep -E "start|sec"|awk '{print$2}' >./result_$name.csv
    cat result.txt |grep -E "start|sec"|grep -A2 "httpshort-"|grep -v "\-\-"|awk '{print$2}' >./result_$name.csv
    cat result.txt |grep -E "start|sec"|grep -A2 "httplong-"|grep -v "\-\-"|awk '{print$2}' >>./result_$name.csv
    cat result.txt |grep -E "start|sec"|grep -A2 "httpsshort-"|grep -v "\-\-"|awk '{print$2}' >>./result_$name.csv
    cat result.txt |grep -E "start|sec"|grep -A2 "httpslong-"|grep -v "\-\-"|awk '{print$2}' >>./result_$name.csv
    cat result.txt |grep -E "start|sec"|grep -A2 "httplonggzip-"|grep -v "\-\-"|awk '{print$2}' >>./result_$name.csv
    cp result.txt result_$name.txt
    curtime=$(date +"%Y%m%d%H%M%S")
    mkdir -p /nas/linus.tang/nginx/to_nginx/result/$name/$curtime
    cp result* /nas/linus.tang/nginx/to_nginx/result/$name/$curtime/ -rf
}
case $2 in
    socketl)
        echo "">./result.txt
        socketlocalhandle
        ;;
    socketr)
        echo "">./result.txt
        socketremotehandle
        ;;
    node)
        echo "">./result.txt
        nodehandle
        ;;
    server)
        echo "">./result.txt
        serverhandle
        ;;
    stats)
        statisticshandle
        ;;
    all)
        echo "">./result.txt
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
