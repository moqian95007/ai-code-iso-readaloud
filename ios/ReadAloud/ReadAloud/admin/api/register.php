<?php
header('Content-Type: application/json');

// 引入必要的文件
require_once '../config.php';

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

// 检查必要参数
if (!isset($data['password']) || !isset($data['email']) || !isset($data['verification_code'])) {
    echo json_encode([
        'status' => 'error',
        'message' => '缺少必要参数'
    ]);
    exit;
}

$password = trim($data['password']);
$email = trim($data['email']);
$verificationCode = trim($data['verification_code']);

// 从邮箱中提取用户名
$username = strstr($email, '@', true);
// 确保用户名至少有3个字符
if (strlen($username) < 3) {
    $username = $username . "_user"; // 添加后缀确保长度
}

// 验证密码长度
if (strlen($password) < 6) {
    echo json_encode([
        'status' => 'error',
        'message' => '密码至少6个字符'
    ]);
    exit;
}

// 验证邮箱格式
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    echo json_encode([
        'status' => 'error',
        'message' => '邮箱格式不正确'
    ]);
    exit;
}

// 连接数据库
$conn = connectDB();

// 验证验证码
$stmt = $conn->prepare("SELECT code, expires_at, verified FROM verification_codes WHERE email = ? ORDER BY created_at DESC LIMIT 1");
$stmt->bind_param("s", $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode([
        'status' => 'error',
        'message' => '验证码不存在，请重新获取'
    ]);
    $stmt->close();
    $conn->close();
    exit;
}

$verificationData = $result->fetch_assoc();
$stmt->close();

// 检查验证码是否正确
if ($verificationData['code'] !== $verificationCode) {
    echo json_encode([
        'status' => 'error',
        'message' => '验证码不正确'
    ]);
    $conn->close();
    exit;
}

// 检查验证码是否过期
if (strtotime($verificationData['expires_at']) < time()) {
    echo json_encode([
        'status' => 'error',
        'message' => '验证码已过期，请重新获取'
    ]);
    $conn->close();
    exit;
}

// 检查验证码是否已验证过
if (!isset($verificationData['verified']) || $verificationData['verified'] != 1) {
    echo json_encode([
        'status' => 'error',
        'message' => '请先验证验证码'
    ]);
    $conn->close();
    exit;
}

// 检查邮箱是否已存在
$stmt = $conn->prepare("SELECT id FROM users WHERE email = ?");
$stmt->bind_param("s", $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    echo json_encode([
        'status' => 'error',
        'message' => '邮箱已被注册'
    ]);
    $stmt->close();
    $conn->close();
    exit;
}
$stmt->close();

// 检查自动生成的用户名是否存在，如果存在则添加随机数字
$stmt = $conn->prepare("SELECT id FROM users WHERE username = ?");
$stmt->bind_param("s", $username);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    // 如果用户名已存在，添加随机数字
    $username = $username . "_" . rand(100, 999);
}
$stmt->close();

// 生成密码哈希
$password_hash = password_hash($password, PASSWORD_DEFAULT);
$status = 'active';
$currentTime = date('Y-m-d H:i:s');

// 插入用户数据
$stmt = $conn->prepare("INSERT INTO users (username, password, email, register_date, last_login, status) VALUES (?, ?, ?, ?, ?, ?)");
$stmt->bind_param("ssssss", $username, $password_hash, $email, $currentTime, $currentTime, $status);

if ($stmt->execute()) {
    $user_id = $conn->insert_id;
    
    // 生成认证令牌
    $token = bin2hex(random_bytes(32));
    $expiry = date('Y-m-d H:i:s', strtotime('+1 day'));
    
    // 保存令牌到数据库
    $tokenStmt = $conn->prepare("INSERT INTO user_tokens (user_id, token, expiry) VALUES (?, ?, ?)");
    $tokenStmt->bind_param("iss", $user_id, $token, $expiry);
    $tokenStmt->execute();
    $tokenStmt->close();
    
    // 删除验证码记录
    $deleteStmt = $conn->prepare("DELETE FROM verification_codes WHERE email = ?");
    $deleteStmt->bind_param("s", $email);
    $deleteStmt->execute();
    $deleteStmt->close();
    
    // 构建用户数据响应
    $userData = [
        'id' => $user_id,
        'username' => $username,
        'email' => $email,
        'token' => $token,
        'register_date' => $currentTime,
        'last_login' => $currentTime,
        'status' => $status
    ];
    
    echo json_encode([
        'status' => 'success',
        'message' => '注册成功',
        'data' => $userData
    ]);
} else {
    echo json_encode([
        'status' => 'error',
        'message' => '注册失败: ' . $conn->error
    ]);
}

$stmt->close();
$conn->close();
?> 