package cn.hjmicro.utils;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;

public class JDBCUtil {
    private static final String PROPERTIES_FILE = "config.properties";

    // 获取数据库连接
    public static Connection getConnection() {
        Properties props = new Properties();
        try{
            Class.forName("com.mysql.cj.jdbc.Driver");
            InputStream in = JDBCUtil.class.getClassLoader().getResourceAsStream("config.properties");
            props.load(in);
            return DriverManager.getConnection(props.getProperty("db.url"),
                    props.getProperty("db.username"),
                    props.getProperty("db.password"));
        } catch (IOException | SQLException | ClassNotFoundException e) {
            e.printStackTrace();
            return null;
        }
    }


    // 关闭数据库连接
    public static void closeConnection(Connection conn) {
        try {
            if (conn != null) {
                conn.close();
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    // 执行查询操作
    public static ResultSet executeQuery(Connection conn, String sql, Object... params) {
        ResultSet rs = null;
        try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
            // 设置参数
            for (int i = 0; i < params.length; i++) {
                pstmt.setObject(i + 1, params[i]);
            }
            rs = pstmt.executeQuery();
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return rs;
    }

    // 执行更新操作（插入、更新、删除）
    public static int executeUpdate(Connection conn, String sql, Object... params) {
        int rowsAffected = 0;
        try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
            // 设置参数
            for (int i = 0; i < params.length; i++) {
                pstmt.setObject(i + 1, params[i]);
            }
            rowsAffected = pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return rowsAffected;
    }

    public static void executeBatch(String sql, List<ArrayList<Object>> parameterList) throws SQLException {
        Connection connection = getConnection();
        try {
            connection.setAutoCommit(false);
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                for(ArrayList<Object>  valueList: parameterList){
                    for (int i = 0; i < valueList.size(); i++) {
                        statement.setObject(i+1,valueList.get(i));
                    }
                    statement.addBatch();
                }
                statement.executeBatch();
                statement.clearParameters();
            }
            connection.commit();
        } catch (SQLException e) {
            connection.rollback();
            throw e;
        } finally {
            connection.setAutoCommit(true);
            connection.close();
        }
    }

    // 测试方法
    public static void main(String[] args) {
        Connection conn = null;
        try {
            // 获取数据库连接
            conn = JDBCUtil.getConnection();

            // 执行查询操作示例
            String querySql = "SELECT * FROM table_name WHERE condition = ?";
            ResultSet rs = JDBCUtil.executeQuery(conn, querySql, "value");
            while (rs.next()) {
                // 处理结果集
            }

            // 执行更新操作示例
            String updateSql = "UPDATE table_name SET column1 = ? WHERE condition = ?";
            int rowsAffected = JDBCUtil.executeUpdate(conn, updateSql, "new_value", "condition_value");
            System.out.println("影响的行数：" + rowsAffected);

            // 其他操作（插入、删除等）也可以类似处理

        } catch (SQLException e) {
            e.printStackTrace();
        } finally {
            // 关闭数据库连接
            JDBCUtil.closeConnection(conn);
        }
    }
}

