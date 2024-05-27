package cn.hjmicro.utils;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;

public class DateTimeUtil {

    /**
     * 格式化日期
     *
     * @param localDate 需要格式化的日期
     * @param format 格式化字符串，例如 "yyyy-MM-dd"
     * @return 格式化后的日期字符串
     */
    public static String formatDate(LocalDate localDate, String format) {
        if (localDate == null) {
            return null;
        }
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return localDate.format(formatter);
    }

    /**
     * 格式化时间
     *
     * @param localTime 需要格式化的日期
     * @param format 格式化字符串，例如 "HH:mm:ss"
     * @return 格式化后的时间字符串
     */
    public static String formatTime(LocalTime localTime, String format) {
        if (localTime == null) {
            return null;
        }
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return localTime.format(formatter);
    }

    /**
     * 格式化日期时间
     *
     * @param localDateTime 需要格式化的日期时间
     * @param format 格式化字符串，例如 "yyyy-MM-dd HH:mm:ss"
     * @return 格式化后的日期时间字符串
     */
    public static String formatDateTime(LocalDateTime localDateTime, String format) {
        if (localDateTime == null) {
            return null;
        }
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return localDateTime.format(formatter);
    }

    /**
     * 将日期字符串转换为 LocalDate 对象
     *
     * @param dateStr 日期字符串
     * @param format 格式化字符串，例如 "yyyy-MM-dd"
     * @return LocalDate 对象
     * @throws DateTimeParseException 解析异常
     */
    public static LocalDate parseDate(String dateStr, String format) throws DateTimeParseException {
        if (dateStr == null || dateStr.isEmpty()) {
            return null;
        }
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return LocalDate.parse(dateStr, formatter);
    }

    /**
     * 将时间字符串转换为 LocalTime 对象
     *
     * @param timeStr 时间字符串
     * @param format 格式化字符串，例如 "HH:mm:ss"
     * @return LocalTime 对象
     * @throws DateTimeParseException 解析异常
     */
    public static LocalTime parseTime(String timeStr, String format) throws DateTimeParseException {
        if (timeStr == null || timeStr.isEmpty()) {
            return null;
        }
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return LocalTime.parse(timeStr, formatter);
    }

    /**
     * 将日期时间字符串转换为 LocalDateTime 对象
     *
     * @param dateTimeStr 日期时间字符串
     * @param format 格式化字符串，例如 "yyyy-MM-dd HH:mm:ss"
     * @return LocalDateTime 对象
     * @throws DateTimeParseException 解析异常
     */
    public static LocalDateTime parseDateTime(String dateTimeStr, String format) throws DateTimeParseException {
        if (dateTimeStr == null || dateTimeStr.isEmpty()) {
            return null;
        }
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return LocalDateTime.parse(dateTimeStr, formatter);
    }

    /**
     * 获取当前日期
     *
     * @return 当前日期
     */
    public static LocalDate nowDate() {
        return LocalDate.now();
    }

    /**
     * 获取当前时间
     *
     * @return 当前时间
     */
    public static LocalTime nowTime() {
        return LocalTime.now();
    }

    /**
     * 获取当前日期时间
     *
     * @return 当前日期时间
     */
    public static LocalDateTime nowDateTime() {
        return LocalDateTime.now();
    }
    public static LocalDateTime nowDateTime(ZoneId zoneId) {
        return LocalDateTime.now(zoneId);
    }

    /**
     * 检查日期是否在过去
     *
     * @param localDate 需要检查的日期
     * @return 如果日期在过去，则返回 true；否则返回 false
     */
    public static boolean isPastDate(LocalDate localDate) {
        return localDate.isBefore(LocalDate.now());
    }

    /**
     * 检查日期是否在未来
     *
     * @param localDate 需要检查的日期
     * @return 如果日期在未来，则返回 true；否则返回 false
     */
    public static boolean isFutureDate(LocalDate localDate) {
        return localDate.isAfter(LocalDate.now());
    }

    /**
     * 计算两个日期之间的差值（以天为单位）
     *
     * @param startDate 开始日期
     * @param endDate 结束日期
     * @return 两日期之间的天数差
     */
    public static long daysBetween(LocalDate startDate, LocalDate endDate) {
        return ChronoUnit.DAYS.between(startDate, endDate);
    }

    /**
     * 计算两个日期时间之间的差值（以秒为单位）
     *
     * @param startDateTime 开始日期时间
     * @param endDateTime 结束日期时间
     * @return 两日期时间之间的秒数差
     */
    public static long secondsBetween(LocalDateTime startDateTime, LocalDateTime endDateTime) {
        return ChronoUnit.SECONDS.between(startDateTime, endDateTime);
    }

    // 可以根据需要添加其他日期时间处理方法
}