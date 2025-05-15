<?php
require_once 'functions.php';
require_once 'config.php';

// 检查用户是否已登录
if (!isLoggedIn()) {
    redirect('index.php');
}

$username = $_SESSION['admin_username'];
$conn = connectDB();

// 初始化变量
$message = '';
$filteredUserId = '';
$filteredUserName = '';

// 处理删除请求
if (isset($_POST['delete']) && isset($_POST['id'])) {
    $id = (int)$_POST['id'];
    $stmt = $conn->prepare("DELETE FROM user_data WHERE id = ?");
    $stmt->bind_param("i", $id);
    
    if ($stmt->execute()) {
        $message = "数据记录已成功删除";
    } else {
        $message = "删除失败: " . $conn->error;
    }
    $stmt->close();
}

// 处理用户过滤
if (isset($_GET['filter_user'])) {
    $filteredUserId = (int)$_GET['filter_user'];
    
    // 获取用户名
    $stmt = $conn->prepare("SELECT username FROM users WHERE id = ?");
    $stmt->bind_param("i", $filteredUserId);
    $stmt->execute();
    $result = $stmt->get_result();
    if ($row = $result->fetch_assoc()) {
        $filteredUserName = $row['username'];
    }
    $stmt->close();
}

// 获取所有用户列表（用于过滤下拉框）
$userList = [];
$stmt = $conn->prepare("SELECT id, username FROM users ORDER BY username");
$stmt->execute();
$result = $stmt->get_result();
while ($row = $result->fetch_assoc()) {
    $userList[] = $row;
}
$stmt->close();

// 获取用户数据
$query = "SELECT ud.id, ud.user_id, u.username, ud.data_key, ud.data_value, ud.created_at, ud.updated_at 
          FROM user_data ud 
          LEFT JOIN users u ON ud.user_id = u.id";

// 添加过滤条件
if ($filteredUserId) {
    $query .= " WHERE ud.user_id = " . $filteredUserId;
}

$query .= " ORDER BY ud.updated_at DESC";
$result = $conn->query($query);
?>

