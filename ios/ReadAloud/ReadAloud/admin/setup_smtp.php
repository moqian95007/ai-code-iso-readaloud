<?php
/**
 * SMTP配置页面
 * 允许用户配置第三方SMTP服务器信息
 */

// 定义配置文件路径
$configFile = __DIR__ . '/mail_config.php';

// 处理表单提交
$message = '';
$messageType = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['save_config'])) {
    // 获取表单数据
    $useSmtp = isset($_POST['use_smtp']) ? (bool)$_POST['use_smtp'] : false;
    $smtpHost = $_POST['smtp_host'] ?? '';
    $smtpPort = (int)($_POST['smtp_port'] ?? 587);
    $smtpUsername = $_POST['smtp_username'] ?? '';
    $smtpPassword = $_POST['smtp_password'] ?? '';
    $smtpEncryption = $_POST['smtp_encryption'] ?? 'tls';
    $fromAddress = $_POST['from_address'] ?? '';
    $fromName = $_POST['from_name'] ?? 'ReadAloud';
    $debug = isset($_POST['debug_mode']) ? (bool)$_POST['debug_mode'] : false;
    $useDirectMail = isset($_POST['use_direct_mail']) ? (bool)$_POST['use_direct_mail'] : false;
    $verifySSL = isset($_POST['verify_ssl']) ? (bool)$_POST['verify_ssl'] : true;
    
    try {
        // 读取原配置文件
        if (file_exists($configFile)) {
            $configContent = file_get_contents($configFile);
        } else {
            $configContent = '<?php' . PHP_EOL;
        }
        
        // 创建新配置内容
        $newConfig = '<?php' . PHP_EOL;
        $newConfig .= '/**' . PHP_EOL;
        $newConfig .= ' * 邮件服务器配置文件' . PHP_EOL;
        $newConfig .= ' * 由setup_smtp.php自动生成于 ' . date('Y-m-d H:i:s') . PHP_EOL;
        $newConfig .= ' */' . PHP_EOL . PHP_EOL;
        
        // 邮件模式配置
        $newConfig .= '// 邮件发送模式' . PHP_EOL;
        $newConfig .= 'define(\'USE_SIMPLE_MAIL\', ' . ($useSmtp ? 'false' : 'true') . '); // 是否使用PHP内置mail()函数' . PHP_EOL . PHP_EOL;
        
        // 发件人设置
        $newConfig .= '// 发件人设置' . PHP_EOL;
        $newConfig .= 'define(\'MAIL_FROM_ADDRESS\', \'' . addslashes($fromAddress) . '\'); // 发件人地址' . PHP_EOL;
        $newConfig .= 'define(\'MAIL_FROM_NAME\', \'' . addslashes($fromName) . '\'); // 发件人名称' . PHP_EOL . PHP_EOL;
        
        // SMTP设置
        $newConfig .= '// SMTP服务器配置' . PHP_EOL;
        $newConfig .= 'define(\'MAIL_HOST\', \'' . addslashes($smtpHost) . '\'); // SMTP服务器' . PHP_EOL;
        $newConfig .= 'define(\'MAIL_PORT\', ' . $smtpPort . '); // SMTP端口' . PHP_EOL;
        $newConfig .= 'define(\'MAIL_USERNAME\', \'' . addslashes($smtpUsername) . '\'); // SMTP用户名' . PHP_EOL;
        $newConfig .= 'define(\'MAIL_PASSWORD\', \'' . addslashes($smtpPassword) . '\'); // SMTP密码' . PHP_EOL;
        $newConfig .= 'define(\'MAIL_ENCRYPTION\', \'' . addslashes($smtpEncryption) . '\'); // 加密方式' . PHP_EOL . PHP_EOL;
        
        // 调试设置
        $newConfig .= '// 调试设置' . PHP_EOL;
        $newConfig .= 'define(\'MAIL_DEBUG\', ' . ($debug ? 'true' : 'false') . '); // 调试模式' . PHP_EOL . PHP_EOL;
        
        // 直接发送设置
        $newConfig .= '// 备用方法' . PHP_EOL;
        $newConfig .= 'define(\'USE_DIRECT_MAIL_FUNCTION\', ' . ($useDirectMail ? 'true' : 'false') . '); // 使用直接发送函数' . PHP_EOL . PHP_EOL;
        
        // SSL证书验证设置
        $newConfig .= '// SSL证书验证' . PHP_EOL;
        $newConfig .= 'define(\'SMTP_VERIFY_PEER\', ' . ($verifySSL ? 'true' : 'false') . '); // ' . ($verifySSL ? '启用' : '禁用') . 'SSL证书验证' . PHP_EOL;
        
        // 保存配置文件
        if (file_put_contents($configFile, $newConfig)) {
            $message = '配置已成功保存。';
            $messageType = 'success';
        } else {
            $message = '无法写入配置文件，请检查文件权限。';
            $messageType = 'error';
        }
    } catch (Exception $e) {
        $message = '保存配置时出错: ' . $e->getMessage();
        $messageType = 'error';
    }
}

