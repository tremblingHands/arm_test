package cn.hjmicro.utils;

import javax.management.ObjectName;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.lang.management.ManagementFactory;
import java.lang.management.OperatingSystemMXBean;

public class SystemInfo {
    // 获取当前主机的 IP 地址
    public static String getIPAddress() {
        try {
            InetAddress localhost = InetAddress.getLocalHost();
            return localhost.getHostAddress();
        } catch (UnknownHostException e) {
            e.printStackTrace();
            return null;
        }
    }

    // 获取系统架构
    public static String getSystemArchitecture() {
        return System.getProperty("os.arch");
    }

    public static String getCpuModel() {
        OperatingSystemMXBean os = ManagementFactory.getOperatingSystemMXBean();
        return os.getArch();
    }


    public static void main(String[] args) {
        System.out.println("当前主机的 IP 地址：" + getIPAddress());
        System.out.println("系统架构：" + getCpuModel());
    }
}
