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
if (!isset($data['user_id']) || !isset($data['token']) || !isset($data['data_key']) || !isset($data['data_value'])) {
    echo json_encode([
        'status' => 'error',
        'message' => '缺少必要参数'
    ]);
    exit;
}

$user_id = (int)$data['user_id'];
$token = trim($data['token']);
$data_key = trim($data['data_key']);
$data_value = $data['data_value']; // 不trim，保留原始数据

// 连接数据库
$conn = connectDB();

// 验证令牌
$stmt = $conn->prepare("SELECT user_id FROM user_tokens WHERE user_id = ? AND token = ? AND expiry > NOW()");
$stmt->bind_param("is", $user_id, $token);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows !== 1) {
    echo json_encode([
        'status' => 'error',
        'message' => '认证失败'
    ]);
    $stmt->close();
    $conn->close();
    exit;
}

$stmt->close();

// 检查用户是否存在
$stmt = $conn->prepare("SELECT id FROM users WHERE id = ? AND status = 'active'");
$stmt->bind_param("i", $user_id);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows !== 1) {
    echo json_encode([
        'status' => 'error',
        'message' => '用户不存在或已被禁用'
    ]);
    $stmt->close();
    $conn->close();
    exit;
}

$stmt->close();

// 检查数据是否已存在
$stmt = $conn->prepare("SELECT id FROM user_data WHERE user_id = ? AND data_key = ?");
$stmt->bind_param("is", $user_id, $data_key);
$stmt->execute();
$result = $stmt->get_result();
$currentTime = date('Y-m-d H:i:s');

if ($result->num_rows > 0) {
    // 更新现有数据
    $dataId = $result->fetch_assoc()['id'];
    $stmt->close();
    
    $stmt = $conn->prepare("UPDATE user_data SET data_value = ?, updated_at = ? WHERE id = ?");
    $stmt->bind_param("ssi", $data_value, $currentTime, $dataId);
} else {
    // 插入新数据
    $stmt->close();
    
    $stmt = $conn->prepare("INSERT INTO user_data (user_id, data_key, data_value, created_at, updated_at) VALUES (?, ?, ?, ?, ?)");
    $stmt->bind_param("issss", $user_id, $data_key, $data_value, $currentTime, $currentTime);
}

if ($stmt->execute()) {
    echo json_encode([
        'status' => 'success',
        'message' => '数据保存成功'
    ]);
} else {
    echo json_encode([
        'status' => 'error',
        'message' => '数据保存失败: ' . $conn->error
    ]);
}

$stmt->close();
$conn->close();
?> 