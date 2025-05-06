<?php
// 数据库配置信息
define('DB_HOST', 'localhost'); // 数据库主机
define('DB_NAME', 'readaloud'); // 数据库名
define('DB_USER', 'readaloud'); // 数据库用户名
define('DB_PASSWORD', 'Yj5YB76hsRLXxJdM'); // 数据库密码

// 连接数据库
function connectDB() {
    $conn = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
    
    // 检查连接
    if ($conn->connect_error) {
        die("数据库连接失败: " . $conn->connect_error);
    }
    
    // 设置字符集
    $conn->set_charset("utf8");
    
    return $conn;
}
?> 