<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ReadAloud 后台管理系统 - 用户数据</title>
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
            overflow-x: auto;
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
            border: 1px solid #ddd;
            padding: 8px 12px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
            position: sticky;
            top: 0;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        tr:hover {
            background-color: #f1f1f1;
        }
        .filter-section {
            margin: 15px 0;
            display: flex;
            align-items: center;
        }
        .filter-section select, .filter-section button {
            padding: 8px 12px;
            margin-right: 10px;
        }
        .reset-btn {
            background-color: #3498db;
            color: white;
            border: none;
            border-radius: 3px;
            cursor: pointer;
        }
        .reset-btn:hover {
            background-color: #2980b9;
        }
        .delete-btn {
            background-color: #e74c3c;
            color: white;
            border: none;
            padding: 4px 8px;
            border-radius: 3px;
            cursor: pointer;
        }
        .delete-btn:hover {
            background-color: #c0392b;
        }
        .success-message {
            background-color: #dff0d8;
            color: #3c763d;
            padding: 10px;
            margin-bottom: 20px;
            border-radius: 3px;
        }
        .error-message {
            background-color: #f2dede;
            color: #a94442;
            padding: 10px;
            margin-bottom: 20px;
            border-radius: 3px;
        }
        .data-value-container {
            max-height: 150px;
            overflow-y: auto;
            word-break: break-all;
            white-space: pre-wrap;
        }
        .view-all-btn {
            margin-top: 5px;
            background-color: #3498db;
            color: white;
            border: none;
            padding: 4px 8px;
            border-radius: 3px;
            cursor: pointer;
        }
        .view-all-btn:hover {
            background-color: #2980b9;
        }
        .modal {
            display: none;
            position: fixed;
            z-index: 1000;
            left: 0;
            top: 0;
            width: 100%;
            height: 100%;
            background-color: rgba(0,0,0,0.7);
        }
        .modal-content {
            position: relative;
            background-color: white;
            margin: 5% auto;
            padding: 20px;
            width: 80%;
            max-width: 800px;
            max-height: 80vh;
            overflow-y: auto;
            border-radius: 5px;
        }
        .close {
            position: absolute;
            right: 20px;
            top: 10px;
            font-size: 28px;
            font-weight: bold;
            cursor: pointer;
        }
        .pagination {
            display: flex;
            justify-content: center;
            margin-top: 20px;
        }
        .pagination a, .pagination span {
            padding: 8px 12px;
            margin: 0 5px;
            border: 1px solid #ddd;
            text-decoration: none;
            color: #333;
            border-radius: 3px;
        }
        .pagination a:hover {
            background-color: #f4f4f4;
        }
        .pagination .active {
            background-color: #3498db;
            color: white;
            border-color: #3498db;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>ReadAloud 后台管理系统</h1>
        <div class="user-info">
            <span>欢迎，<?php echo htmlspecialchars($username); ?></span>
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
                <h2>用户持久化数据</h2>
                
                <?php if(!empty($message)): ?>
                <div class="<?php echo strpos($message, '成功') !== false ? 'success-message' : 'error-message'; ?>">
                    <?php echo $message; ?>
                </div>
                <?php endif; ?>
                
                <div class="filter-section">
                    <form method="get" action="">
                        <label for="filter_user">按用户筛选：</label>
                        <select name="filter_user" id="filter_user">
                            <option value="">-- 所有用户 --</option>
                            <?php foreach ($userList as $user): ?>
                            <option value="<?php echo $user['id']; ?>" <?php echo ($filteredUserId == $user['id']) ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($user['username']); ?> (ID: <?php echo $user['id']; ?>)
                            </option>
                            <?php endforeach; ?>
                        </select>
                        <button type="submit" class="reset-btn">应用筛选</button>
                        <?php if ($filteredUserId): ?>
                        <a href="user_data.php" class="reset-btn" style="text-decoration: none;">重置筛选</a>
                        <?php endif; ?>
                    </form>
                </div>
                
                <?php if ($filteredUserName): ?>
                <p>当前筛选：用户 "<?php echo htmlspecialchars($filteredUserName); ?>" (ID: <?php echo $filteredUserId; ?>)</p>
                <?php endif; ?>
                
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>用户ID</th>
                            <th>用户名</th>
                            <th>数据键</th>
                            <th>数据值</th>
                            <th>创建时间</th>
                            <th>更新时间</th>
                            <th>操作</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if ($result->num_rows > 0): ?>
                            <?php while ($row = $result->fetch_assoc()): ?>
                                <?php 
                                // 准备数据值的显示
                                $dataValue = htmlspecialchars($row['data_value']);
                                $shortDataValue = mb_strlen($dataValue) > 100 ? mb_substr($dataValue, 0, 100) . '...' : $dataValue;
                                $dataId = $row['id'];
                                ?>
                                <tr>
                                    <td><?php echo $row['id']; ?></td>
                                    <td><?php echo $row['user_id']; ?></td>
                                    <td><?php echo htmlspecialchars($row['username']); ?></td>
                                    <td><?php echo htmlspecialchars($row['data_key']); ?></td>
                                    <td>
                                        <div class="data-value-container" id="data-short-<?php echo $dataId; ?>">
                                            <?php echo $shortDataValue; ?>
                                        </div>
                                        <?php if (mb_strlen($dataValue) > 100): ?>
                                            <button class="view-all-btn" onclick="viewFullData(<?php echo $dataId; ?>)">查看全部</button>
                                        <?php endif; ?>
                                    </td>
                                    <td><?php echo $row['created_at']; ?></td>
                                    <td><?php echo $row['updated_at']; ?></td>
                                    <td>
                                        <form method="post" action="" onsubmit="return confirm('确定要删除这条数据吗？此操作不可撤销。');">
                                            <input type="hidden" name="id" value="<?php echo $row['id']; ?>">
                                            <button type="submit" name="delete" class="delete-btn">删除</button>
                                        </form>
                                    </td>
                                </tr>
                            <?php endwhile; ?>
                        <?php else: ?>
                            <tr>
                                <td colspan="8" style="text-align: center;">没有找到用户数据</td>
                            </tr>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    
    <!-- 数据全文查看模态框 -->
    <div id="dataModal" class="modal">
        <div class="modal-content">
            <span class="close" onclick="closeModal()">&times;</span>
            <h3>数据详情</h3>
            <pre id="fullDataContent" style="white-space: pre-wrap; word-break: break-all; max-height: 500px; overflow-y: auto;"></pre>
        </div>
    </div>
    
    <script>
        // 全局存储数据的对象
        const fullDataValues = {};
        
        <?php 
        // 重置结果指针
        $result->data_seek(0);
        while ($row = $result->fetch_assoc()): 
        ?>
            fullDataValues[<?php echo $row['id']; ?>] = <?php echo json_encode($row['data_value']); ?>;
        <?php endwhile; ?>
        
        // 查看完整数据的函数
        function viewFullData(id) {
            const modal = document.getElementById('dataModal');
            const contentDiv = document.getElementById('fullDataContent');
            
            // 设置内容
            contentDiv.textContent = fullDataValues[id] || '数据不可用';
            
            // 显示模态框
            modal.style.display = 'block';
            
            // 尝试格式化JSON
            try {
                const jsonData = JSON.parse(fullDataValues[id]);
                contentDiv.textContent = JSON.stringify(jsonData, null, 2);
            } catch (e) {
                // 不是有效的JSON，保持原样
            }
        }
        
        // 关闭模态框
        function closeModal() {
            document.getElementById('dataModal').style.display = 'none';
        }
        
        // 点击模态框外部关闭
        window.onclick = function(event) {
            const modal = document.getElementById('dataModal');
            if (event.target === modal) {
                modal.style.display = 'none';
            }
        }
    </script>
</body>
</html>

<?php
// 关闭数据库连接
$conn->close();
?> 