<?php
// 引入配置文件
require_once 'config.php';

// 连接数据库
$conn = connectDB();

// 检查是否已存在verified字段
$checkColumnQuery = "SHOW COLUMNS FROM verification_codes LIKE 'verified'";
$result = $conn->query($checkColumnQuery);

if ($result->num_rows == 0) {
    // 添加verified字段
    $alterTableQuery = "ALTER TABLE verification_codes ADD COLUMN verified TINYINT(1) NOT NULL DEFAULT 0";
    if ($conn->query($alterTableQuery) === TRUE) {
        echo "成功添加verified字段到verification_codes表！<br>";
    } else {
        echo "添加字段失败: " . $conn->error . "<br>";
    }
} else {
    echo "verified字段已存在，无需添加。<br>";
}

// 关闭数据库连接
$conn->close();

echo "<p>数据库更新完成。</p>";
?> 