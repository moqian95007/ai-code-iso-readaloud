<?php
require_once 'functions.php';

// 检查用户是否已登录
if (!isLoggedIn()) {
    redirect('index.php');
}

$conn = connectDB();
$message = '';
$error = '';

// 处理订阅操作
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['action'])) {
        $action = $_POST['action'];
        $subscriptionId = isset($_POST['subscription_id']) ? $_POST['subscription_id'] : '';
        
        if ($action === 'update_status') {
            // 更新订阅状态
            $isActive = isset($_POST['is_active']) ? (int)$_POST['is_active'] : 0;
            
            $stmt = $conn->prepare("UPDATE user_subscriptions SET is_active = ?, updated_at = NOW() WHERE id = ?");
            $stmt->bind_param("is", $isActive, $subscriptionId);
            
            if ($stmt->execute()) {
                $message = '订阅状态已更新';
            } else {
                $error = '更新失败: ' . $conn->error;
            }
            $stmt->close();
        } elseif ($action === 'extend') {
            // 延长订阅有效期
            $days = isset($_POST['days']) ? (int)$_POST['days'] : 0;
            
            if ($days > 0) {
                $stmt = $conn->prepare("UPDATE user_subscriptions SET end_date = DATE_ADD(end_date, INTERVAL ? DAY), updated_at = NOW() WHERE id = ?");
                $stmt->bind_param("is", $days, $subscriptionId);
                
                if ($stmt->execute()) {
                    $message = "订阅有效期已延长 {$days} 天";
                } else {
                    $error = '延长失败: ' . $conn->error;
                }
                $stmt->close();
            } else {
                $error = '延长天数必须大于0';
            }
        } elseif ($action === 'add') {
            // 添加新订阅
            $userId = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
            $type = isset($_POST['subscription_type']) ? $_POST['subscription_type'] : '';
            $days = isset($_POST['duration']) ? (int)$_POST['duration'] : 0;
            
            if ($userId > 0 && !empty($type) && $days > 0) {
                // 检查用户是否存在
                $userStmt = $conn->prepare("SELECT id FROM users WHERE id = ?");
                $userStmt->bind_param("i", $userId);
                $userStmt->execute();
                $userResult = $userStmt->get_result();
                
                if ($userResult->num_rows === 1) {
                    // 生成UUID
                    $id = generateUuid();
                    $startDate = date('Y-m-d H:i:s');
                    $endDate = date('Y-m-d H:i:s', strtotime("+{$days} days"));
                    $subscriptionId = "manual_{$type}_" . time();
                    $isActive = 1;
                    $currentTime = date('Y-m-d H:i:s');
                    
                    // 如果添加新订阅，将此用户的其他订阅设为非活跃
                    $deactivateStmt = $conn->prepare("UPDATE user_subscriptions SET is_active = 0, updated_at = ? WHERE user_id = ?");
                    $deactivateStmt->bind_param("si", $currentTime, $userId);
                    $deactivateStmt->execute();
                    $deactivateStmt->close();
                    
                    // 插入新订阅
                    $stmt = $conn->prepare("INSERT INTO user_subscriptions (id, user_id, subscription_type, start_date, end_date, subscription_id, is_active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
                    $stmt->bind_param("sisssssss", $id, $userId, $type, $startDate, $endDate, $subscriptionId, $isActive, $currentTime, $currentTime);
                    
                    if ($stmt->execute()) {
                        $message = "已成功为用户ID {$userId} 添加 {$type} 类型的订阅";
                    } else {
                        $error = '添加订阅失败: ' . $conn->error;
                    }
                    $stmt->close();
                } else {
                    $error = '用户不存在';
                }
                $userStmt->close();
            } else {
                $error = '添加订阅需要有效的用户ID、订阅类型和天数';
            }
        }
    }
}

// 获取查询参数
$userId = isset($_GET['user_id']) ? (int)$_GET['user_id'] : 0;
$page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
$limit = 20;
$offset = ($page - 1) * $limit;
$whereClause = '';
$paramTypes = '';
$paramValues = [];

// 构建查询条件
if ($userId > 0) {
    $whereClause = 'WHERE user_id = ?';
    $paramTypes = 'i';
    $paramValues[] = $userId;
}

