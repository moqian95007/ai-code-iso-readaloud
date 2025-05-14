<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Access-Control-Allow-Headers, Content-Type, Access-Control-Allow-Methods, Authorization, X-Requested-With');

// 引入数据库连接
require_once '../config.php';
require_once '../functions.php';

// 接收POST数据
$data = json_decode(file_get_contents('php://input'), true);

// 如果没有收到JSON数据，尝试从POST获取
if (empty($data)) {
    $data = $_POST;
}

// 验证必要参数是否存在
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['status' => 'error', 'message' => '只接受POST请求', 'data' => null]);
    exit();
}

// 检查登录类型和必要参数
if (!isset($data['login_type'])) {
    echo json_encode(['status' => 'error', 'message' => '缺少登录类型参数', 'data' => null]);
    exit();
}

$login_type = $data['login_type'];
$conn = connectDB();

// 根据登录类型处理不同的认证
if ($login_type === 'apple') {
    // 验证必要参数是否存在
    if (!isset($data['apple_user_id']) || empty($data['apple_user_id'])) {
        echo json_encode(['status' => 'error', 'message' => '缺少Apple用户ID', 'data' => null]);
        exit();
    }
    
    $account_id = cleanInput($data['apple_user_id']);
    $email = isset($data['email']) ? cleanInput($data['email']) : '';
    $full_name = isset($data['full_name']) ? cleanInput($data['full_name']) : '';
    $id_token = isset($data['id_token']) ? cleanInput($data['id_token']) : '';
    
    // 查找是否已存在此account_id的Apple用户
    $stmt = $conn->prepare("SELECT id, username, email, phone, register_date, last_login, status FROM users WHERE account_id = ? AND login_type = 'apple'");
    $stmt->bind_param("s", $account_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        // 用户已存在，更新登录时间
        $user = $result->fetch_assoc();
        $user_id = $user['id'];
        
        // 更新用户信息和最后登录时间
        $current_time = date('Y-m-d H:i:s');
        $update_stmt = $conn->prepare("UPDATE users SET last_login = ? WHERE id = ?");
        $update_stmt->bind_param("si", $current_time, $user_id);
        $update_stmt->execute();
        
        // 如果有新的email或name，更新用户资料
        if (!empty($email) && $email != $user['email']) {
            $update_email = $conn->prepare("UPDATE users SET email = ? WHERE id = ?");
            $update_email->bind_param("si", $email, $user_id);
            $update_email->execute();
            $user['email'] = $email;
        }
        
        if (!empty($full_name) && $full_name != $user['username']) {
            $update_name = $conn->prepare("UPDATE users SET username = ? WHERE id = ?");
            $update_name->bind_param("si", $full_name, $user_id);
            $update_name->execute();
            $user['username'] = $full_name;
        }
        
        // 生成新的令牌
        $token = bin2hex(random_bytes(32));
        $expiry = date('Y-m-d H:i:s', strtotime('+30 days'));
        
        // 更新或插入令牌
        $token_stmt = $conn->prepare("INSERT INTO user_tokens (user_id, token, expiry) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE token = ?, expiry = ?");
        $token_stmt->bind_param("issss", $user_id, $token, $expiry, $token, $expiry);
        $token_stmt->execute();
        
        // 返回用户信息
        $user['token'] = $token;
        echo json_encode(['status' => 'success', 'message' => '登录成功', 'data' => $user]);
    } else {
        // 用户不存在，创建新用户
        $username = !empty($full_name) ? $full_name : "AppleUser_" . substr($account_id, 0, 5);
        $current_time = date('Y-m-d H:i:s');
        $status = 'active';
        $login_type_value = 'apple';

        // 生成随机密码 (用户无需知道此密码，因为他们使用Apple登录)
        $random_password = bin2hex(random_bytes(16)); // 32个字符的随机字符串
        $hashed_password = password_hash($random_password, PASSWORD_DEFAULT);

        // 插入新用户
        $insert_stmt = $conn->prepare("INSERT INTO users (username, email, account_id, login_type, apple_id, password, register_date, last_login, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $insert_stmt->bind_param("sssssssss", $username, $email, $account_id, $login_type_value, $account_id, $hashed_password, $current_time, $current_time, $status);
        
        if ($insert_stmt->execute()) {
            $user_id = $conn->insert_id;
            
            // 生成令牌
            $token = bin2hex(random_bytes(32));
            $expiry = date('Y-m-d H:i:s', strtotime('+30 days'));
            
            // 插入令牌
            $token_stmt = $conn->prepare("INSERT INTO user_tokens (user_id, token, expiry) VALUES (?, ?, ?)");
            $token_stmt->bind_param("iss", $user_id, $token, $expiry);
            $token_stmt->execute();
            
            // 返回新用户信息
            $new_user = [
                'id' => $user_id,
                'username' => $username,
                'email' => $email,
                'phone' => null,
                'register_date' => $current_time,
                'last_login' => $current_time,
                'status' => 'active',
                'token' => $token
            ];
            
            echo json_encode(['status' => 'success', 'message' => '注册成功', 'data' => $new_user]);
        } else {
            echo json_encode(['status' => 'error', 'message' => '注册失败: ' . $conn->error, 'data' => null]);
        }
    }
} elseif ($login_type === 'google') {
    // 验证必要参数是否存在
    if (!isset($data['id_token']) || empty($data['id_token'])) {
        echo json_encode(['status' => 'error', 'message' => '缺少Google令牌', 'data' => null]);
        exit();
    }
    
    $google_token = cleanInput($data['id_token']);
    $email = isset($data['email']) ? cleanInput($data['email']) : '';
    $full_name = isset($data['full_name']) ? cleanInput($data['full_name']) : '';
    
    // 使用id_token作为account_id
    $account_id = $google_token;
    
    // 查找是否已存在此account_id的Google用户
    $stmt = $conn->prepare("SELECT id, username, email, phone, register_date, last_login, status FROM users WHERE account_id = ? AND login_type = 'google'");
    $stmt->bind_param("s", $account_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        // 用户已存在，更新登录时间
        $user = $result->fetch_assoc();
        $user_id = $user['id'];
        
        // 更新最后登录时间
        $current_time = date('Y-m-d H:i:s');
        $update_stmt = $conn->prepare("UPDATE users SET last_login = ? WHERE id = ?");
        $update_stmt->bind_param("si", $current_time, $user_id);
        $update_stmt->execute();
        
        // 如果有新的email，更新用户邮箱
        if (!empty($email) && $email != $user['email']) {
            $update_email = $conn->prepare("UPDATE users SET email = ? WHERE id = ?");
            $update_email->bind_param("si", $email, $user_id);
            $update_email->execute();
            $user['email'] = $email;
        }
        
        // 如果有新的name，更新用户名
        if (!empty($full_name) && $full_name != $user['username']) {
            $update_name = $conn->prepare("UPDATE users SET username = ? WHERE id = ?");
            $update_name->bind_param("si", $full_name, $user_id);
            $update_name->execute();
            $user['username'] = $full_name;
        }
        
        // 生成新的令牌
        $token = bin2hex(random_bytes(32));
        $expiry = date('Y-m-d H:i:s', strtotime('+30 days'));
        
        // 更新或插入令牌
        $token_stmt = $conn->prepare("INSERT INTO user_tokens (user_id, token, expiry) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE token = ?, expiry = ?");
        $token_stmt->bind_param("issss", $user_id, $token, $expiry, $token, $expiry);
        $token_stmt->execute();
        
        // 返回用户信息
        $user['token'] = $token;
        echo json_encode(['status' => 'success', 'message' => '登录成功', 'data' => $user]);
    } else {
        // 用户不存在，创建新用户
        $username = !empty($full_name) ? $full_name : "GoogleUser_" . substr($account_id, 0, 5);
        $current_time = date('Y-m-d H:i:s');
        $status = 'active';
        $login_type_value = 'google';

        // 生成随机密码 (用户无需知道此密码，因为他们使用Google登录)
        $random_password = bin2hex(random_bytes(16)); // 32个字符的随机字符串
        $hashed_password = password_hash($random_password, PASSWORD_DEFAULT);

        // 插入新用户
        $insert_stmt = $conn->prepare("INSERT INTO users (username, email, account_id, login_type, google_id, password, register_date, last_login, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $insert_stmt->bind_param("sssssssss", $username, $email, $account_id, $login_type_value, $account_id, $hashed_password, $current_time, $current_time, $status);
        
        if ($insert_stmt->execute()) {
            $user_id = $conn->insert_id;
            
            // 生成令牌
            $token = bin2hex(random_bytes(32));
            $expiry = date('Y-m-d H:i:s', strtotime('+30 days'));
            
            // 插入令牌
            $token_stmt = $conn->prepare("INSERT INTO user_tokens (user_id, token, expiry) VALUES (?, ?, ?)");
            $token_stmt->bind_param("iss", $user_id, $token, $expiry);
            $token_stmt->execute();
            
            // 返回新用户信息
            $new_user = [
                'id' => $user_id,
                'username' => $username,
                'email' => $email,
                'phone' => null,
                'register_date' => $current_time,
                'last_login' => $current_time,
                'status' => 'active',
                'token' => $token
            ];
            
            echo json_encode(['status' => 'success', 'message' => '注册成功', 'data' => $new_user]);
        } else {
            echo json_encode(['status' => 'error', 'message' => '注册失败: ' . $conn->error, 'data' => null]);
        }
    }
} else {
    echo json_encode(['status' => 'error', 'message' => '不支持的登录类型', 'data' => null]);
}

$conn->close();
?> 