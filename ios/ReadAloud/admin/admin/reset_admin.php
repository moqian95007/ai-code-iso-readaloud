<?php
require_once 'config.php';
require_once 'functions.php';

// 连接数据库
$conn = connectDB();

// 设置管理员账户信息
$username = 'admin';
$password = 'admin123';
$email = 'admin@readaloud.com';
$currentTime = date('Y-m-d H:i:s');

// 生成新的密码哈希
$password_hash = hashPassword($password);

// 检查管理员账户是否存在
$stmt = $conn->prepare("SELECT id FROM admin WHERE username = ?");
$stmt->bind_param("s", $username);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    // 更新管理员密码
    $admin_id = $result->fetch_assoc()['id'];
    $stmt->close();
    
    $stmt = $conn->prepare("UPDATE admin SET password = ? WHERE id = ?");
    $stmt->bind_param("si", $password_hash, $admin_id);
    
    if ($stmt->execute()) {
        echo "管理员密码已重置为: $password";
    } else {
        echo "更新失败: " . $conn->error;
    }
} else {
    // 创建新管理员账户
    $stmt->close();
    
    $stmt = $conn->prepare("INSERT INTO admin (username, password, email, created_at) VALUES (?, ?, ?, ?)");
    $stmt->bind_param("ssss", $username, $password_hash, $email, $currentTime);
    
    if ($stmt->execute()) {
        echo "管理员账户已创建，用户名: $username, 密码: $password";
    } else {
        echo "创建失败: " . $conn->error;
    }
}

$stmt->close();
$conn->close();
?> 