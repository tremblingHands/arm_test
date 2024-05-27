package cn.hjmicro;

import cn.hjmicro.utils.JDBCUtil;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.SQLException;
import java.text.MessageFormat;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.stream.Stream;

import static cn.hjmicro.utils.SystemInfo.getIPAddress;
import static cn.hjmicro.utils.SystemInfo.getSystemArchitecture;

public class ResultHandler {

    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("please input data dir");
        }
        String ip = getIPAddress();
        String aarch = getSystemArchitecture();
        LocalDateTime nowDateTime = LocalDateTime.now();
        MessageFormat sqlFormat = new MessageFormat("INSERT INTO {0} (ip,aarch,task_name,query,used_time,dt) VALUES (?,?,?,?,?,?)");
        String dataDir = args[0];
        try {
            File dir = new File(dataDir);
            File[] files = dir.listFiles();
            assert files != null;
            for (File file : files) {
                String taskName = file.getName(); // 1socket-1task-1t
                File[] subTasks = file.listFiles();
                assert subTasks != null;
                for (File subTask : subTasks) {
                    String subTaskName = subTask.getName(); //tt-tpch_parquet_report2,terasort_report.txt tt-tpch_parquet_report.txt
                    List<ArrayList<Object>> paramList = new ArrayList<>();
                    if (subTaskName.contains("txt") && subTaskName.contains("tt")) {
                        ArrayList<Object> valueList = new ArrayList<>();
                        valueList.add(ip);
                        valueList.add(aarch);
                        valueList.add(taskName);
                        String name = "throughout-total";
                        Path p = Paths.get(subTask.getAbsolutePath());
                        List<String> lines = Files.readAllLines(p);
                        String usedTime = lines.get(0);
                        float t = Float.parseFloat(usedTime);
                        valueList.add(name);
                        valueList.add(t);
                        valueList.add(nowDateTime);
                        paramList.add(valueList);
                    } else {
                        if (subTaskName.contains("tpc")) {
                            File[] datafiles = subTask.listFiles();
                            //todo 解析文件
                            assert datafiles != null;
                            for (File df : datafiles) {
                                if (df.getName().contains("csv")) {
                                    Path p = Paths.get(df.getAbsolutePath());
                                    List<String> lines = Files.readAllLines(p);
                                    for (String line : lines) {
                                        String[] fields = line.split(",");
                                        if (fields.length < 2 || fields[0].contains("Name")) continue;
                                        ArrayList<Object> valueList = new ArrayList<>();
                                        valueList.add(ip);
                                        valueList.add(aarch);
                                        valueList.add(taskName);
                                        String name = fields[0];
                                        if (subTaskName.contains("tt") && subTaskName.contains("report1")) {
                                            name += "_tt1";
                                        }
                                        if (subTaskName.contains("tt") && subTaskName.contains("report2")) {
                                            name += "_tt2";
                                        }
                                        valueList.add(name);
                                        float runtime = Float.parseFloat(fields[1].trim());
                                        valueList.add(runtime);
                                        valueList.add(nowDateTime);
                                        paramList.add(valueList);
                                    }
                                }
                            }
                        } else {
                            File[] txtfiles = subTask.listFiles();
                            assert txtfiles != null;
                            for (File txtfile : txtfiles) {
                                if (txtfile.length() > 1) {
                                    Path p = Paths.get(txtfile.getAbsolutePath());
                                    List<String> lines = Files.readAllLines(p);
                                    String usedTime = lines.get(0);
                                    usedTime = usedTime.replaceAll("\\[", "").replaceAll("\\]", "").replaceAll(",", "").trim();
                                    float t = Float.parseFloat(usedTime);
                                    String name = "terasort";
                                    if (subTaskName.contains("tt")) {
                                        name = "throughout-total";
                                    }
                                    ArrayList<Object> valueList = new ArrayList<>();
                                    valueList.add(ip);
                                    valueList.add(aarch);
                                    valueList.add(taskName);
                                    valueList.add(name);
                                    valueList.add(t);
                                    valueList.add(nowDateTime);
                                    paramList.add(valueList);
                                }
                            }
                        }
                    }
                    if (subTaskName.contains("tpch_parquet_report")) {
                        try {
                            String[] arguments = {"tpch"};
                            String executeSql = sqlFormat.format(arguments);
                            JDBCUtil.executeBatch(executeSql, paramList);
                        } catch (SQLException throwables) {
                            throwables.printStackTrace();
                        }
                    }
                    if (subTaskName.contains("tpcds_parquet_report")) {
                        try {
                            String[] arguments = {"tpcds"};
                            String executeSql = sqlFormat.format(arguments);
                            JDBCUtil.executeBatch(executeSql, paramList);
                        } catch (SQLException throwables) {
                            throwables.printStackTrace();
                        }
                    }
                    if (subTaskName.contains("terasort")) {
                        try {
                            String[] arguments = {"terasort"};
                            String executeSql = sqlFormat.format(arguments);
                            JDBCUtil.executeBatch(executeSql, paramList);
                        } catch (SQLException throwables) {
                            throwables.printStackTrace();
                        }
                    }
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

//do something with file    }
}
