import argparse
import os
import re
import subprocess
import csv
import time
import sys
import psutil
import math
from collections import defaultdict
from multiprocessing import Process, Queue, Manager

def get_power_consumption():
    """Get current power consumption using ipmitool"""
    try:
        result = subprocess.run(
            ["ipmitool", "sdr", "elist"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        output = result.stdout
        power_lines = [line for line in output.splitlines() if "Pwr Consumption" in line or "Total_Power" in line]
        if power_lines:
            power_value = re.search(r"\|\s*([\d.]+)\s*Watts", power_lines[0])
            if power_value:
                return float(power_value.group(1))
        print("No power consumption data found in the output.")
    except subprocess.CalledProcessError as e:
        print(f"Failed to get power consumption: {e.stderr}")
    except Exception as e:
        print(f"An error occurred while getting power consumption: {e}")
    return None

def monitor_power_consumption(pids, power_data_queue, interval=2):
    try:
        print("Starting power consumption monitoring...")
        
        while True:
            # Check if any process is still alive using PIDs
            alive_processes = [pid for pid in pids if psutil.pid_exists(pid)]
            if not alive_processes:  # Exit if no processes are alive
                break
            
            print(f"Active PIDs: {alive_processes}")  # Print current active PIDs
            power = get_power_consumption()  # Fetch current power consumption

            if power is not None:
                power_data_queue.put(power)  # Append valid power data
                print(f"Recorded power consumption: {power:.2f} Watts")
            else:
                print("Failed to get power consumption data.")

            time.sleep(interval)  # Wait for the specified interval
    except Exception as e:
        print(f"An error occurred in monitor_power_consumption: {e}")
    finally:
        print("Power consumption monitoring stopped.")

def parse_lscpu_output():
    # Execute the `lscpu -p=CPU,Core,Socket,Node` command and capture its output
    process = subprocess.Popen(['lscpu', '-p=CPU,Core,Socket,Node'],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,
                                universal_newlines=True)
    stdout, stderr = process.communicate()

    # Check if the command executed successfully
    if process.returncode != 0:
        raise Exception("Failed to execute lscpu: " + stderr)

    # Parse the output
    cores_info = []
    for line in stdout.strip().split('\n'):
        if line.startswith('#') or not line.strip():
            continue  # Skip comment lines and empty lines
        parts = line.split(',')
        if len(parts) < 4:
            continue  # Skip lines with incorrect format
        cpu_id, core_id, socket_id, node_id = parts
        cores_info.append((int(cpu_id), int(socket_id), int(node_id)))
    return cores_info

def group_by_socket(cpu_info):
    # Use defaultdict to automatically create lists
    socket_groups = defaultdict(list)
    for cpu_id, socket_id, node_id in cpu_info:
        # Group core information by Socket ID
        socket_groups[socket_id].append((cpu_id, node_id))
    return socket_groups

def write_to_csv(filename, header, data):
    """Write data to a CSV file"""
    try:
        with open(filename, "a", newline="") as csvfile:
            writer = csv.writer(csvfile)
            if csvfile.tell() == 0:
                writer.writerow(header)
            formatted_data = [str(round(float(item), 2)) if isinstance(item, (int, float)) else item for item in data]
            writer.writerow(formatted_data)
    except IOError as e:
        print(f"Error writing to CSV file {filename}: {e}")

def run_ffmpeg_on_cpu(ffmpeg, encoder, node_id, cpu, queue, input_file, output_file):
    try:
        output_file = f"{output_file}_{cpu}.mp4"
        cmd = [
            'numactl', '--physcpubind', str(cpu), '--membind', str(node_id),
            ffmpeg, '-hwaccel', 'auto', '-y', '-hide_banner', '-i', input_file,
            '-c:v', encoder, '-x265-params', 'frame-threads=1:no-wpp=1:pools=,',
            '-preset', 'medium', '-vtag', 'hvc1',
            '-loglevel', 'info', '-f', 'mp4', output_file
        ]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        fps_match = re.search(r'\((\d+\.?\d*) fps\)', result.stdout.decode('utf-8'))
        if fps_match:
            fps_value = float(fps_match.group(1))
            queue.put(fps_value)
        else:
            print("FPS value not found in the output.")

        if os.path.exists(output_file):
            os.remove(output_file)
            print(f"Deleted file: {output_file}")
        else:
            print(f"File not found: {output_file}")
    except Exception as e:
        print(f"An error occurred: {e}")

def parse_socket_ids(socket_id_str):
    # Parse the socket ID string into a list of integers
    return [int(s) for s in socket_id_str.split(',')]

def start_total_processes(args, cores_info, socket_groups):
    # Construct the path to the video directory
    video_dir = os.path.join(os.getenv("VBENCH_ROOT"), "videos/crf0")
    # Ensure the video directory is valid and has the necessary permissions
    assert os.path.isdir(video_dir) and os.access(video_dir, os.R_OK) and os.access(video_dir, os.X_OK), \
        "video_dir: {} is not a valid video directory".format(video_dir)
    # Ensure the output directory is writable
    assert os.path.isdir(args.output_dir) and os.access(args.output_dir, os.W_OK), \
        "Output directory {} is non writable".format(args.output_dir)
    # Ensure the output and video input directories are not the same
    assert os.path.abspath(video_dir) != os.path.abspath(args.output_dir), \
        "Output and video input directory cannot be the same"

    # Find all video files in the video directory with supported extensions
    input_files = [x for x in os.listdir(video_dir) if
                   re.search("mkv$", x) or re.search("y4m$", x) or re.search("mp4$", x)]
    # Ensure there are valid video files found
    assert len(input_files) > 0, "Cannot find valid video files in args.video_dir: {}".format(args.video_dir)

    # Initialize a list to keep track of processes
    processes = []
    # Determine how many times to repeat the input files based on the number of cores
    repeat_times = len(cores_info) // 16
    # Extend the list of input files accordingly
    extended_input_files = input_files * repeat_times

    # Create a queue for each test
    queue = Queue()
    # Iterate over each socket ID provided in the arguments
    for socket_id in parse_socket_ids(args.socket_id):
        # Get the items for the current socket ID from the socket_groups dictionary
        items = socket_groups.get(socket_id, [])
        if not items:
            print(f"No CPU information found for socket ID {socket_id}.")
            continue
        # Iterate over each CPU and node ID pair in the current socket's items
        for cpu, node_id in items:
            # Determine the name of the video file to process based on the CPU ID
            v_name = extended_input_files[cpu]
            # Construct the full path to the input file
            input_file = os.path.join(video_dir, v_name)
            # Construct the full path to the output file, assuming it will be saved in the output directory
            output_file = os.path.join(args.output_dir, v_name)
            # Start a process to run ffmpeg on the current CPU with the specified parameters
            p = Process(target=run_ffmpeg_on_cpu, args=(args.ffmpeg, args.encoder, node_id, cpu, queue, input_file, output_file))
            p.start()
            # Add the process to the list of processes
            processes.append(p)

    # Wait for all processes to complete
    for p in processes:
        p.join()

    # Collect results from the queue
    results = []
    while not queue.empty():
        result = queue.get()
        results.append(result)

    # Print individual results
    for result in results:
        print(f"{result}")

    # Calculate and print the total sum of FPS
    total_sum = sum(results)
    write_to_csv("total_fps_results.csv", ["Total FPS"], [total_sum])
    print(f"The total FPS is: {total_sum}")

def start_scaling_processes(args, cores_info, socket_groups):
    # Construct the path to the video directory for scaling processes
    video_dir = os.path.join(os.getenv("VBENCH_ROOT"), "videos/socket-scaling")
    # Ensure the video directory is valid and has the necessary permissions
    assert os.path.isdir(video_dir) and os.access(video_dir, os.R_OK) and os.access(video_dir, os.X_OK), \
        "video_dir: {} is not a valid video directory".format(video_dir)
    # Ensure the output directory is writable
    assert os.path.isdir(args.output_dir) and os.access(args.output_dir, os.W_OK), \
        "Output directory {} is non writable".format(args.output_dir)
    # Ensure the output and video input directories are not the same
    assert os.path.abspath(video_dir) != os.path.abspath(args.output_dir), \
        "Output and video input directory cannot be the same"

    # Find all video files in the video directory with supported extensions
    input_files = [x for x in os.listdir(video_dir) if
                   re.search("mkv$", x) or re.search("y4m$", x) or re.search("mp4$", x)]
    # Ensure there are valid video files found
    assert len(input_files) > 0, "Cannot find valid video files in args.video_dir: {}".format(args.video_dir)
    
    # Iterate over each socket ID provided in the arguments
    for socket_id in parse_socket_ids(args.socket_id):
        # Get the items for the current socket ID from the socket_groups dictionary
        items = socket_groups.get(socket_id, [])
        if not items:
            print(f"No CPU information found for socket ID {socket_id}.")
            continue
        
        # Determine the maximum number of cores available for the current socket
        max_cores = len(items)

        # Start with 1 in the list
        cores_numbers_to_test = [1]
        
        # Then add core numbers starting from 8, increasing by 8 each time, up to the maximum number of cores available
        for i in range(1, (max_cores // 8) + 1):
            core_number = 8 * i
            if core_number <= max_cores:
                cores_numbers_to_test.append(core_number)
        
        # Ensure the list starts with 1 and the elements are in ascending order
        cores_numbers_to_test.sort()

        # For each input file, perform tests with different numbers of cores
        for input_file in input_files:
            # Construct the full path to the input file
            input_path = os.path.join(video_dir, input_file)
            # Iterate over the list of core numbers to test
            for cores_number in cores_numbers_to_test:
                print(f"Testing {input_file} with {cores_number} cores...")    

                # Create a queue for collecting results of this test
                queue = Queue()
                # Initialize a list to keep track of processes for this test
                processes = []
                # Distribute cores in order for the current test
                for cpu, node_id in items:
                    # Stop if the desired number of cores for this test has been reached
                    if cores_number <= len(processes):  
                       break

                    # Construct the output file name with the current core number
                    output_file = f"{os.path.splitext(input_file)[0]}_{cores_number}_{socket_id}_{cpu}.mp4"
                    # Construct the full path to the output file for this test
                    output_path = os.path.join(args.output_dir, output_file)

                    # Start a process to run ffmpeg with the current core number and other specified parameters
                    p = Process(target=run_ffmpeg_on_cpu, args=(args.ffmpeg, args.encoder, node_id, cpu, queue, input_path, output_path))
                    p.start()
                    # Add the process to the list of processes for this test
                    processes.append(p)

                # Wait for all processes of this test to complete
                for p in processes:
                      p.join()

                # Collect results from the queue for this test
                results = []
                while not queue.empty():
                    result = queue.get()
                    results.append(result)

                # Print the results for this test
                total_fps = sum(results)
                write_to_csv("scaling_results.csv", ["Input File", "Cores Number", "Total FPS"], [input_file, cores_number, total_fps])
                print(f"The total FPS for {input_file} with {cores_number} cores is: {total_fps}\n")

def get_all_items(args, socket_groups):
    socket_ids = parse_socket_ids(args.socket_id)
    
    all_items = []
    for socket_id in socket_ids:
        items = socket_groups.get(socket_id, [])
        if items:
            all_items.extend(items)
        else:
            print(f"No CPU information found for socket ID {socket_id}.")

    return all_items


def start_power_processes(args, cores_info, socket_groups):
    """Start processes for power consumption test"""
    video_dir = os.path.join(os.getenv("VBENCH_ROOT"), "videos/socket-scaling")
    assert os.path.isdir(video_dir) and os.access(video_dir, os.R_OK) and os.access(video_dir, os.X_OK), \
        f"video_dir: {video_dir} is not a valid video directory"
    assert os.path.isdir(args.output_dir) and os.access(args.output_dir, os.W_OK), \
        f"Output directory {args.output_dir} is not writable"
    assert os.path.abspath(video_dir) != os.path.abspath(args.output_dir), \
        "Output and video input directory cannot be the same"

    input_files = [x for x in os.listdir(video_dir) if re.search(r'\.mkv$|\.y4m$|\.mp4$', x)]
    assert len(input_files) > 0, f"Cannot find valid video files in args.video_dir: {args.video_dir}"

    items = get_all_items(args, socket_groups)
    cores = [cpu for cpu, node_id in items]

    try:
        manager = Manager()
        power_data_queue = manager.Queue()


        for input_file in sorted(input_files):
            input_path = os.path.join(video_dir, input_file)

            queue = Queue()
            processes = []

            for cpu, node_id in items:
                print(f"Starting video encoding for {input_file} on socket {node_id} using core {cpu}...")

                output_file = f"{os.path.splitext(input_file)[0]}_{node_id}_{cpu}.mp4"
                output_path = os.path.join(args.output_dir, output_file)

                p = Process(target=run_ffmpeg_on_cpu, args=(args.ffmpeg, args.encoder, node_id, cpu, queue, input_path, output_path,))
                p.start()
                processes.append(p)

            # Extract the PIDs from the processes
            pids = [p.pid for p in processes]

            # Start the monitoring thread
            monitor_thread = Process(target=monitor_power_consumption, args=(pids, power_data_queue))
            monitor_thread.start()

            for p in processes:
                p.join()

            monitor_thread.terminate()
            monitor_thread.join()

            # Collect results from the queue
            results = []
            while not queue.empty():
                result = queue.get()
                results.append(result)

            # Print individual results
            for result in results:
                print(f"{result}")

            # Calculate and print the total sum of FPS
            total_sum = sum(results)
            
            power_consumption_data = [power_data_queue.get() for _ in range(power_data_queue.qsize())]

            avg_power = sum(power_consumption_data) / len(power_consumption_data) if power_consumption_data else 0.0
            print(f"Total Power Consumption for {input_file} on socket {args.socket_id}: {avg_power:.2f} Watts")

            if math.isclose(number, 0.0, rel_tol=1e-9, abs_tol=0.0):
                write_to_csv('power_scaling_results.csv', ['Input File', 'Socket ID', 'Average Power (Watts)', "Total FPS", "Performance(FPS/Watts)"], [input_file, args.socket_id, avg_power, total_sum, 0.0])
            else:                
                write_to_csv('power_scaling_results.csv', ['Input File', 'Socket ID', 'Average Power (Watts)', "Total FPS", "Performance(FPS/Watts)"], [input_file, args.socket_id, avg_power, total_sum, total_sum / avg_power])
    except ZeroDivisionError as e:
            print(f"Error: {e} - Check if the average power is zero.")

def main():
    """Main function to parse arguments and start the appropriate test"""
    if "VBENCH_ROOT" not in os.environ:
        print("Error: VBENCH_ROOT environment variable is not set.")
        sys.exit(1)

    parser = argparse.ArgumentParser()
    parser.add_argument("--output_dir", type=str, default="/tmp", help="Where to save transcoded videos")
    parser.add_argument("--encoder", type=str, default="libx265", help="FFmpeg encoder to use")
    parser.add_argument("--ffmpeg_dir", type=str, help="Path to ffmpeg installation folder")
    parser.add_argument("--socket_id", type=str, default="0", help="Comma-separated list of sockets to use, e.g., '0,1'")
    parser.add_argument("--mode", type=str, choices=["total", "scaling", "power"], help="Mode to run: 'total' for all cores, 'scaling' for scaling tests, 'power' for power monitoring")

    args = parser.parse_args()

    args.ffmpeg = os.path.join(args.ffmpeg_dir, "ffmpeg")
    assert os.path.isfile(args.ffmpeg) and os.access(args.ffmpeg, os.X_OK), \
        f"Cannot find a ffmpeg executable in args.ffmpeg_dir: {args.ffmpeg_dir}"

    args.socket_ids = parse_socket_ids(args.socket_id)

    cores_info = parse_lscpu_output()
    socket_groups = group_by_socket(cores_info)

    if args.mode == "total":
        start_total_processes(args, cores_info, socket_groups)
    elif args.mode == "scaling":
        start_scaling_processes(args, cores_info, socket_groups)
    elif args.mode == "power":
        start_power_processes(args, cores_info, socket_groups)
    else:
        print("Invalid mode specified.")

if __name__ == "__main__":
    main()
