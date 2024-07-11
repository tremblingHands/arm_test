import matplotlib.pyplot as plt
import numpy as np
import os
import sys

def plot_lines_from_directory(directory_path, ylabel, title):
    file_paths = [os.path.join(directory_path, file) for file in os.listdir(directory_path) if os.path.isfile(os.path.join(directory_path, file))]

    plt.style.use('seaborn-whitegrid')
    plt.figure(figsize=(12.5, 7.5), dpi=240)
    plt.subplots_adjust(top=0.95)

    hex_colors = ['#FF0000', '#FFA500', '#FFFF00', '#008000', '#0000FF', '#800080', '#FF00FF', 
    '#008080', '#FF1493', '#00FA9A', '#8A2BE2', '#FFD700', '#32CD32', '#00CED1', '#FF4500',
    '#9400D3', '#FF6347', '#40E0D0', '#7B68EE', '#00FF7F', '#DC143C', '#ADFF2F', '#1E90FF',
    '#FF69B4', '#FF8C00']
    for i, file_path in enumerate(file_paths):
        with open(file_path, 'r') as file:
            data = [float(line.strip()) for line in file.readlines()]
            data_index = [i+1 for i in (np.arange(len(data)))]

        file_name = os.path.splitext(os.path.basename(file_path))[0]
        plt.plot(data_index, data, label=file_name, color=hex_colors[i])

    plt.title(title)
    plt.xlabel('Test Sequence', fontsize=8)
    plt.ylabel(ylabel, fontsize=8)

    plt.legend(loc='upper left', bbox_to_anchor=(1, 1.05), fontsize=5.5)
    plt.xlim(1, len(data))
    plt.xticks(data_index, fontsize=7)
    plt.yticks(fontsize=7)
    output_file= ylabel + "-" + title
    plt.savefig(output_file, bbox_inches='tight', dpi=300)

directory_path = sys.argv[1]
ylabel = sys.argv[2]
title = sys.argv[3]
plot_lines_from_directory(directory_path, ylabel, title)