// 获取订阅总数
$countQuery = "SELECT COUNT(*) as total FROM user_subscriptions " . $whereClause;
$countStmt = $conn->prepare($countQuery);
if (!empty($paramTypes)) {
    $countStmt->bind_param($paramTypes, ...$paramValues);
}
$countStmt->execute();
$countResult = $countStmt->get_result();
$totalRows = $countResult->fetch_assoc()['total'];
$totalPages = ceil($totalRows / $limit);
$countStmt->close();

// 获取订阅列表
$subscriptions = [];
$query = "SELECT s.*, u.username 
         FROM user_subscriptions s 
         LEFT JOIN users u ON s.user_id = u.id 
         " . $whereClause . " 
         ORDER BY s.updated_at DESC 
         LIMIT ? OFFSET ?";

$stmt = $conn->prepare($query);
if (!empty($paramTypes)) {
    $paramTypes .= 'ii';
    $paramValues[] = $limit;
    $paramValues[] = $offset;
    $stmt->bind_param($paramTypes, ...$paramValues);
} else {
    $stmt->bind_param('ii', $limit, $offset);
}

$stmt->execute();
$result = $stmt->get_result();

while ($row = $result->fetch_assoc()) {
    $subscriptions[] = $row;
}
$stmt->close();

// 获取所有用户列表（用于添加订阅的下拉菜单）
$users = [];
$userQuery = "SELECT id, username, email FROM users ORDER BY username";
$userResult = $conn->query($userQuery);

if ($userResult) {
    while ($row = $userResult->fetch_assoc()) {
        $users[] = $row;
    }
    $userResult->free();
}

$conn->close();

