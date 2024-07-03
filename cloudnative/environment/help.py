import sys

def x86_write_numbers_to_file(n, s1, s2, filename='output.xml'):
    with open(filename, 'w') as file:
        for i in range(n):
            j = int(i/2)
            if i % 2 == 0:
                file.write(f"    <vcpupin vcpu='{i}' cpuset='{s1 + j}'/>\n")
            else:
                file.write(f"    <vcpupin vcpu='{i}' cpuset='{s2 + j}'/>\n")

def arm_write_numbers_to_file(n, s1, filename='output.xml'):
    with open(filename, 'w') as file:
        for i in range(n):
            file.write(f"    <vcpupin vcpu='{i}' cpuset='{s1 + i}'/>\n")


def generate_vm_cpu_list(cpu_str, start_index, vcpu_num, all_cpu_num):
    cpu_str_array=cpu_str.split(',')
    if vcpu_num % 2 != 0:
        print(f"vcpu number is not even number")
        sys.exit(1)
    if len(cpu_str_array) == 1:
        tmp_array=cpu_str_array[0].split('-')
        vcpu_array = []
        start_cpu = int(tmp_array[0]) + start_index
        for i in range(vcpu_num):
            vcpu_array.append(start_cpu+i)
        vcpu_list_str = ' '.join(map(str, vcpu_array))
        isolcpu_str = f"{vcpu_array[0]}-{vcpu_array[vcpu_num-1]}"
        restcpu_str = f"0-{vcpu_array[0]-1}"
        if vcpu_array[vcpu_num - 1] < all_cpu_num-1:
            restcpu_str = f"{restcpu_str},{vcpu_array[vcpu_num-1]+1}-{all_cpu_num-1}"
        print(f"VM_CPU_LIST= {vcpu_list_str}#")
        print(f"VM_CPU_LIST_FIRST_START= none#")
        print(f"VM_CPU_LIST_SECOND_START= none#")
        print(f"ISOLATION_CPU_CMDLINE= isolcpus={isolcpu_str} rcu_nocbs={isolcpu_str} kthread_cpus={restcpu_str} irqaffinity={restcpu_str}#")
    elif len(cpu_str_array) == 2:
        tmp_array_0=cpu_str_array[0].split('-')
        tmp_array_1=cpu_str_array[1].split('-')
        vcpu_array = []
        first_start_cpu = int(tmp_array_0[0]) + start_index
        second_start_cpu = int(tmp_array_1[0]) + start_index
        half_vcpu_num = int(vcpu_num/2)
        for i in range(half_vcpu_num):
            vcpu_array.append(first_start_cpu+i)
            vcpu_array.append(second_start_cpu+i)
        vcpu_list_str = ' '.join(map(str, vcpu_array))
        isolcpu_str = f"{vcpu_array[0]}-{vcpu_array[vcpu_num-2]},{vcpu_array[1]}-{vcpu_array[vcpu_num-1]}"
        restcpu_str = f"0-{vcpu_array[0]-1},{vcpu_array[vcpu_num-2]+1}-{vcpu_array[1]-1}"
        if vcpu_array[vcpu_num - 1] < all_cpu_num-1:
            restcpu_str = f"{restcpu_str},{vcpu_array[vcpu_num-1]+1}-{all_cpu_num-1}"
        print(f"VM_CPU_LIST= {vcpu_list_str}#")
        print(f"VM_CPU_LIST_FIRST_START= {vcpu_array[0]}#")
        print(f"VM_CPU_LIST_SECOND_START= {vcpu_array[1]}#")
        print(f"ISOLATION_CPU_CMDLINE= isolcpus={isolcpu_str} rcu_nocbs={isolcpu_str} kthread_cpus={restcpu_str} irqaffinity={restcpu_str}#")



cpu_str = sys.argv[1]
start_index = int(sys.argv[2])
vcpu_num = int(sys.argv[3])
all_cpu_num = int(sys.argv[4])
generate_vm_cpu_list(cpu_str, start_index, vcpu_num, all_cpu_num)
