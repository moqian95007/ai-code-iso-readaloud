<?php
require_once 'functions.php';

// 检查用户是否已登录
if (!isLoggedIn()) {
    redirect('index.php');
}

// 检查是否有用户ID
if (!isset($_GET['id'])) {
    redirect('users.php');
}

$userId = (int)$_GET['id'];
$conn = connectDB();
$message = '';
$user = null;

// 处理表单提交
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = cleanInput($_POST['username']);
    $email = cleanInput($_POST['email']);
    $phone = cleanInput($_POST['phone']);
    $status = cleanInput($_POST['status']);
    
    $stmt = $conn->prepare("UPDATE users SET username = ?, email = ?, phone = ?, status = ? WHERE id = ?");
    $stmt->bind_param("ssssi", $username, $email, $phone, $status, $userId);
    
    if ($stmt->execute()) {
        $message = '用户信息已更新';
    } else {
        $message = '更新失败: ' . $conn->error;
    }
    $stmt->close();
}

// 获取用户信息
$stmt = $conn->prepare("SELECT id, username, email, phone, register_date, last_login, status FROM users WHERE id = ?");
$stmt->bind_param("i", $userId);
$stmt->execute();
$result = $stmt->get_result();

if ($result && $result->num_rows === 1) {
    $user = $result->fetch_assoc();
} else {
    redirect('users.php');
}

$stmt->close();
$conn->close();
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ReadAloud 后台管理系统 - 编辑用户</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            background-color: #f4f4f4;
        }
        .header {
            background-color: #333;
            color: white;
            padding: 15px 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header h1 {
            margin: 0;
            font-size: 24px;
        }
        .user-info {
            display: flex;
            align-items: center;
        }
        .user-info span {
            margin-right: 15px;
        }
        .container {
            display: flex;
            min-height: calc(100vh - 60px);
        }
        .sidebar {
            width: 200px;
            background-color: #2c3e50;
            color: white;
            padding: 20px 0;
        }
        .sidebar ul {
            list-style-type: none;
            padding: 0;
            margin: 0;
        }
        .sidebar li {
            padding: 10px 20px;
        }
        .sidebar li:hover {
            background-color: #34495e;
            cursor: pointer;
        }
        .sidebar a {
            color: white;
            text-decoration: none;
            display: block;
        }
        .content {
            flex: 1;
            padding: 20px;
        }
        .card {
            background-color: white;
            border-radius: 5px;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
            padding: 20px;
            margin-bottom: 20px;
        }
        .card h2 {
            margin-top: 0;
            border-bottom: 1px solid #eee;
            padding-bottom: 10px;
            color: #333;
        }
        .logout-btn {
            background-color: #e74c3c;
            color: white;
            border: none;
            padding: 8px 12px;
            border-radius: 3px;
            cursor: pointer;
        }
        .logout-btn:hover {
            background-color: #c0392b;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        input[type="text"], input[type="email"], select {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 3px;
            box-sizing: border-box;
        }
        .buttons {
            display: flex;
            justify-content: space-between;
            margin-top: 20px;
        }
        .btn {
            padding: 10px 15px;
            border: none;
            border-radius: 3px;
            cursor: pointer;
        }
        .btn-primary {
            background-color: #3498db;
            color: white;
        }
        .btn-primary:hover {
            background-color: #2980b9;
        }
        .btn-cancel {
            background-color: #95a5a6;
            color: white;
        }
        .btn-cancel:hover {
            background-color: #7f8c8d;
        }
        .message {
            padding: 10px;
            margin-bottom: 20px;
            background-color: #d4edda;
            color: #155724;
            border-radius: 3px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>ReadAloud 后台管理系统</h1>
        <div class="user-info">
            <span>欢迎，<?php echo htmlspecialchars($_SESSION['admin_username']); ?></span>
            <form method="post" action="logout.php">
                <button type="submit" class="logout-btn">退出登录</button>
            </form>
        </div>
    </div>
    
    <div class="container">
        <div class="sidebar">
            <ul>
                <li><a href="dashboard.php">仪表盘</a></li>
                <li><a href="users.php">用户管理</a></li>
                <li><a href="subscriptions.php">订阅管理</a></li>
                <li><a href="user_data.php">用户数据</a></li>
                <li><a href="api.php">API接口</a></li>
            </ul>
        </div>
        
        <div class="content">
            <div class="card">
                <h2>编辑用户</h2>
                
                <?php if (!empty($message)): ?>
                    <div class="message"><?php echo $message; ?></div>
                <?php endif; ?>
                
                <?php if ($user): ?>
                    <form method="post" action="">
                        <div class="form-group">
                            <label for="username">用户名</label>
                            <input type="text" id="username" name="username" value="<?php echo htmlspecialchars($user['username']); ?>" required>
                        </div>
                        
                        <div class="form-group">
                            <label for="email">邮箱</label>
                            <input type="email" id="email" name="email" value="<?php echo htmlspecialchars($user['email']); ?>">
                        </div>
                        
                        <div class="form-group">
                            <label for="phone">手机号</label>
                            <input type="text" id="phone" name="phone" value="<?php echo htmlspecialchars($user['phone']); ?>">
                        </div>
                        
                        <div class="form-group">
                            <label for="status">状态</label>
                            <select id="status" name="status">
                                <option value="active" <?php echo $user['status'] === 'active' ? 'selected' : ''; ?>>激活</option>
                                <option value="inactive" <?php echo $user['status'] === 'inactive' ? 'selected' : ''; ?>>禁用</option>
                            </select>
                        </div>
                        
                        <div class="form-group">
                            <label>注册日期</label>
                            <input type="text" value="<?php echo $user['register_date']; ?>" readonly>
                        </div>
                        
                        <div class="form-group">
                            <label>最后登录</label>
                            <input type="text" value="<?php echo $user['last_login']; ?>" readonly>
                        </div>
                        
                        <div class="form-group">
                            <label>订阅管理</label>
                            <a href="subscriptions.php?user_id=<?php echo $user['id']; ?>" class="btn btn-primary" style="display: inline-block; text-decoration: none; margin-top: 5px;">查看用户订阅</a>
                        </div>
                        
                        <div class="buttons">
                            <a href="users.php" class="btn btn-cancel">返回</a>
                            <button type="submit" class="btn btn-primary">保存更改</button>
                        </div>
                    </form>
                <?php endif; ?>
            </div>
        </div>
    </div>
</body>
</html> 