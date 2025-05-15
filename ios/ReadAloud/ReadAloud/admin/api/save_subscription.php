<?php
header('Content-Type: application/json');

// 开启详细日志
error_reporting(E_ALL);
ini_set('display_errors', 1);
error_log("【save_subscription.php】开始处理请求");

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

// 获取原始POST数据并记录
$raw_data = file_get_contents('php://input');
error_log("【save_subscription.php】接收到的原始数据：" . $raw_data);

// 解析JSON数据
$data = json_decode($raw_data, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    echo json_encode([
        'status' => 'error',
        'message' => 'JSON解析失败: ' . json_last_error_msg()
    ]);
    exit;
}

// 检查必要参数
if (!isset($data['user_id']) || !isset($data['token']) || !isset($data['subscriptions'])) {
    echo json_encode([
        'status' => 'error',
        'message' => '缺少必要参数'
    ]);
    exit;
}

$user_id = (int)$data['user_id'];
$token = trim($data['token']);
$subscriptions = $data['subscriptions'];

// 以数组形式处理订阅数据
if (isset($subscriptions['id'])) {
    $subscriptions = [$subscriptions];
}

// 记录请求详情
error_log("【save_subscription.php】用户ID: $user_id");
error_log("【save_subscription.php】订阅数据数量: " . count($subscriptions));

