<?php
/**
 * 直接邮件发送测试脚本
 * 使用多种不同的配置方式测试邮件发送
 */

// 引入配置
require_once 'mail_config.php';

// 获取测试邮箱
$testEmail = isset($_GET['email']) ? $_GET['email'] : '';
if (empty($testEmail)) {
    die("请提供测试邮箱地址：direct_mail_test.php?email=your@email.com");
}

// 生成验证码
$testCode = sprintf("%06d", rand(0, 999999));

// 创建日志
$logFile = __DIR__ . '/mail_log.txt';
$log = function($message) use ($logFile) {
    $time = date('Y-m-d H:i:s');
    file_put_contents($logFile, "[$time] $message\n", FILE_APPEND);
    echo "$message<br>\n";
};

$log("======= 开始邮件发送测试 =======");
$log("收件人: $testEmail");
$log("验证码: $testCode");

// 测试多种不同的邮件发送方法
$methods = [
    '方法1 - 基本mail函数' => function() use ($testEmail, $testCode, $log) {
        $subject = "ReadAloud验证码测试 - 方法1";
        $message = "您的验证码是: $testCode";
        $headers = "From: " . MAIL_FROM_ADDRESS . "\r\n";
        
        $log("尝试方法1 - 使用基本mail()函数");
        $result = mail($testEmail, $subject, $message, $headers);
        $log("方法1结果: " . ($result ? "成功" : "失败"));
        return $result;
    },
    
    '方法2 - 添加额外邮件头' => function() use ($testEmail, $testCode, $log) {
        $subject = "ReadAloud验证码测试 - 方法2";
        $message = "您的验证码是: $testCode";
        $headers = "From: " . MAIL_FROM_NAME . " <" . MAIL_FROM_ADDRESS . ">\r\n";
        $headers .= "Reply-To: " . MAIL_FROM_ADDRESS . "\r\n";
        $headers .= "X-Mailer: PHP/" . phpversion() . "\r\n";
        $headers .= "MIME-Version: 1.0\r\n";
        $headers .= "Content-Type: text/plain; charset=UTF-8\r\n";
        
        $log("尝试方法2 - 添加额外邮件头");
        $result = mail($testEmail, $subject, $message, $headers);
        $log("方法2结果: " . ($result ? "成功" : "失败"));
        return $result;
    },
    
    '方法3 - HTML邮件' => function() use ($testEmail, $testCode, $log) {
        $subject = "ReadAloud验证码测试 - 方法3";
        $message = "
        <html>
        <head>
            <title>ReadAloud验证码</title>
        </head>
        <body>
            <h2>ReadAloud验证码测试</h2>
            <p>您的验证码是: <b>$testCode</b></p>
        </body>
        </html>
        ";
        $headers = "From: " . MAIL_FROM_NAME . " <" . MAIL_FROM_ADDRESS . ">\r\n";
        $headers .= "Reply-To: " . MAIL_FROM_ADDRESS . "\r\n";
        $headers .= "X-Mailer: PHP/" . phpversion() . "\r\n";
        $headers .= "MIME-Version: 1.0\r\n";
        $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
        
        $log("尝试方法3 - HTML邮件");
        $result = mail($testEmail, $subject, $message, $headers);
        $log("方法3结果: " . ($result ? "成功" : "失败"));
        return $result;
    },
    
    '方法4 - 添加额外参数' => function() use ($testEmail, $testCode, $log) {
        $subject = "ReadAloud验证码测试 - 方法4";
        $message = "您的验证码是: $testCode";
        $headers = "From: " . MAIL_FROM_NAME . " <" . MAIL_FROM_ADDRESS . ">\r\n";
        $headers .= "Reply-To: " . MAIL_FROM_ADDRESS . "\r\n";
        $headers .= "X-Mailer: PHP/" . phpversion() . "\r\n";
        
        // 添加额外参数，例如 -f 指定发件人
        $additionalParams = "-f " . MAIL_FROM_ADDRESS;
        
        $log("尝试方法4 - 添加额外参数: $additionalParams");
        $result = mail($testEmail, $subject, $message, $headers, $additionalParams);
        $log("方法4结果: " . ($result ? "成功" : "失败"));
        return $result;
    },
    
    '方法5 - 使用服务器域名作为发件人' => function() use ($testEmail, $testCode, $log) {
        // 获取服务器域名
        $serverName = $_SERVER['SERVER_NAME'] ?? 'localhost';
        $fromAddress = "noreply@$serverName";
        
        $subject = "ReadAloud验证码测试 - 方法5";
        $message = "您的验证码是: $testCode";
        $headers = "From: ReadAloud <$fromAddress>\r\n";
        
        $log("尝试方法5 - 使用服务器域名作为发件人: $fromAddress");
        $result = mail($testEmail, $subject, $message, $headers);
        $log("方法5结果: " . ($result ? "成功" : "失败"));
        return $result;
    }
];

// 执行所有测试方法
$successCount = 0;
foreach ($methods as $name => $method) {
    $log("\n=== 测试: $name ===");
    try {
        $result = $method();
        if ($result) {
            $successCount++;
        }
    } catch (Exception $e) {
        $log("错误: " . $e->getMessage());
    }
}

$log("\n总结: 尝试了 " . count($methods) . " 种方法，成功 $successCount 次");
$log("请检查您的邮箱(包括垃圾邮件文件夹)是否收到了测试邮件");
$log("日志文件保存在: $logFile");

// 显示服务器信息
$log("\n=== 服务器信息 ===");
$log("PHP版本: " . phpversion());
$log("服务器软件: " . ($_SERVER['SERVER_SOFTWARE'] ?? '未知'));
$log("服务器名称: " . ($_SERVER['SERVER_NAME'] ?? '未知'));
$log("服务器IP: " . ($_SERVER['SERVER_ADDR'] ?? '未知'));
$log("主机名: " . (function_exists('gethostname') ? gethostname() : '未知'));

// 检查PHP mail配置
$log("\n=== PHP邮件配置 ===");
if (function_exists('ini_get')) {
    $log("sendmail_path: " . (ini_get('sendmail_path') ?: '未设置'));
    $log("SMTP: " . (ini_get('SMTP') ?: '未设置'));
    $log("smtp_port: " . (ini_get('smtp_port') ?: '未设置'));
    $log("mail.add_x_header: " . (ini_get('mail.add_x_header') ? '是' : '否'));
    $log("mail.force_extra_parameters: " . (ini_get('mail.force_extra_parameters') ?: '未设置'));
}

// 提供一些建议
$log("\n=== 建议 ===");
$log("1. 检查服务器上的sendmail或Postfix是否正确配置");
$log("2. 检查主机是否限制了邮件发送");
$log("3. 尝试使用第三方SMTP服务如SendGrid或Mailgun");
$log("4. 联系您的主机提供商获取正确的邮件发送配置");
?> 