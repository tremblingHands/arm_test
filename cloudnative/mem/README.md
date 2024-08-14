# 内存测试工具

内存时延benchmark: lmbench

内存带宽benchmark：stream

## 使用方法

### 虚拟机环境测试

``sh run.sh --virt``

单核测试绑定CPU8，多核测试绑定CPU[0-31]

### 物理机环境测试

``sh run.sh --host``

Intel上，单核测试绑定CPU16，多核测试绑定CPU[0,64,2,66,4,68,6,70,8,72,10,74,12,76,14,78,16,80,18,82,20,84,22,86,24,88,26,90,28,92,30,94]

AMD上，单核测试绑定CPU12，多核测试绑定CPU[0-15,128-143]

aarch64上，单核测试绑定CPU16，多核测试绑定CPU[0-31]

## 工具帮助

sh run.sh --help

``` console
The OS Platform is CentOS Stream release 8
The Architecture is x86_64
CPU Vendor is Intel
Usage: run.sh [options]

Options:
  -c, --cpu <cpu>            Specify the CPU core for single-core memory testing (default: 8)
  -mc, --multicpu <range>    Specify the CPU core list for multi-core memory testing (default: 0-31)
  --host                     Indicates that the test is running on a host environment
                             Auto configure test CPU cores
  --virt                     Indicates that the test is running on a virtual machine
                             Auto configure test CPU cores
                             Sets single-core=8 and multi-core=[0-31]
  -r, --round <rounds>       Specify the number of memory test rounds (default: 5)
  -o, --output <result_dir>  Specify the data results path (default: results)
  -h, --help                 Show this help message and exit
```