// 读取当前配置
$useSmtp = false;
$smtpHost = 'smtp.example.com';
$smtpPort = 587;
$smtpUsername = '';
$smtpPassword = '';
$smtpEncryption = 'tls';
$fromAddress = 'noreply@example.com';
$fromName = 'ReadAloud';
$debug = false;
$useDirectMail = false;
$verifySSL = true;

if (file_exists($configFile)) {
    include $configFile;
    
    $useSmtp = defined('USE_SIMPLE_MAIL') ? !USE_SIMPLE_MAIL : false;
    $smtpHost = defined('MAIL_HOST') ? MAIL_HOST : 'smtp.example.com';
    $smtpPort = defined('MAIL_PORT') ? MAIL_PORT : 587;
    $smtpUsername = defined('MAIL_USERNAME') ? MAIL_USERNAME : '';
    $smtpPassword = defined('MAIL_PASSWORD') ? MAIL_PASSWORD : '';
    $smtpEncryption = defined('MAIL_ENCRYPTION') ? MAIL_ENCRYPTION : 'tls';
    $fromAddress = defined('MAIL_FROM_ADDRESS') ? MAIL_FROM_ADDRESS : 'noreply@example.com';
    $fromName = defined('MAIL_FROM_NAME') ? MAIL_FROM_NAME : 'ReadAloud';
    $debug = defined('MAIL_DEBUG') ? MAIL_DEBUG : false;
    $useDirectMail = defined('USE_DIRECT_MAIL_FUNCTION') ? USE_DIRECT_MAIL_FUNCTION : false;
    $verifySSL = defined('SMTP_VERIFY_PEER') ? SMTP_VERIFY_PEER : true;
}
?>

