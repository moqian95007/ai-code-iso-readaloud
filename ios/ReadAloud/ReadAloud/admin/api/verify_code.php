<?php
// 设置响应头为JSON
header('Content-Type: application/json');

// 引入配置文件
require_once '../config.php';

// 记录请求信息，便于调试
error_log("Received verification code validation request");

// 检查请求方法
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode([
        'status' => 'error',
        'message' => '不支持的请求方法'
    ]);
    exit;
}

// 获取POST数据 - 支持JSON和表单数据
$email = null;
$verificationCode = null;

// 检查是否有JSON数据
$rawInput = file_get_contents('php://input');
if (!empty($rawInput)) {
    $postData = json_decode($rawInput, true);
    if (json_last_error() === JSON_ERROR_NONE) {
        if (isset($postData['email'])) {
            $email = $postData['email'];
        }
        if (isset($postData['verification_code'])) {
            $verificationCode = $postData['verification_code'];
        }
        error_log("Received JSON data with email: " . $email . " and code: " . $verificationCode);
    }
}

// 如果没有从JSON获取到数据，尝试从标准POST中获取
if (empty($email) && isset($_POST['email'])) {
    $email = $_POST['email'];
}
if (empty($verificationCode) && isset($_POST['verification_code'])) {
    $verificationCode = $_POST['verification_code'];
}

// 检查是否提供了必要参数
if (empty($email) || empty($verificationCode)) {
    echo json_encode([
        'status' => 'error',
        'message' => '请提供电子邮箱和验证码'
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
error_log("Database connection established");

// 检查邮箱是否已注册
$checkUserExistsQuery = "SELECT id FROM users WHERE email = ?";
$checkUserExistsStmt = $conn->prepare($checkUserExistsQuery);
$checkUserExistsStmt->bind_param("s", $email);
$checkUserExistsStmt->execute();
$userResult = $checkUserExistsStmt->get_result();
$checkUserExistsStmt->close();

if ($userResult->num_rows > 0) {
    echo json_encode([
        'status' => 'error',
        'message' => '该邮箱已被注册'
    ]);
    $conn->close();
    exit;
}

// 验证验证码
$verifyCodeQuery = "SELECT code, expires_at FROM verification_codes WHERE email = ? ORDER BY created_at DESC LIMIT 1";
$verifyCodeStmt = $conn->prepare($verifyCodeQuery);
$verifyCodeStmt->bind_param("s", $email);
$verifyCodeStmt->execute();
$codeResult = $verifyCodeStmt->get_result();
$verifyCodeStmt->close();

if ($codeResult->num_rows === 0) {
    echo json_encode([
        'status' => 'error',
        'message' => '验证码不存在，请重新获取'
    ]);
    $conn->close();
    exit;
}

$codeData = $codeResult->fetch_assoc();

// 检查验证码是否正确
if ($codeData['code'] !== $verificationCode) {
    echo json_encode([
        'status' => 'error',
        'message' => '验证码不正确'
    ]);
    $conn->close();
    exit;
}

// 检查验证码是否过期
if (strtotime($codeData['expires_at']) < time()) {
    echo json_encode([
        'status' => 'error',
        'message' => '验证码已过期，请重新获取'
    ]);
    $conn->close();
    exit;
}

// 更新验证码状态为已验证，以便后续注册使用
$updateCodeQuery = "UPDATE verification_codes SET verified = 1 WHERE email = ? AND code = ?";
$updateCodeStmt = $conn->prepare($updateCodeQuery);
$updateCodeStmt->bind_param("ss", $email, $verificationCode);
$updateResult = $updateCodeStmt->execute();
$updateCodeStmt->close();

if (!$updateResult) {
    echo json_encode([
        'status' => 'error',
        'message' => '验证码状态更新失败'
    ]);
    $conn->close();
    exit;
}

// 验证成功
echo json_encode([
    'status' => 'success',
    'message' => '验证码验证成功',
    'data' => [
        'email' => $email,
        'verified' => true,
        'username_suggestion' => strstr($email, '@', true) // 提取邮箱@前的部分作为用户名建议
    ]
]);

// 关闭数据库连接
$conn->close();
?> 