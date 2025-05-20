<?php
require_once 'functions.php';

// 检查用户是否已登录
if (!isLoggedIn()) {
    redirect('index.php');
}

$conn = connectDB();
$message = '';

try {
    // 1. 获取SQL文件内容
    $sqlFilePath = __DIR__ . '/sql/update_import_count.sql';
    $sqlContent = file_get_contents($sqlFilePath);
    
    if (!$sqlContent) {
        throw new Exception("无法读取SQL文件");
    }
    
    // 2. 分割SQL语句
    $sqlStatements = explode(';', $sqlContent);
    
    // 3. 执行每一条SQL语句
    $executed = 0;
    foreach ($sqlStatements as $sql) {
        $sql = trim($sql);
        if (empty($sql)) continue;
        
        if ($conn->query($sql)) {
            $executed++;
        } else {
            // 如果字段已存在，会报错，但不影响功能
            if (strpos($conn->error, 'Duplicate column name') !== false) {
                $message .= "字段 remaining_import_count 已存在，跳过。<br>";
            } else {
                throw new Exception("执行SQL失败: " . $conn->error);
            }
        }
    }
    
    $message = "数据库更新成功！执行了 {$executed} 条SQL语句。";
    
} catch (Exception $e) {
    $message = "错误: " . $e->getMessage();
}

$conn->close();
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ReadAloud 后台管理系统 - 数据库更新</title>
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
        .message {
            padding: 10px;
            margin-bottom: 20px;
            background-color: #d4edda;
            color: #155724;
            border-radius: 3px;
        }
        .error {
            background-color: #f8d7da;
            color: #721c24;
        }
        .btn {
            padding: 10px 15px;
            border: none;
            border-radius: 3px;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
            margin-top: 10px;
        }
        .btn-primary {
            background-color: #3498db;
            color: white;
        }
        .btn-primary:hover {
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
                <h2>数据库更新</h2>
                
                <?php if (!empty($message)): ?>
                    <div class="message <?php echo strpos($message, '错误') !== false ? 'error' : ''; ?>">
                        <?php echo $message; ?>
                    </div>
                <?php endif; ?>
                
                <p>此页面用于更新数据库结构，添加剩余导入数量字段。</p>
                
                <a href="users.php" class="btn btn-primary">返回用户管理</a>
            </div>
        </div>
    </div>
</body>
</html> 