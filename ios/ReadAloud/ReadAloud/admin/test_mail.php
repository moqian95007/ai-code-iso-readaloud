<?php
/**
 * 邮件发送测试脚本
 * 用于测试 PHPMailer 配置是否正确
 * 兼容简化版和手动安装的 PHPMailer
 */

// 引入邮件配置
require_once 'mail_config.php';

// 默认使用简化版PHPMailer路径
$phpmailerPaths = [
    __DIR__ . '/phpmailer/autoload.php',    // 简化版或手动安装路径
    __DIR__ . '/vendor/autoload.php'        // Composer 安装路径
];

$phpmailerLoaded = false;
foreach ($phpmailerPaths as $path) {
    if (file_exists($path)) {
        require_once $path;
        $phpmailerLoaded = true;
        echo "已加载 PHPMailer: " . $path . "<br>\n";
        break;
    }
}

if (!$phpmailerLoaded) {
    die("PHPMailer 未安装，请先运行 install_phpmailer_direct.php 脚本。<br>\n");
}

// 获取要发送的邮箱地址
$testEmail = isset($_GET['email']) ? $_GET['email'] : '';

if (empty($testEmail)) {
    echo "请提供一个测试邮箱地址。用法: test_mail.php?email=your_email@example.com<br>\n";
    exit(1);
}

// 生成测试验证码
$testCode = sprintf("%06d", rand(0, 999999));

echo "正在发送测试邮件到: {$testEmail}<br>\n";
echo "测试验证码: {$testCode}<br>\n";

// 创建 PHPMailer 实例
$mail = new PHPMailer\PHPMailer\PHPMailer(true);

try {
    // 如果是共享主机环境，可以尝试使用基本的邮件发送模式
    if (defined('USE_SIMPLE_MAIL') && USE_SIMPLE_MAIL) {
        $mail->isMail();
        echo "使用简单邮件模式<br>\n";
    } else {
        $mail->isSMTP();
        $mail->Host = MAIL_HOST;
        $mail->SMTPAuth = true;
        $mail->Username = MAIL_USERNAME;
        $mail->Password = MAIL_PASSWORD;
        $mail->SMTPSecure = MAIL_ENCRYPTION;
        $mail->Port = MAIL_PORT;
        
        // 如果定义了禁用SSL证书验证，则设置
        if (defined('SMTP_VERIFY_PEER') && SMTP_VERIFY_PEER === false) {
            $mail->SMTPOptions = [
                'ssl' => [
                    'verify_peer' => false,
                    'verify_peer_name' => false,
                    'allow_self_signed' => true
                ]
            ];
            echo "<span style='color:orange;'>警告: SSL证书验证已禁用</span><br>\n";
        }
        
        echo "使用SMTP模式<br>\n";
    }
    
    // 调试模式
    if (defined('MAIL_DEBUG') && MAIL_DEBUG) {
        echo "调试模式已启用<br>\n";
        $mail->SMTPDebug = 2; // 启用详细调试输出
        $mail->Debugoutput = function($str, $level) {
            echo "<pre style='background-color: #f5f5f5; padding: 5px; font-size: 12px; color: #333;'>DEBUG: " . htmlspecialchars($str) . "</pre>\n";
        };
    }
    
    // 发件人和收件人
    $mail->setFrom(MAIL_FROM_ADDRESS, MAIL_FROM_NAME);
    $mail->addAddress($testEmail);
    
    // 邮件内容
    $mail->isHTML(true);
    $mail->Subject = "ReadAloud 邮件发送测试";
    $mail->Body = "这是一封测试邮件，用于验证邮件服务器配置是否正确。<br><br>您的测试验证码是: <b>{$testCode}</b>";
    $mail->AltBody = "这是一封测试邮件，用于验证邮件服务器配置是否正确。您的测试验证码是: {$testCode}";
    $mail->CharSet = 'UTF-8';
    
    // 发送邮件
    if ($mail->send()) {
        echo "<span style='color:green;font-weight:bold;'>测试邮件发送成功！</span><br>\n";
    } else {
        echo "<span style='color:red;font-weight:bold;'>测试邮件发送失败: {$mail->ErrorInfo}</span><br>\n";
    }
} catch (Exception $e) {
    echo "<span style='color:red;font-weight:bold;'>测试邮件发送异常: {$e->getMessage()}</span><br>\n";
    
    // 额外的错误诊断信息
    echo "<br>诊断信息：<br>\n";
    echo "- 请确保您已正确配置 mail_config.php 文件中的邮件设置<br>\n";
    echo "- 检查您的主机是否允许发送邮件<br>\n";
    echo "- 如果使用Gmail，请确保您已开启「安全性较低的应用的访问权限」<br>\n";
    echo "- 如果使用企业邮箱，请确保您的IP地址在白名单中<br>\n";
}

// 显示配置信息
echo "<br>当前配置:<br>\n";
echo "- 发件人: " . MAIL_FROM_ADDRESS . " (" . MAIL_FROM_NAME . ")<br>\n";
if (!defined('USE_SIMPLE_MAIL') || !USE_SIMPLE_MAIL) {
    echo "- SMTP 服务器: " . MAIL_HOST . "<br>\n";
    echo "- 端口: " . MAIL_PORT . "<br>\n";
    echo "- 用户名: " . MAIL_USERNAME . "<br>\n";
    echo "- 加密方式: " . MAIL_ENCRYPTION . "<br>\n";
} else {
    echo "- 使用简单邮件模式 (PHP mail函数)<br>\n";
}

// 检查PHP配置
echo "<br>PHP邮件配置:<br>\n";
if (function_exists('ini_get')) {
    echo "- sendmail_path: " . (ini_get('sendmail_path') ?: '未设置') . "<br>\n";
    echo "- SMTP: " . (ini_get('SMTP') ?: '未设置') . "<br>\n";
    echo "- smtp_port: " . (ini_get('smtp_port') ?: '未设置') . "<br>\n";
}

// 测试PHP mail函数
echo "<br>测试PHP mail函数:<br>\n";
$mailFunctionTest = @mail($testEmail, 'PHP Mail Test', 'This is a test from PHP mail() function', 'From: ' . MAIL_FROM_ADDRESS);
echo "- PHP mail()函数测试: " . ($mailFunctionTest ? "<span style='color:green;'>成功</span>" : "<span style='color:red;'>失败</span>") . "<br>\n";
?> 