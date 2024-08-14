#!/bin/sh

set -e

yum install -y perf gcc-toolset-10 python38 perl cmake unzip bzip2 patch expect numactl php-cli php-xml php-json 
source /opt/rh/gcc-toolset-10/enable
alias python3=python3.8
python3 -m pip install psutil

cd $HOME

if [ -d "ffmpeg_" ]; then
    echo "ffmpeg_ directory exists."
else
    echo "ffmpeg_ directory does not exist."
    mkdir ffmpeg_/

    wget http://10.1.180.190/videocodec/ffmpeg/ffmpeg-7.0.tar.xz
    wget http://10.1.180.190/videocodec/ffmpeg/x264-7ed753b10a61d0be95f683289dfb925b800b0676.zip
    wget http://10.1.180.190/videocodec/ffmpeg/x265_3.6.tar.gz
    wget http://10.1.180.190/videocodec/ffmpeg/vbench-02.zip
    
    wget http://10.1.180.190/videocodec/ffmpeg/nasm-2.16.03.tar.gz
    tar xzvf nasm-2.16.03.tar.gz
    cd nasm-2.16.03 && ./configure && make -j && make install 
    cd - && rm -rf nasm*
    
    wget http://10.1.180.190/videocodec/ffmpeg/yasm-1.3.0.tar.gz
    tar xzvf yasm-1.3.0.tar.gz
    cd yasm-1.3.0 && ./configure && make -j && make install
    cd - && rm -rf yasm*
    
    tar -xf ffmpeg-7.0.tar.xz
    unzip -o x264-7ed753b10a61d0be95f683289dfb925b800b0676.zip
    tar -xf x265_3.6.tar.gz
    
    export PKG_CONFIG_PATH="$HOME/ffmpeg_/lib/pkgconfig"
    cd ~/x264-7ed753b10a61d0be95f683289dfb925b800b0676
    ./configure --prefix=$HOME/ffmpeg_/ --enable-static --enable-lto --enable-pic
    make -j $NUM_CPU_CORES
    make install
    cd ~ && rm -rf x264*
    
    cd ~/x265_3.6/build
    cmake ../source/ -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/ffmpeg_/
    make -j $NUM_CPU_CORES
    make install
    cd ~ && rm -rf x265*
    
    cd ~/ffmpeg-7.0/
    ./configure --disable-zlib --disable-doc --prefix=$HOME/ffmpeg_/ --extra-cflags="-I$HOME/ffmpeg_/include" --extra-ldflags="-L$HOME/ffmpeg_/lib -ldl" --bindir="$HOME/ffmpeg_/bin" --pkg-config-flags="--static" --enable-gpl --enable-libx264 --enable-libx265
    make -j $NUM_CPU_CORES
    echo $? > ~/install-exit-status
    make install
    cd ~ && rm -rf ffmpeg-7.0*
    
    unzip -o vbench-02.zip
fi

echo 3 > /proc/sys/vm/drop_caches
echo always > /sys/kernel/mm/transparent_hugepage/enabled

export PATH=$HOME/ffmpeg_/bin:$PATH
export LD_LIBRARY_PATH=$HOME/ffmpeg_/lib/:$LD_LIBRARY_PATH

cd $HOME/scripts/topdown
python3 perf_metrics.py -C 1 --command 'numactl --physcpubind 1 --membind 0 ffmpeg -hwaccel auto -y -hide_banner -i $HOME/vbench/videos/crf0/new_chicken_3840x2160_30.mkv  \
-c:v libx265 -x265-params "frame-threads=1:no-wpp=1" -preset medium -vtag hvc1 -loglevel info -f mp4 output_file_0.mp4'
echo $? >> ~/test-exit-status
cd -

VBENCH_ROOT=$HOME/vbench/ python3 vbench/code/post-silicon-test.py --output_dir=/tmp --encoder=libx265 --socket_id='1' --ffmpeg_dir=$HOME/ffmpeg_/bin/ --mode=total   > total.log   2>&1
echo $? > ~/test-exit-status
VBENCH_ROOT=$HOME/vbench/ python3 vbench/code/post-silicon-test.py --output_dir=/tmp --encoder=libx265 --socket_id='1' --ffmpeg_dir=$HOME/ffmpeg_/bin/ --mode=scaling > scaling.log 2>&1
echo $? >> ~/test-exit-status
VBENCH_ROOT=$HOME/vbench/ python3 vbench/code/post-silicon-test.py --output_dir=/tmp --encoder=libx265 --socket_id='0' --ffmpeg_dir=$HOME/ffmpeg_/bin/ --mode=power > power0.log 2>&1
echo $? >> ~/test-exit-status
VBENCH_ROOT=$HOME/vbench/ python3 vbench/code/post-silicon-test.py --output_dir=/tmp --encoder=libx265 --socket_id='1' --ffmpeg_dir=$HOME/ffmpeg_/bin/ --mode=power > power1.log 2>&1
echo $? >> ~/test-exit-status
VBENCH_ROOT=$HOME/vbench/ python3 vbench/code/post-silicon-test.py --output_dir=/tmp --encoder=libx265 --socket_id='0,1' --ffmpeg_dir=$HOME/ffmpeg_/bin/ --mode=power > power01.log 2>&1
echo $? >> ~/test-exit-status
