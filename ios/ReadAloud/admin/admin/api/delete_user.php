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

// 连接数据库
$conn = connectDB();

// 验证令牌
$stmt = $conn->prepare("SELECT user_id FROM user_tokens WHERE user_id = ? AND token = ? AND expiry > NOW()");
if (!$stmt) {
    echo json_encode([
        'status' => 'error',
        'message' => '数据库操作失败: ' . $conn->error
    ]);
    $conn->close();
    exit;
}

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

// 开始删除用户相关数据
try {
    // 开始事务
    $conn->begin_transaction();
    
    // 1. 删除用户订阅
    $stmt = $conn->prepare("DELETE FROM user_subscriptions WHERE user_id = ?");
    if (!$stmt) {
        throw new Exception('删除用户订阅准备失败: ' . $conn->error);
    }
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $stmt->close();
    
    // 2. 删除用户令牌
    $stmt = $conn->prepare("DELETE FROM user_tokens WHERE user_id = ?");
    if (!$stmt) {
        throw new Exception('删除用户令牌准备失败: ' . $conn->error);
    }
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $stmt->close();
    
    // 3. 删除用户数据
    $stmt = $conn->prepare("DELETE FROM user_data WHERE user_id = ?");
    if (!$stmt) {
        throw new Exception('删除用户数据准备失败: ' . $conn->error);
    }
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $stmt->close();
    
    // 4. 最后删除用户账户
    $stmt = $conn->prepare("DELETE FROM users WHERE id = ?");
    if (!$stmt) {
        throw new Exception('删除用户账户准备失败: ' . $conn->error);
    }
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $stmt->close();
    
    // 提交事务
    $conn->commit();
    
    echo json_encode([
        'status' => 'success',
        'message' => '用户账户已成功删除'
    ]);
    
} catch (Exception $e) {
    // 发生错误时回滚事务
    $conn->rollback();
    
    echo json_encode([
        'status' => 'error',
        'message' => '删除账户失败: ' . $e->getMessage()
    ]);
}

// 关闭数据库连接
$conn->close();
?> 