<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ReadAloud - SMTP配置</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: #fff;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 1px solid #ddd;
            padding-bottom: 10px;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        input[type="text"],
        input[type="password"],
        input[type="email"],
        input[type="number"],
        select {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }
        button {
            background-color: #4CAF50;
            color: white;
            padding: 10px 15px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 16px;
        }
        button:hover {
            background-color: #45a049;
        }
        .message {
            padding: 10px;
            margin-bottom: 20px;
            border-radius: 4px;
        }
        .message.success {
            background-color: #d4edda;
            border-color: #c3e6cb;
            color: #155724;
        }
        .message.error {
            background-color: #f8d7da;
            border-color: #f5c6cb;
            color: #721c24;
        }
        .checkbox-container {
            margin-bottom: 15px;
        }
        .checkbox-label {
            display: inline-block;
            margin-left: 5px;
            font-weight: normal;
        }
        .info-text {
            color: #666;
            font-size: 0.9em;
            margin-top: 5px;
        }
        .section {
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 1px solid #eee;
        }
        .section-title {
            margin-top: 0;
        }
        .test-button {
            background-color: #007bff;
        }
        .test-button:hover {
            background-color: #0069d9;
        }
        .test-link {
            display: inline-block;
            margin-top: 10px;
            color: #007bff;
            text-decoration: none;
        }
        .test-link:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>ReadAloud - 邮件服务配置</h1>
        
        <?php if (!empty($message)): ?>
        <div class="message <?php echo $messageType; ?>">
            <?php echo $message; ?>
        </div>
        <?php endif; ?>
        
        <form method="post">
            <div class="section">
                <h2 class="section-title">基本设置</h2>
                
                <div class="checkbox-container">
                    <input type="checkbox" id="use_smtp" name="use_smtp" value="1" <?php echo $useSmtp ? 'checked' : ''; ?>>
                    <label for="use_smtp" class="checkbox-label">使用SMTP服务器发送邮件</label>
                    <p class="info-text">启用此选项将使用SMTP服务器发送邮件，否则使用PHP内置的mail()函数。</p>
                </div>
                
                <div class="form-group">
                    <label for="from_address">发件人地址</label>
                    <input type="email" id="from_address" name="from_address" value="<?php echo htmlspecialchars($fromAddress); ?>" required>
                    <p class="info-text">发送验证码邮件的发件人地址。使用SMTP时，这通常需要与SMTP用户名保持一致。</p>
                </div>
                
                <div class="form-group">
                    <label for="from_name">发件人名称</label>
                    <input type="text" id="from_name" name="from_name" value="<?php echo htmlspecialchars($fromName); ?>" required>
                </div>
                
                <div class="checkbox-container">
                    <input type="checkbox" id="use_direct_mail" name="use_direct_mail" value="1" <?php echo $useDirectMail ? 'checked' : ''; ?>>
                    <label for="use_direct_mail" class="checkbox-label">尝试多种邮件发送方法</label>
                    <p class="info-text">启用此选项将尝试多种不同的邮件发送方法，在困难环境下提高成功率。</p>
                </div>
            </div>
            
            <div class="section" id="smtp_section" style="<?php echo $useSmtp ? '' : 'display: none;'; ?>">
                <h2 class="section-title">SMTP服务器设置</h2>
                
                <div class="form-group">
                    <label for="smtp_host">SMTP服务器地址</label>
                    <input type="text" id="smtp_host" name="smtp_host" value="<?php echo htmlspecialchars($smtpHost); ?>">
                    <p class="info-text">例如：smtp.gmail.com, smtp.qq.com, smtp.163.com</p>
                </div>
                
                <div class="form-group">
                    <label for="smtp_port">SMTP端口</label>
                    <input type="number" id="smtp_port" name="smtp_port" value="<?php echo $smtpPort; ?>">
                    <p class="info-text">常用端口：25(不加密), 465(SSL), 587(TLS)</p>
                </div>
                
                <div class="form-group">
                    <label for="smtp_username">SMTP用户名</label>
                    <input type="text" id="smtp_username" name="smtp_username" value="<?php echo htmlspecialchars($smtpUsername); ?>">
                    <p class="info-text">通常是您的完整邮箱地址</p>
                </div>
                
                <div class="form-group">
                    <label for="smtp_password">SMTP密码</label>
                    <input type="password" id="smtp_password" name="smtp_password" value="<?php echo htmlspecialchars($smtpPassword); ?>">
                    <p class="info-text">您邮箱的密码或授权码(QQ、163等邮箱需要生成授权码)</p>
                </div>
                
                <div class="form-group">
                    <label for="smtp_encryption">加密方式</label>
                    <select id="smtp_encryption" name="smtp_encryption">
                        <option value="tls" <?php echo $smtpEncryption === 'tls' ? 'selected' : ''; ?>>TLS</option>
                        <option value="ssl" <?php echo $smtpEncryption === 'ssl' ? 'selected' : ''; ?>>SSL</option>
                        <option value="" <?php echo $smtpEncryption === '' ? 'selected' : ''; ?>>无加密</option>
                    </select>
                </div>
                
                <div class="checkbox-container">
                    <input type="checkbox" id="verify_ssl" name="verify_ssl" value="1" <?php echo $verifySSL ? 'checked' : ''; ?>>
                    <label for="verify_ssl" class="checkbox-label">验证SSL证书</label>
                    <p class="info-text">如果遇到SSL证书错误，请取消勾选此选项。<strong>注意：</strong>这可能会降低安全性，但有助于解决某些服务器的SSL证书问题。</p>
                </div>
            </div>
            
            <div class="section">
                <h2 class="section-title">高级设置</h2>
                
                <div class="checkbox-container">
                    <input type="checkbox" id="debug_mode" name="debug_mode" value="1" <?php echo $debug ? 'checked' : ''; ?>>
                    <label for="debug_mode" class="checkbox-label">启用调试模式</label>
                    <p class="info-text">启用此选项将在日志中记录详细的发送过程信息，便于排查问题。</p>
                </div>
            </div>
            
            <button type="submit" name="save_config">保存配置</button>
            <a href="test_mail.php" class="test-link" target="_blank">测试邮件发送</a>
            <a href="direct_mail_test.php" class="test-link" target="_blank">多方式测试</a>
        </form>
        
        <div class="section">
            <h2 class="section-title">常见SMTP服务器设置</h2>
            <p><strong>QQ邮箱：</strong> smtp.qq.com, 端口587, TLS加密, 用户名为完整邮箱地址, 密码为授权码(需在QQ邮箱设置中生成)</p>
            <p><strong>163邮箱：</strong> smtp.163.com, 端口25或465, SSL加密(端口465), 用户名为完整邮箱地址, 密码为授权码</p>
            <p><strong>Gmail：</strong> smtp.gmail.com, 端口587, TLS加密, 需要开启"安全性较低的应用访问权限"或使用应用专用密码</p>
            <p><strong>阿里云企业邮箱：</strong> smtp.example.com, 端口465, SSL加密, 将"example.com"替换为您的实际域名</p>
        </div>
    </div>
    
    <script>
        document.getElementById('use_smtp').addEventListener('change', function() {
            document.getElementById('smtp_section').style.display = this.checked ? 'block' : 'none';
        });
    </script>
</body>
</html> 