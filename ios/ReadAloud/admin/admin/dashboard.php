<?php
require_once 'functions.php';

// 检查用户是否已登录
if (!isLoggedIn()) {
    redirect('index.php');
}

$conn = connectDB();

// 获取各种统计数据
$totalUsers = 0;
$totalActiveUsers = 0;
$totalSubscriptions = 0;
$totalActiveSubscriptions = 0;

// 获取用户数量
$result = $conn->query("SELECT COUNT(*) as total FROM users");
if ($result && $row = $result->fetch_assoc()) {
    $totalUsers = $row['total'];
}

// 获取活跃用户数量
$result = $conn->query("SELECT COUNT(*) as total FROM users WHERE status = 'active'");
if ($result && $row = $result->fetch_assoc()) {
    $totalActiveUsers = $row['total'];
}

// 获取订阅数量
$result = $conn->query("SELECT COUNT(*) as total FROM user_subscriptions");
if ($result && $row = $result->fetch_assoc()) {
    $totalSubscriptions = $row['total'];
}

// 获取活跃订阅数量
$result = $conn->query("SELECT COUNT(*) as total FROM user_subscriptions WHERE is_active = 1 AND end_date > NOW()");
if ($result && $row = $result->fetch_assoc()) {
    $totalActiveSubscriptions = $row['total'];
}

$conn->close();
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ReadAloud 后台管理系统 - 仪表盘</title>
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
        .stats-container {
            display: flex;
            flex-wrap: wrap;
            margin: 0 -10px;
        }
        .stat-box {
            flex: 1;
            min-width: 200px;
            margin: 10px;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
            text-align: center;
            background-color: white;
        }
        .stat-box h3 {
            margin-top: 0;
            color: #333;
        }
        .stat-number {
            font-size: 36px;
            font-weight: bold;
            margin: 15px 0;
        }
        .users-stat {
            border-left: 4px solid #3498db;
        }
        .users-stat .stat-number {
            color: #3498db;
        }
        .active-users-stat {
            border-left: 4px solid #2ecc71;
        }
        .active-users-stat .stat-number {
            color: #2ecc71;
        }
        .subscriptions-stat {
            border-left: 4px solid #e67e22;
        }
        .subscriptions-stat .stat-number {
            color: #e67e22;
        }
        .active-subscriptions-stat {
            border-left: 4px solid #f1c40f;
        }
        .active-subscriptions-stat .stat-number {
            color: #f1c40f;
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
                <h2>系统概览</h2>
                <div class="stats-container">
                    <div class="stat-box users-stat">
                        <h3>总用户数</h3>
                        <div class="stat-number"><?php echo $totalUsers; ?></div>
                        <div>注册用户总数</div>
                    </div>
                    
                    <div class="stat-box active-users-stat">
                        <h3>活跃用户数</h3>
                        <div class="stat-number"><?php echo $totalActiveUsers; ?></div>
                        <div>状态为活跃的用户数</div>
                    </div>
                    
                    <div class="stat-box subscriptions-stat">
                        <h3>总订阅数</h3>
                        <div class="stat-number"><?php echo $totalSubscriptions; ?></div>
                        <div>订阅记录总数</div>
                    </div>
                    
                    <div class="stat-box active-subscriptions-stat">
                        <h3>有效订阅数</h3>
                        <div class="stat-number"><?php echo $totalActiveSubscriptions; ?></div>
                        <div>当前有效的订阅数</div>
                    </div>
                </div>
            </div>
            
            <div class="card">
                <h2>快捷操作</h2>
                <p>这里是快捷操作区域，您可以添加常用功能链接。</p>
                <ul>
                    <li><a href="users.php">查看用户列表</a></li>
                    <li><a href="subscriptions.php">管理订阅</a></li>
                    <li><a href="user_data.php">查看用户数据</a></li>
                </ul>
            </div>
        </div>
    </div>
</body>
</html> 