try {
    // 连接数据库
    $conn = connectDB();
    error_log("【save_subscription.php】数据库连接成功");
    
    // 验证令牌
    $query = "SELECT user_id FROM user_tokens WHERE user_id = ? AND token = ? AND expiry > NOW()";
    $stmt = $conn->prepare($query);
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
        $stmt->close();
        $conn->close();
        exit;
    }
    $stmt->close();
    error_log("【save_subscription.php】令牌验证成功");
    
    // 验证用户
    $query = "SELECT id FROM users WHERE id = ? AND status = 'active'";
    $stmt = $conn->prepare($query);
    if (!$stmt) {
        throw new Exception("准备用户验证语句失败: " . $conn->error);
    }
    
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows !== 1) {
        echo json_encode([
            'status' => 'error',
            'message' => '用户不存在或已禁用'
        ]);
        $stmt->close();
        $conn->close();
        exit;
    }
    $stmt->close();
    error_log("【save_subscription.php】用户验证成功");
    
    // 检查user_subscriptions表是否存在
    $result = $conn->query("SHOW TABLES LIKE 'user_subscriptions'");
    if ($result->num_rows === 0) {
        // 创建表
        $createTableSQL = "CREATE TABLE `user_subscriptions` (
            `id` VARCHAR(36) NOT NULL,
            `user_id` INT NOT NULL,
            `subscription_type` VARCHAR(50) NOT NULL,
            `start_date` VARCHAR(50) NOT NULL,
            `end_date` VARCHAR(50) NOT NULL,
            `subscription_id` VARCHAR(100) NOT NULL,
            `is_active` TINYINT(1) NOT NULL DEFAULT 1,
            `created_at` VARCHAR(50) NOT NULL,
            `updated_at` VARCHAR(50) NOT NULL,
            PRIMARY KEY (`id`),
            INDEX (`user_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
        
        if (!$conn->query($createTableSQL)) {
            throw new Exception("创建表失败: " . $conn->error);
        }
        error_log("【save_subscription.php】创建user_subscriptions表成功");
    }
    
    // 开始事务
    $conn->begin_transaction();
    error_log("【save_subscription.php】开始事务");
    
    $updated = 0;
    $inserted = 0;
    
    // 处理每个订阅
    foreach ($subscriptions as $subscription) {
        // 检查必要字段
        $required_fields = ['id', 'userId', 'type', 'startDate', 'endDate', 'subscriptionId', 'isActive', 'createdAt', 'updatedAt'];
        foreach ($required_fields as $field) {
            if (!isset($subscription[$field])) {
                throw new Exception("订阅数据缺少必要字段: " . $field);
            }
        }
        
        $id = $subscription['id'];
        $sub_user_id = (int)$subscription['userId'];
        $type = $subscription['type'];
        $start_date = date('Y-m-d H:i:s', strtotime($subscription['startDate']));
        $end_date = date('Y-m-d H:i:s', strtotime($subscription['endDate']));
        $subscription_id = $subscription['subscriptionId'];
        $is_active = (int)$subscription['isActive'];
        $created_at = date('Y-m-d H:i:s', strtotime($subscription['createdAt']));
        $updated_at = date('Y-m-d H:i:s', strtotime($subscription['updatedAt']));
        
        error_log("【save_subscription.php】处理订阅: ID=$id, 类型=$type, 用户ID=$sub_user_id, 活跃=$is_active");
        error_log("【save_subscription.php】转换后的日期: 开始=$start_date, 结束=$end_date, 创建=$created_at, 更新=$updated_at");
        
        // 检查记录是否存在
        $query = "SELECT 1 FROM user_subscriptions WHERE id = ?";
        $stmt = $conn->prepare($query);
        if (!$stmt) {
            throw new Exception("准备检查语句失败: " . $conn->error);
        }
        
        $stmt->bind_param("s", $id);
        $stmt->execute();
        $result = $stmt->get_result();
        $exists = $result->num_rows > 0;
        $stmt->close();
        
        if ($exists) {
            // 更新现有记录
            error_log("【save_subscription.php】更新现有记录: $id");
            $query = "UPDATE user_subscriptions SET 
                subscription_type = ?,
                start_date = ?,
                end_date = ?,
                subscription_id = ?,
                is_active = ?,
                updated_at = ?
                WHERE id = ?";
                
            $stmt = $conn->prepare($query);
            if (!$stmt) {
                throw new Exception("准备更新语句失败: " . $conn->error);
            }
            
            $stmt->bind_param("ssssis", $type, $start_date, $end_date, $subscription_id, $is_active, $updated_at, $id);
            $stmt->execute();
            
            if ($stmt->affected_rows > 0) {
                $updated++;
                error_log("【save_subscription.php】更新成功: $id");
            } else {
                error_log("【save_subscription.php】无需更新或更新失败: $id, 错误: " . $stmt->error);
            }
            $stmt->close();
        } else {
            // 插入新记录
            error_log("【save_subscription.php】插入新记录: $id");
            $query = "INSERT INTO user_subscriptions (
                id, user_id, subscription_type, start_date, end_date, 
                subscription_id, is_active, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
            
            $stmt = $conn->prepare($query);
            if (!$stmt) {
                throw new Exception("准备插入语句失败: " . $conn->error);
            }
            
            error_log("【save_subscription.php】SQL绑定参数: id=$id, user_id=$sub_user_id, type=$type, start=$start_date, end=$end_date, subscription_id=$subscription_id, is_active=$is_active, created=$created_at, updated=$updated_at");
            
            // 对每个参数进行检查
            foreach ([$id, $sub_user_id, $type, $start_date, $end_date, $subscription_id, $is_active, $created_at, $updated_at] as $index => $param) {
                error_log("【save_subscription.php】参数 $index: " . (is_string($param) ? $param : gettype($param) . ":" . var_export($param, true)));
            }
            
            // 使用try-catch直接捕获绑定错误
            try {
                $bind_result = $stmt->bind_param("sissssiss", $id, $sub_user_id, $type, $start_date, $end_date, $subscription_id, $is_active, $created_at, $updated_at);
                if (!$bind_result) {
                    throw new Exception("参数绑定失败: " . $stmt->error);
                }
            } catch (Exception $e) {
                throw new Exception("参数绑定异常: " . $e->getMessage() . ", 参数类型数量: 9, 绑定类型字符串: sissssiss");
            }
            
            // 使用try-catch直接捕获执行错误
            try {
                $exec_result = $stmt->execute();
                if (!$exec_result) {
                    throw new Exception("执行失败: " . $stmt->error);
                }
            } catch (Exception $e) {
                throw new Exception("执行异常: " . $e->getMessage());
            }
            
            if ($stmt->affected_rows > 0) {
                $inserted++;
                error_log("【save_subscription.php】插入成功: $id");
            } else {
                error_log("【save_subscription.php】插入失败: $id, 错误: " . $stmt->error);
                throw new Exception("插入记录失败: " . $stmt->error);
            }
            $stmt->close();
        }
    }
    
    // 提交事务
    $conn->commit();
    error_log("【save_subscription.php】事务提交成功: 更新 $updated 条, 新增 $inserted 条");
    
    // 返回成功响应
    echo json_encode([
        'status' => 'success',
        'message' => "订阅数据保存成功，更新 $updated 条，新增 $inserted 条"
    ]);
    
} catch (Exception $e) {
    // 回滚事务（如果事务已开始）
    if (isset($conn) && $conn->ping()) {
        $conn->rollback();
        error_log("【save_subscription.php】事务回滚");
    }
    
    // 记录错误
    $error_message = "保存订阅数据失败: " . $e->getMessage();
    error_log("【save_subscription.php】错误: " . $error_message);
    
    // 返回错误响应
    echo json_encode([
        'status' => 'error',
        'message' => $error_message
    ]);
} finally {
    // 关闭数据库连接（如果存在）
    if (isset($conn) && $conn->ping()) {
        $conn->close();
        error_log("【save_subscription.php】数据库连接关闭");
    }
}

error_log("【save_subscription.php】请求处理完成");
?>