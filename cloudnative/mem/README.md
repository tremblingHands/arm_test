# 内存测试工具

内存时延benchmark: lmbench

内存带宽benchmark：stream

## 使用方法

### 虚拟机环境测试

``sh run.sh --virt``

单核测试绑定CPU8，多核测试绑定CPU[0-31]

### 物理机环境测试

``sh run.sh --host``

x86-64上，单核测试绑定CPU12，多核测试绑定CPU[0-15,128-143]

aarch64上，单核测试绑定CPU16，多核测试绑定CPU[0-31]

## 工具帮助

sh run.sh --help

``` console
The OS Platform is CentOS Linux release 7.9.2009 (AltArch)
The Architecture is aarch64
Usage: run.sh [options]

Options:
  -c, --cpu <cpu>            Specify the CPU core for single-core memory testing (default: 12)
  -mc, --multicpu <range>    Specify the CPU core list for multi-core memory testing (default: 0-31)
  --host                     Indicates that the test is running on a host environment
                             Auto configure test CPU cores
                             x86_64: single-core=12, multi-core=[0-15,128-143]
                             aarch64: single-core=16, multi-core=[0-31]
  --virt                     Indicates that the test is running on a virtual machine
                             Auto configure test CPU cores
                             Sets single-core=8 and multi-core=[0-31]
  -r, --round <rounds>       Specify the number of memory test rounds (default: 5)
  -o, --output <result_dir>  Specify the data results path (default: results)
  -h, --help                 Show this help message and exit
```


