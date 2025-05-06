<?php
session_start();
require_once 'config.php';

// 检查用户是否已登录
function isLoggedIn() {
    return isset($_SESSION['admin_id']);
}

// 重定向函数
function redirect($url) {
    header("Location: $url");
    exit();
}

// 清理输入数据
function cleanInput($data) {
    $data = trim($data);
    $data = stripslashes($data);
    $data = htmlspecialchars($data);
    return $data;
}

// 生成密码哈希
function hashPassword($password) {
    return password_hash($password, PASSWORD_DEFAULT);
}

// 验证密码
function verifyPassword($password, $hash) {
    return password_verify($password, $hash);
}
?> 