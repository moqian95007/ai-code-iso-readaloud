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
if (!isset($data['user_id']) || !isset($data['token'])) {
    echo json_encode([
        'status' => 'error',
        'message' => '缺少必要参数'
    ]);
    exit;
}

$user_id = (int)$data['user_id'];
$token = trim($data['token']);
$data_key = isset($data['data_key']) ? trim($data['data_key']) : null;

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

// 特殊处理：获取剩余导入数量
if ($data_key === "remaining_import_count") {
    $stmt = $conn->prepare("SELECT remaining_import_count FROM users WHERE id = ?");
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 1) {
        $row = $result->fetch_assoc();
        $userData = [
            "remaining_import_count" => (string)$row["remaining_import_count"]
        ];
        
        echo json_encode([
            'status' => 'success',
            'data' => $userData
        ]);
    } else {
        echo json_encode([
            'status' => 'error',
            'message' => '找不到用户数据'
        ]);
    }
    
    $stmt->close();
    $conn->close();
    exit;
}

// 获取用户数据
if ($data_key) {
    // 获取特定键的数据
    $stmt = $conn->prepare("SELECT data_key, data_value FROM user_data WHERE user_id = ? AND data_key = ?");
    $stmt->bind_param("is", $user_id, $data_key);
} else {
    // 获取所有数据
    $stmt = $conn->prepare("SELECT data_key, data_value FROM user_data WHERE user_id = ?");
    $stmt->bind_param("i", $user_id);
}

$stmt->execute();
$result = $stmt->get_result();
$userData = [];

while ($row = $result->fetch_assoc()) {
    $userData[$row['data_key']] = $row['data_value'];
}

$stmt->close();
$conn->close();

// 返回用户数据
echo json_encode([
    'status' => 'success',
    'data' => $userData
]);
?> 