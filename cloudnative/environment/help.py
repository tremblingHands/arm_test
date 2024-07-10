import sys

def write_vm_cpu_tune(vcpu_list_second_start, io_pin_cpu, isolation_cmdline, vcpu_array, fio_start_index):
    filename='vm-cpu-list'
    vcpu_list_str = ' '.join(map(str, vcpu_array))
    with open(filename, 'w') as file:
        file.write(f'VM_CPU_LIST="{vcpu_list_str}"\n')
        file.write(f'VM_CPU_LIST_FIRST_START="{vcpu_array[0]}"\n')
        file.write(f'VM_CPU_LIST_SECOND_START="{vcpu_list_second_start}"\n')
        file.write(f'VM_EMU_PIN_CPU="{vcpu_array[0]-1}"\n')
        file.write(f'VM_IO_PIN_CPU="{io_pin_cpu}"\n')
        file.write(f'ISOLATION_CPU_CMDLINE="{isolation_cmdline}"\n')
        file.write('VM_CPU_TUNE="')
        for i, element in enumerate(vcpu_array):
            file.write(f"    <vcpupin vcpu='{i}' cpuset='{element}'/>\\n")
        file.write('"\n')
        file.write("\n\n")

        fio_end_index = fio_start_index + 8
        fio_host_cpu_list = vcpu_array[fio_start_index:fio_end_index]
        fio_host_cpu_list_str = ','.join(map(str, fio_host_cpu_list))

        fio_guest_cpu_list = []
        for i in range(8):
            fio_guest_cpu_list.append(start_index+i)
        fio_guest_cpu_list_str = ','.join(map(str, fio_guest_cpu_list))

        file.write(f'TEST_HOST_LIST1="{fio_host_cpu_list[0]}"\n')
        file.write(f'TEST_HOST_LIST8="{fio_host_cpu_list_str}"\n')
        file.write(f'TEST_GUEST_LIST1="{fio_guest_cpu_list[0]}"\n')
        file.write(f'TEST_GUEST_LIST8="{fio_guest_cpu_list_str}"\n')

        return

def generate_vm_cpu_list(cpu_str, start_index, vcpu_num, all_cpu_num, fio_start_index):
    cpu_str_array=cpu_str.split(',')
    vcpu_array = []
    if vcpu_num % 2 != 0:
        print(f"vcpu number is not even number")
        sys.exit(1)
    if len(cpu_str_array) == 1:
        tmp_array=cpu_str_array[0].split('-')
        start_cpu = int(tmp_array[0]) + start_index
        for i in range(vcpu_num):
            vcpu_array.append(start_cpu+i)

        vcpu_list_str = ' '.join(map(str, vcpu_array))
        isolcpu_str = f"{vcpu_array[0]}-{vcpu_array[vcpu_num-1]}"
        restcpu_str = f"0-{vcpu_array[0]-1}"
        if vcpu_array[vcpu_num - 1] < all_cpu_num-1:
            restcpu_str = f"{restcpu_str},{vcpu_array[vcpu_num-1]+1}-{all_cpu_num-1}"
        isolation_cmdline_str = f"isolcpus={isolcpu_str} rcu_nocbs={isolcpu_str} kthread_cpus={restcpu_str} irqaffinity={restcpu_str}"

        write_vm_cpu_tune("none", vcpu_array[0]-2, isolation_cmdline_str, vcpu_array, fio_start_index)

    elif len(cpu_str_array) == 2:
        tmp_array_0=cpu_str_array[0].split('-')
        tmp_array_1=cpu_str_array[1].split('-')
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
        isolation_cmdline_str = f"isolcpus={isolcpu_str} rcu_nocbs={isolcpu_str} kthread_cpus={restcpu_str} irqaffinity={restcpu_str}"

        write_vm_cpu_tune(vcpu_array[1], vcpu_array[1]-1, isolation_cmdline_str, vcpu_array, fio_start_index)
    return

cpu_str = sys.argv[1]
start_index = int(sys.argv[2])
vcpu_num = int(sys.argv[3])
all_cpu_num = int(sys.argv[4])
fio_start_index = int(sys.argv[5])
generate_vm_cpu_list(cpu_str, start_index, vcpu_num, all_cpu_num, fio_start_index)
