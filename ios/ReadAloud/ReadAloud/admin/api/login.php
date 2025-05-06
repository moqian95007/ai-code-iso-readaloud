<?php
header('Content-Type: application/json');

// 引入必要的文件
require_once '../config.php';
require_once '../functions.php';

// 检查请求方法
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode([
        'status' => 'error',
        'message' => '请求方法不支持'
    ]);
    exit;
}

// 获取POST数据
$data = json_decode(file_get_contents('php://input'), true);

// 确定邮箱参数 - 支持从username或email字段获取邮箱
$email = null;
if (isset($data['email'])) {
    $email = trim($data['email']);
} elseif (isset($data['username'])) {
    // 兼容旧版本，从username字段获取邮箱
    $email = trim($data['username']);
}

// 检查必要参数
if (empty($email) || !isset($data['password'])) {
    echo json_encode([
        'status' => 'error',
        'message' => '缺少必要参数'
    ]);
    exit;
}

$password = trim($data['password']);

// 连接数据库
$conn = connectDB();

// 只通过邮箱查询用户
$stmt = $conn->prepare("SELECT id, username, email, password, status FROM users WHERE email = ?");
$stmt->bind_param("s", $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows !== 1) {
    echo json_encode([
        'status' => 'error',
        'message' => '邮箱或密码错误'
    ]);
    $stmt->close();
    $conn->close();
    exit;
}

$user = $result->fetch_assoc();
$stmt->close();

// 验证密码
if (!password_verify($password, $user['password'])) {
    echo json_encode([
        'status' => 'error',
        'message' => '邮箱或密码错误'
    ]);
    $conn->close();
    exit;
}

// 检查用户状态
if ($user['status'] !== 'active') {
    echo json_encode([
        'status' => 'error',
        'message' => '账号已被禁用，请联系管理员'
    ]);
    $conn->close();
    exit;
}

// 更新最后登录时间
$currentTime = date('Y-m-d H:i:s');
$stmt = $conn->prepare("UPDATE users SET last_login = ? WHERE id = ?");
$stmt->bind_param("si", $currentTime, $user['id']);
$stmt->execute();
$stmt->close();

// 生成认证令牌
$token = bin2hex(random_bytes(32));
$expiry = date('Y-m-d H:i:s', strtotime('+1 day'));

// 保存令牌到数据库
$stmt = $conn->prepare("INSERT INTO user_tokens (user_id, token, expiry) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE token = ?, expiry = ?");
$stmt->bind_param("issss", $user['id'], $token, $expiry, $token, $expiry);
$stmt->execute();
$stmt->close();

// 构建用户数据响应
$userData = [
    'id' => $user['id'],
    'username' => $user['username'],
    'email' => $user['email'],
    'token' => $token,
    'last_login' => $currentTime,
    'status' => $user['status']
];

$conn->close();

// 返回成功响应
echo json_encode([
    'status' => 'success',
    'message' => '登录成功',
    'data' => $userData
]);
?> 