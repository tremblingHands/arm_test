#! /bin/sh
wget 'http://10.1.180.190/bigdata/hadoop/hadoop-3.4.0-x86.tar.gz'
wget 'http://10.1.180.190/bigdata/HiBench-7.1.1.tar.gz'
tar xf hadoop-3.4.0-x86.tar.gz
tar xf http://10.1.180.190/bigdata/HiBench-7.1.1.tar.gz
echo 0.0.0.0 hadoop1 >> /etc/hosts 
if [[ $(lsof -t "/dev/nvme1n1") ]]; then
    lsof -t "/dev/nvme1n1" |xargs kill -9
fi
if [[ $(lsof -t "/dev/nvme3n1") ]]; then
    lsof -t "/dev/nvme3n1" |xargs kill -9
fi
if [[ $(lsof -t "/dev/nvme0n1") ]]; then
    lsof -t "/dev/nvme0n1" |xargs kill -9
fi
if [[ $(lsof -t "/dev/nvme2n1") ]]; then
    lsof -t "/dev/nvme2n1" |xargs kill -9
fi
if [ -e /data1 ]; then
    umount /data1 ||true
    rm -rf /data1
fi
if [ -e /data2 ]; then
    umount /data2 ||true
    rm -rf /data2
fi
if [ -e /data3 ]; then
    umount /data3 ||true
    rm -rf /data3
fi
mkfs.ext4  -F /dev/nvme1n1
mkfs.ext4  -F /dev/nvme3n1
mkdir /data1 /data2
mount /dev/nvme1n1 /data1
mount /dev/nvme3n1 /data2
if [ ! -e ~/.ssh/id_rsa ]; then
    ssh-keygen -A
    ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    echo "StrictHostKeyChecking no" >>/etc/ssh/ssh_config
else
    echo "ssh id_rsa exits!"
fi

echo "export HDFS_NAMENODE_USER=root
export HDFS_DATANODE_USER=root
export HDFS_SECONDARYNAMENODE_USER=root
export YARN_RESOURCEMANAGER_USER=root
export YARN_NODEMANAGER_USER=root" >> /root/.bashrc
source /root/.bashrc
echo "export JAVA_HOME=/etc/alternatives/java_sdk_1.8.0" >> /root/hadoop-3.4.0/etc/hadoop/hadoop-env.sh
cd /root/hadoop-3.4.0
bin/hadoop namenode -format
sbin/start-all.sh

cd /root/HiBench-7.1.1
sed -i 's/hibench.scale.profile tiny/hibench.scale.profile gigantic/g' conf/hibench.conf
sed -i 's/run_hadoop_job/eval run_hadoop_job/g' bin/workloads/micro/dfsioe/prepare/prepare.sh
sed -i 's/run_hadoop_job/eval run_hadoop_job/g' bin/workloads/micro/dfsioe/hadoop/run_read.sh
sed -i 's/run_hadoop_job/eval run_hadoop_job/g' bin/workloads/micro/dfsioe/hadoop/run_write.sh
    echo '
hibench.hadoop.home    /root/hadoop-3.4.0
hibench.hadoop.executable     ${hibench.hadoop.home}/bin/hadoop
hibench.hadoop.configure.dir  ${hibench.hadoop.home}/etc/hadoop
hibench.hdfs.master       hdfs://hadoop1:9000
hibench.hadoop.release    apache
' > conf/hadoop.conf
                echo '
micro.terasort
micro.dfsioe
' > conf/benchmarks.lst
                echo '
hadoop
' > conf/frameworks.lst

cd /root/HiBench-7.1.1
sed -i 's/hibench.default.map.parallelism 8/hibench.default.map.parallelism 128/g' conf/hibench.conf
sed -i 's/hibench.default.shuffle.parallelism 8/hibench.default.shuffle.parallelism 64/g' conf/hibench.conf
wget http://gitlab/appsoftware/scripts/-/blob/master/hj-tune/bigdata_tools.py
python3.6 .\bigdata_tools.py --ip 10.1.180.2 --passwd bigdata --action node_add
sleep 3
python3.6 .\bigdata_tools.py --ip 10.1.180.2 --passwd bigdata --action node_on
bin/run_all.sh
python3.6 .\bigdata_tools.py --ip 10.1.180.2 --passwd bigdata --action node_off
bash /root/hadoop-3.4.0/sbin/stop-all.sh
rm -rf /data1/*
rm -rf /data2/*
echo done all