// 生成UUID函数
function generateUuid() {
    if (function_exists('random_bytes')) {
        $data = random_bytes(16);
    } elseif (function_exists('openssl_random_pseudo_bytes')) {
        $data = openssl_random_pseudo_bytes(16);
    } else {
        $data = uniqid('', true);
    }
    
    $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
    $data[8] = chr(ord($data[8]) & 0x3f | 0x80);
    
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

// 获取订阅类型名称
function getSubscriptionTypeName($type) {
    switch ($type) {
        case 'monthly':
            return '月度会员';
        case 'quarterly':
            return '季度会员';
        case 'halfYearly':
            return '半年会员';
        case 'yearly':
            return '年度会员';
        default:
            return $type;
    }
}
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ReadAloud 后台管理系统 - 订阅管理</title>
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
        .table-container {
            overflow-x: auto;
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
        .message, .error {
            padding: 10px;
            margin-bottom: 20px;
            border-radius: 3px;
        }
        .message {
            background-color: #d4edda;
            color: #155724;
        }
        .error {
            background-color: #f8d7da;
            color: #721c24;
        }
        .action-btn {
            display: inline-block;
            padding: 5px 10px;
            margin: 2px;
            border-radius: 3px;
            text-decoration: none;
            color: white;
            cursor: pointer;
            font-size: 12px;
        }
        .update-btn {
            background-color: #3498db;
        }
        .update-btn:hover {
            background-color: #2980b9;
        }
        .extend-btn {
            background-color: #2ecc71;
        }
        .extend-btn:hover {
            background-color: #27ae60;
        }
        .delete-btn {
            background-color: #e74c3c;
        }
        .delete-btn:hover {
            background-color: #c0392b;
        }
        .form-group {
            margin-bottom: 15px;
        }
        .form-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        .form-group input, .form-group select {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 3px;
            box-sizing: border-box;
        }
        .btn {
            padding: 8px 15px;
            border: none;
            border-radius: 3px;
            cursor: pointer;
            font-weight: bold;
        }
        .btn-primary {
            background-color: #3498db;
            color: white;
        }
        .btn-primary:hover {
            background-color: #2980b9;
        }
        .active-tag {
            display: inline-block;
            padding: 3px 6px;
            border-radius: 3px;
            font-size: 12px;
            color: white;
        }
        .active-true {
            background-color: #2ecc71;
        }
        .active-false {
            background-color: #95a5a6;
        }
        .pagination {
            margin-top: 20px;
            text-align: center;
        }
        .pagination a, .pagination span {
            display: inline-block;
            padding: 5px 10px;
            margin: 0 2px;
            border: 1px solid #ddd;
            text-decoration: none;
            color: #333;
        }
        .pagination a:hover {
            background-color: #f2f2f2;
        }
        .pagination .current {
            background-color: #3498db;
            color: white;
            border-color: #3498db;
        }
        .filter-form {
            display: flex;
            margin-bottom: 20px;
            align-items: flex-end;
        }
        .filter-form .form-group {
            margin-right: 10px;
            margin-bottom: 0;
            flex: 1;
        }
        .filter-form button {
            margin-left: 10px;
            height: 36px;
        }
        .tab-container {
            margin-bottom: 20px;
        }
        .tab {
            display: inline-block;
            padding: 10px 15px;
            cursor: pointer;
            border: 1px solid #ddd;
            border-bottom: none;
            background-color: #f9f9f9;
            margin-right: 5px;
            border-radius: 5px 5px 0 0;
        }
        .tab.active {
            background-color: white;
            border-bottom: 1px solid white;
            margin-bottom: -1px;
            position: relative;
        }
        .tab-content {
            display: none;
            border: 1px solid #ddd;
            padding: 20px;
            background-color: white;
        }
        .tab-content.active {
            display: block;
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
                <h2>订阅管理</h2>
                
                <?php if (!empty($message)): ?>
                    <div class="message"><?php echo $message; ?></div>
                <?php endif; ?>
                
                <?php if (!empty($error)): ?>
                    <div class="error"><?php echo $error; ?></div>
                <?php endif; ?>
                
                <div class="tab-container">
                    <div class="tab active" onclick="openTab(event, 'subscription-list')">订阅列表</div>
                    <div class="tab" onclick="openTab(event, 'add-subscription')">添加订阅</div>
                </div>
                
                <div id="subscription-list" class="tab-content active">
                    <div class="filter-form">
                        <form method="get" action="">
                            <div class="form-group">
                                <label for="user_id">按用户ID筛选</label>
                                <input type="number" id="user_id" name="user_id" value="<?php echo $userId; ?>" min="0">
                            </div>
                            <button type="submit" class="btn btn-primary">筛选</button>
                            <?php if ($userId > 0): ?>
                                <a href="subscriptions.php" class="btn" style="margin-left:10px;">重置</a>
                            <?php endif; ?>
                        </form>
                    </div>
                    
                    <div class="table-container">
                        <table>
                            <thead>
                                <tr>
                                    <th>ID</th>
                                    <th>用户ID</th>
                                    <th>用户名</th>
                                    <th>订阅类型</th>
                                    <th>开始日期</th>
                                    <th>结束日期</th>
                                    <th>状态</th>
                                    <th>创建时间</th>
                                    <th>更新时间</th>
                                    <th>操作</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php if (empty($subscriptions)): ?>
                                    <tr>
                                        <td colspan="10" style="text-align: center;">没有找到订阅记录</td>
                                    </tr>
                                <?php else: ?>
                                    <?php foreach ($subscriptions as $subscription): ?>
                                        <tr>
                                            <td><?php echo substr($subscription['id'], 0, 8); ?>...</td>
                                            <td><?php echo $subscription['user_id']; ?></td>
                                            <td><?php echo htmlspecialchars($subscription['username'] ?? 'Unknown'); ?></td>
                                            <td><?php echo getSubscriptionTypeName($subscription['subscription_type']); ?></td>
                                            <td><?php echo $subscription['start_date']; ?></td>
                                            <td><?php echo $subscription['end_date']; ?></td>
                                            <td>
                                                <span class="active-tag active-<?php echo $subscription['is_active'] ? 'true' : 'false'; ?>">
                                                    <?php echo $subscription['is_active'] ? '活跃' : '非活跃'; ?>
                                                </span>
                                            </td>
                                            <td><?php echo $subscription['created_at']; ?></td>
                                            <td><?php echo $subscription['updated_at']; ?></td>
                                            <td>
                                                <form method="post" action="" style="display:inline;">
                                                    <input type="hidden" name="action" value="update_status">
                                                    <input type="hidden" name="subscription_id" value="<?php echo $subscription['id']; ?>">
                                                    <input type="hidden" name="is_active" value="<?php echo $subscription['is_active'] ? '0' : '1'; ?>">
                                                    <button type="submit" class="action-btn update-btn">
                                                        <?php echo $subscription['is_active'] ? '设为非活跃' : '设为活跃'; ?>
                                                    </button>
                                                </form>
                                                
                                                <button type="button" class="action-btn extend-btn" onclick="showExtendForm('<?php echo $subscription['id']; ?>')">延长有效期</button>
                                                
                                                <div id="extend-form-<?php echo $subscription['id']; ?>" style="display:none; margin-top:5px;">
                                                    <form method="post" action="">
                                                        <input type="hidden" name="action" value="extend">
                                                        <input type="hidden" name="subscription_id" value="<?php echo $subscription['id']; ?>">
                                                        <input type="number" name="days" placeholder="天数" min="1" max="365" required style="width:60px;">
                                                        <button type="submit" class="action-btn extend-btn">确认</button>
                                                    </form>
                                                </div>
                                            </td>
                                        </tr>
                                    <?php endforeach; ?>
                                <?php endif; ?>
                            </tbody>
                        </table>
                    </div>
                    
                    <?php if ($totalPages > 1): ?>
                        <div class="pagination">
                            <?php if ($page > 1): ?>
                                <a href="?page=<?php echo $page-1; ?><?php echo $userId ? '&user_id=' . $userId : ''; ?>">&laquo; 上一页</a>
                            <?php endif; ?>
                            
                            <?php for ($i = 1; $i <= $totalPages; $i++): ?>
                                <?php if ($i == $page): ?>
                                    <span class="current"><?php echo $i; ?></span>
                                <?php else: ?>
                                    <a href="?page=<?php echo $i; ?><?php echo $userId ? '&user_id=' . $userId : ''; ?>"><?php echo $i; ?></a>
                                <?php endif; ?>
                            <?php endfor; ?>
                            
                            <?php if ($page < $totalPages): ?>
                                <a href="?page=<?php echo $page+1; ?><?php echo $userId ? '&user_id=' . $userId : ''; ?>">下一页 &raquo;</a>
                            <?php endif; ?>
                        </div>
                    <?php endif; ?>
                </div>
                
                <div id="add-subscription" class="tab-content">
                    <form method="post" action="">
                        <input type="hidden" name="action" value="add">
                        
                        <div class="form-group">
                            <label for="add_user_id">用户</label>
                            <select id="add_user_id" name="user_id" required>
                                <option value="">-- 选择用户 --</option>
                                <?php foreach ($users as $user): ?>
                                    <option value="<?php echo $user['id']; ?>"><?php echo htmlspecialchars($user['username']); ?> (<?php echo htmlspecialchars($user['email']); ?>)</option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        
                        <div class="form-group">
                            <label for="subscription_type">订阅类型</label>
                            <select id="subscription_type" name="subscription_type" required>
                                <option value="">-- 选择订阅类型 --</option>
                                <option value="monthly">月度会员</option>
                                <option value="quarterly">季度会员</option>
                                <option value="halfYearly">半年会员</option>
                                <option value="yearly">年度会员</option>
                            </select>
                        </div>
                        
                        <div class="form-group">
                            <label for="duration">有效期（天）</label>
                            <input type="number" id="duration" name="duration" min="1" max="3650" required>
                        </div>
                        
                        <button type="submit" class="btn btn-primary">添加订阅</button>
                    </form>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        function showExtendForm(subscriptionId) {
            var formId = 'extend-form-' + subscriptionId;
            var form = document.getElementById(formId);
            if (form.style.display === 'none') {
                form.style.display = 'block';
            } else {
                form.style.display = 'none';
            }
        }
        
        function openTab(evt, tabId) {
            var i, tabContent, tabLinks;
            
            // 隐藏所有标签内容
            tabContent = document.getElementsByClassName("tab-content");
            for (i = 0; i < tabContent.length; i++) {
                tabContent[i].classList.remove("active");
            }
            
            // 移除所有标签的活跃状态
            tabLinks = document.getElementsByClassName("tab");
            for (i = 0; i < tabLinks.length; i++) {
                tabLinks[i].classList.remove("active");
            }
            
            // 显示当前标签内容，设置当前标签为活跃
            document.getElementById(tabId).classList.add("active");
            evt.currentTarget.classList.add("active");
        }
    </script>
</body>
</html> 