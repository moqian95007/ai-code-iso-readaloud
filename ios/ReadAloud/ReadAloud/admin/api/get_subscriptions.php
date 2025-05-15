<?php
header('Content-Type: application/json');

// 开启详细日志
error_reporting(E_ALL);
ini_set('display_errors', 1);
error_log("【get_subscriptions.php】开始处理获取订阅请求");

// 引入必要的文件
require_once '../config.php';

// 检查请求方法
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode([
        'status' => 'error',
        'message' => '请求方法不支持'
    ]);
    error_log("【get_subscriptions.php】错误: 请求方法不支持");
    exit;
}

// 获取POST数据
$raw_data = file_get_contents('php://input');
error_log("【get_subscriptions.php】原始请求数据: " . $raw_data);

$data = json_decode($raw_data, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    echo json_encode([
        'status' => 'error',
        'message' => 'JSON解析失败: ' . json_last_error_msg()
    ]);
    error_log("【get_subscriptions.php】JSON解析失败: " . json_last_error_msg());
    exit;
}

// 检查必要参数
if (!isset($data['user_id']) || !isset($data['token'])) {
    echo json_encode([
        'status' => 'error',
        'message' => '缺少必要参数'
    ]);
    error_log("【get_subscriptions.php】缺少必要参数");
    exit;
}

$user_id = (int)$data['user_id'];
$token = trim($data['token']);
$active_only = isset($data['active_only']) ? (bool)$data['active_only'] : false;

error_log("【get_subscriptions.php】用户ID: $user_id, 只获取活跃订阅: " . ($active_only ? 'true' : 'false'));

try {
    // 连接数据库
    $conn = connectDB();
    error_log("【get_subscriptions.php】数据库连接成功");
    
    // 验证令牌
    $stmt = $conn->prepare("SELECT user_id FROM user_tokens WHERE user_id = ? AND token = ? AND expiry > NOW()");
    if (!$stmt) {
        throw new Exception("准备令牌验证语句失败: " . $conn->error);
    }
    
    $stmt->bind_param("is", $user_id, $token);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows !== 1) {
        echo json_encode([
            'status' => 'error',
            'message' => '认证失败'
        ]);
        error_log("【get_subscriptions.php】认证失败: 令牌无效");
        $stmt->close();
        $conn->close();
        exit;
    }
    
    $stmt->close();
    error_log("【get_subscriptions.php】令牌验证成功");
    
    // 确保表存在
    $tableResult = $conn->query("SHOW TABLES LIKE 'user_subscriptions'");
    if ($tableResult->num_rows === 0) {
        // 表不存在
        error_log("【get_subscriptions.php】表user_subscriptions不存在，返回空数组");
        echo json_encode([
            'status' => 'success',
            'data' => []
        ]);
        $conn->close();
        exit;
    }
    
    // 获取用户订阅数据
    if ($active_only) {
        // 只获取有效的活跃订阅
        error_log("【get_subscriptions.php】查询活跃订阅");
        $query = "
            SELECT * FROM user_subscriptions 
            WHERE user_id = ? AND is_active = 1 AND end_date > NOW()
            ORDER BY end_date DESC
        ";
    } else {
        // 获取所有订阅
        error_log("【get_subscriptions.php】查询所有订阅");
        $query = "
            SELECT * FROM user_subscriptions 
            WHERE user_id = ?
            ORDER BY updated_at DESC
        ";
    }
    
    $stmt = $conn->prepare($query);
    if (!$stmt) {
        throw new Exception("准备查询语句失败: " . $conn->error);
    }
    
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $result = $stmt->get_result();
    $subscriptions = [];
    
    error_log("【get_subscriptions.php】找到 " . $result->num_rows . " 条订阅记录");
    
    while ($row = $result->fetch_assoc()) {
        error_log("【get_subscriptions.php】处理订阅ID: " . $row['id']);
        
        // 转换为客户端期望的格式（使用驼峰命名法）
        $subscriptions[] = [
            'id' => $row['id'],
            'userId' => (int)$row['user_id'],
            'type' => $row['subscription_type'],
            'startDate' => $row['start_date'],
            'endDate' => $row['end_date'],
            'subscriptionId' => $row['subscription_id'],
            'isActive' => (bool)$row['is_active'],
            'createdAt' => $row['created_at'],
            'updatedAt' => $row['updated_at']
        ];
    }
    
    $stmt->close();
    
    // 返回用户订阅数据
    error_log("【get_subscriptions.php】返回 " . count($subscriptions) . " 条订阅数据");
    echo json_encode([
        'status' => 'success',
        'data' => $subscriptions
    ]);
    
} catch (Exception $e) {
    $errorMessage = "获取订阅数据失败: " . $e->getMessage();
    error_log("【get_subscriptions.php】错误: " . $errorMessage);
    
    echo json_encode([
        'status' => 'error',
        'message' => $errorMessage
    ]);
} finally {
    // 关闭数据库连接
    if (isset($conn) && $conn->ping()) {
        $conn->close();
        error_log("【get_subscriptions.php】数据库连接关闭");
    }
}

error_log("【get_subscriptions.php】请求处理完成");
?> 