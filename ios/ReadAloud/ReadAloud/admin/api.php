<?php
require_once 'functions.php';

// 检查用户是否已登录
if (!isLoggedIn()) {
    redirect('index.php');
}
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ReadAloud 后台管理系统 - API接口</title>
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
        .api-section {
            margin-bottom: 30px;
        }
        .api-endpoint {
            background-color: #f9f9f9;
            padding: 15px;
            margin-bottom: 15px;
            border-left: 4px solid #3498db;
        }
        .api-endpoint h3 {
            margin-top: 0;
            color: #333;
        }
        pre {
            background-color: #f4f4f4;
            padding: 10px;
            border-radius: 3px;
            overflow-x: auto;
        }
        code {
            font-family: Consolas, Monaco, 'Andale Mono', monospace;
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
                <li><a href="user_data.php">用户数据</a></li>
                <li><a href="api.php">API接口</a></li>
            </ul>
        </div>
        
        <div class="content">
            <div class="card">
                <h2>API接口文档</h2>
                
                <div class="api-section">
                    <h3>接口基础信息</h3>
                    <p>所有API接口均使用 HTTP POST 方法，返回 JSON 格式数据。</p>
                    <p>基础URL: <code>/api/</code></p>
                    <p>所有响应都包含 <code>status</code> 字段，表示请求状态，成功为 "success"，失败为 "error"。</p>
                </div>
                
                <div class="api-section">
                    <h3>用户接口</h3>
                    
                    <div class="api-endpoint">
                        <h3>1. 用户注册</h3>
                        <p><strong>端点:</strong> <code>/api/register.php</code></p>
                        <p><strong>描述:</strong> 注册新用户</p>
                        <p><strong>参数:</strong></p>
                        <pre><code>
{
    "username": "用户名",
    "password": "密码",
    "email": "电子邮箱",
    "phone": "手机号码" (可选)
}
                        </code></pre>
                        <p><strong>响应:</strong></p>
                        <pre><code>
// 成功
{
    "status": "success",
    "message": "注册成功",
    "user_id": 123
}

// 失败
{
    "status": "error",
    "message": "用户名已存在"
}
                        </code></pre>
                    </div>
                    
                    <div class="api-endpoint">
                        <h3>2. 用户登录</h3>
                        <p><strong>端点:</strong> <code>/api/login.php</code></p>
                        <p><strong>描述:</strong> 用户登录</p>
                        <p><strong>参数:</strong></p>
                        <pre><code>
{
    "username": "用户名",
    "password": "密码"
}
                        </code></pre>
                        <p><strong>响应:</strong></p>
                        <pre><code>
// 成功
{
    "status": "success",
    "message": "登录成功",
    "user_id": 123,
    "token": "认证令牌"
}

// 失败
{
    "status": "error",
    "message": "用户名或密码错误"
}
                        </code></pre>
                    </div>
                </div>
                
                <div class="api-section">
                    <h3>用户数据接口</h3>
                    
                    <div class="api-endpoint">
                        <h3>1. 获取用户数据</h3>
                        <p><strong>端点:</strong> <code>/api/get_user_data.php</code></p>
                        <p><strong>描述:</strong> 获取用户存储的数据</p>
                        <p><strong>参数:</strong></p>
                        <pre><code>
{
    "user_id": 123,
    "token": "认证令牌",
    "data_key": "要获取的数据键" (可选，不提供则获取所有)
}
                        </code></pre>
                        <p><strong>响应:</strong></p>
                        <pre><code>
// 成功
{
    "status": "success",
    "data": {
        "key1": "值1",
        "key2": "值2"
    }
}

// 失败
{
    "status": "error",
    "message": "认证失败"
}
                        </code></pre>
                    </div>
                    
                    <div class="api-endpoint">
                        <h3>2. 保存用户数据</h3>
                        <p><strong>端点:</strong> <code>/api/save_user_data.php</code></p>
                        <p><strong>描述:</strong> 保存用户数据</p>
                        <p><strong>参数:</strong></p>
                        <pre><code>
{
    "user_id": 123,
    "token": "认证令牌",
    "data_key": "数据键",
    "data_value": "数据值"
}
                        </code></pre>
                        <p><strong>响应:</strong></p>
                        <pre><code>
// 成功
{
    "status": "success",
    "message": "数据保存成功"
}

// 失败
{
    "status": "error",
    "message": "认证失败"
}
                        </code></pre>
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html> 