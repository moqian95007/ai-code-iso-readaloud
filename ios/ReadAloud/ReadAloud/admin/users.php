<?php
require_once 'functions.php';

// 检查用户是否已登录
if (!isLoggedIn()) {
    redirect('index.php');
}

$conn = connectDB();
$message = '';

// 处理用户状态更新
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'update') {
    $userId = (int)$_POST['user_id'];
    $status = cleanInput($_POST['status']);
    
    $stmt = $conn->prepare("UPDATE users SET status = ? WHERE id = ?");
    $stmt->bind_param("si", $status, $userId);
    
    if ($stmt->execute()) {
        $message = '用户状态已更新';
    } else {
        $message = '更新失败: ' . $conn->error;
    }
    $stmt->close();
}

// 处理剩余导入数量更新
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'update_import_count') {
    $userId = (int)$_POST['user_id'];
    $importCount = (int)$_POST['remaining_import_count'];
    
    // 确保数量不为负数
    if ($importCount < 0) {
        $importCount = 0;
    }
    
    $stmt = $conn->prepare("UPDATE users SET remaining_import_count = ? WHERE id = ?");
    $stmt->bind_param("ii", $importCount, $userId);
    
    if ($stmt->execute()) {
        $message = '用户剩余导入数量已更新';
    } else {
        $message = '更新失败: ' . $conn->error;
    }
    $stmt->close();
}

// 获取所有用户
$users = [];
$result = $conn->query("SELECT id, username, email, phone, register_date, last_login, status, remaining_import_count FROM users ORDER BY register_date DESC");

if ($result) {
    while ($row = $result->fetch_assoc()) {
        $users[] = $row;
    }
    $result->free();
}

$conn->close();
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ReadAloud 后台管理系统 - 用户管理</title>
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
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        th, td {
            padding: 10px;
            border: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
        tr:hover {
            background-color: #f9f9f9;
        }
        .message {
            padding: 10px;
            margin-bottom: 20px;
            background-color: #d4edda;
            color: #155724;
            border-radius: 3px;
        }
        select, button {
            padding: 5px 10px;
            border: 1px solid #ddd;
            border-radius: 3px;
            background-color: white;
        }
        button {
            background-color: #3498db;
            color: white;
            border: none;
            cursor: pointer;
        }
        button:hover {
            background-color: #2980b9;
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
                <h2>用户管理</h2>
                
                <?php if (!empty($message)): ?>
                    <div class="message"><?php echo $message; ?></div>
                <?php endif; ?>
                
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>用户名</th>
                            <th>邮箱</th>
                            <th>手机号</th>
                            <th>注册日期</th>
                            <th>最后登录</th>
                            <th>状态</th>
                            <th>剩余导入次数</th>
                            <th>操作</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($users)): ?>
                            <tr>
                                <td colspan="9" style="text-align: center;">没有找到用户</td>
                            </tr>
                        <?php else: ?>
                            <?php foreach ($users as $user): ?>
                                <tr>
                                    <td><?php echo $user['id']; ?></td>
                                    <td><?php echo htmlspecialchars($user['username']); ?></td>
                                    <td><?php echo htmlspecialchars($user['email']); ?></td>
                                    <td><?php echo htmlspecialchars($user['phone']); ?></td>
                                    <td><?php echo $user['register_date']; ?></td>
                                    <td><?php echo $user['last_login']; ?></td>
                                    <td>
                                        <form method="post" action="" style="display:inline;">
                                            <input type="hidden" name="action" value="update">
                                            <input type="hidden" name="user_id" value="<?php echo $user['id']; ?>">
                                            <select name="status">
                                                <option value="active" <?php echo $user['status'] === 'active' ? 'selected' : ''; ?>>激活</option>
                                                <option value="inactive" <?php echo $user['status'] === 'inactive' ? 'selected' : ''; ?>>禁用</option>
                                            </select>
                                            <button type="submit">更新</button>
                                        </form>
                                    </td>
                                    <td>
                                        <form method="post" action="" style="display:inline;">
                                            <input type="hidden" name="action" value="update_import_count">
                                            <input type="hidden" name="user_id" value="<?php echo $user['id']; ?>">
                                            <input type="number" name="remaining_import_count" value="<?php echo isset($user['remaining_import_count']) ? (int)$user['remaining_import_count'] : 1; ?>" min="0" style="width: 60px;">
                                            <button type="submit">更新</button>
                                        </form>
                                    </td>
                                    <td>
                                        <a href="edit_user.php?id=<?php echo $user['id']; ?>">编辑</a>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</body>
</html> 