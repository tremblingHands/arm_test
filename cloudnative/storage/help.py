# coding:utf-8 
import sys
import numpy as np

def process_data(filename, start_index, data_size):
    #读取文件中的数据并转换为浮点数列表
    with open(filename, 'r') as file:
        data = [float(line.strip()) for line in file]
    data = data[int(start_index):int(start_index)+int(data_size)]
    # 计算最小二乘法的线性回归方程
    data_index = [i+1 for i in (np.arange(len(data)))]
    slope, intercept = np.polyfit(data_index, data, 1)
    slope = round(slope, 2)
    intercept = round(intercept, 2)

    # 使用线性回归方程计算每个数的预测值 
    predicted_values = [round(slope*(i+1) + intercept, 3) for i in range(len(data))] 
 
    # 计算原始数据最大值和最小值的差值，判断是否小于原始数据平均值的20%
    original_max = max(data)
    original_min = min(data)
    original_range = original_max - original_min 
    original_average = np.mean(data)
    original_average = round(original_average, 2)
    
    # 计算预测数据最大值和最小值的差值，判断是否小于原始数据平均值的10%
    predicted_max = max(predicted_values)
    predicted_min = min(predicted_values)
    predicted_range = predicted_max - predicted_min
  
    if (original_range < original_average * 0.2) and (predicted_range < original_average * 0.1):
        print("true="+str(original_average))
    else:
        print("false="+str(original_average))
    return

filename = sys.argv[1]
start_index = sys.argv[2]
data_size = sys.argv[3]
process_data(filename, start_index, data_size)
