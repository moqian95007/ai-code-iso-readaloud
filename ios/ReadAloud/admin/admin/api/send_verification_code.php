<?php
// 设置响应头为JSON
header('Content-Type: application/json');

// 引入配置文件
require_once '../config.php';
require_once '../mail_config.php';

// 记录请求信息，便于调试
error_log("Received verification code request");

// 检查请求方法
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode([
        'status' => 'error',
        'message' => '不支持的请求方法'
    ]);
    exit;
}

// 获取POST数据 - 支持JSON和表单数据
$email = null;

// 检查是否有JSON数据
$rawInput = file_get_contents('php://input');
if (!empty($rawInput)) {
    $postData = json_decode($rawInput, true);
    if (json_last_error() === JSON_ERROR_NONE && isset($postData['email'])) {
        $email = $postData['email'];
        error_log("Received JSON data with email: " . $email);
    }
}

// 如果没有从JSON获取到email，尝试从标准POST中获取
if (empty($email) && isset($_POST['email'])) {
    $email = $_POST['email'];
    error_log("Received POST form data with email: " . $email);
}

// 检查是否提供了email
if (empty($email)) {
    echo json_encode([
        'status' => 'error',
        'message' => '请提供有效的电子邮箱'
    ]);
    exit;
}

// 验证邮箱格式
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    echo json_encode([
        'status' => 'error',
        'message' => '邮箱格式不正确'
    ]);
    exit;
}

// 连接数据库
$conn = connectDB();
error_log("Database connection established");

// 检查邮箱是否已存在于users表 (可选的检查)
$checkEmailQuery = "SELECT id FROM users WHERE email = ?";
$checkEmailStmt = $conn->prepare($checkEmailQuery);
if (!$checkEmailStmt) {
    error_log("Prepare failed for email check: " . $conn->error);
    echo json_encode([
        'status' => 'error',
        'message' => '数据库查询准备失败: ' . $conn->error
    ]);
    exit;
}

$checkEmailStmt->bind_param("s", $email);
$checkEmailStmt->execute();
$result = $checkEmailStmt->get_result();
$checkEmailStmt->close();

// 生成6位数验证码
$verificationCode = sprintf("%06d", rand(0, 999999));
error_log("Generated verification code: " . $verificationCode . " for email: " . $email);

// 设置过期时间为10分钟后
$expiresAt = date('Y-m-d H:i:s', strtotime('+10 minutes'));

// 检查是否已存在该邮箱的验证码
$checkCodeQuery = "SELECT id FROM verification_codes WHERE email = ?";
$checkCodeStmt = $conn->prepare($checkCodeQuery);
if (!$checkCodeStmt) {
    error_log("Prepare failed for code check: " . $conn->error);
    echo json_encode([
        'status' => 'error',
        'message' => '数据库查询准备失败: ' . $conn->error
    ]);
    exit;
}

$checkCodeStmt->bind_param("s", $email);
$checkCodeStmt->execute();
$codeResult = $checkCodeStmt->get_result();
$codeExists = $codeResult->num_rows > 0;
$checkCodeStmt->close();

$success = false;

// 如果已存在验证码，更新它；否则，插入新记录
if ($codeExists) {
    error_log("Updating existing verification code");
    $updateQuery = "UPDATE verification_codes SET code = ?, created_at = NOW(), expires_at = ? WHERE email = ?";
    $updateStmt = $conn->prepare($updateQuery);
    if (!$updateStmt) {
        error_log("Prepare failed for update: " . $conn->error);
        echo json_encode([
            'status' => 'error',
            'message' => '数据库更新准备失败: ' . $conn->error
        ]);
        exit;
    }
    
    $updateStmt->bind_param("sss", $verificationCode, $expiresAt, $email);
    $success = $updateStmt->execute();
    $updateStmt->close();
} else {
    error_log("Inserting new verification code");
    $insertQuery = "INSERT INTO verification_codes (email, code, created_at, expires_at) VALUES (?, ?, NOW(), ?)";
    $insertStmt = $conn->prepare($insertQuery);
    if (!$insertStmt) {
        error_log("Prepare failed for insert: " . $conn->error);
        echo json_encode([
            'status' => 'error',
            'message' => '数据库插入准备失败: ' . $conn->error
        ]);
        exit;
    }
    
    $insertStmt->bind_param("sss", $email, $verificationCode, $expiresAt);
    $success = $insertStmt->execute();
    $insertStmt->close();
}

if (!$success) {
    error_log("Failed to save verification code: " . $conn->error);
    echo json_encode([
        'status' => 'error',
        'message' => '保存验证码失败: ' . $conn->error
    ]);
    exit;
}

// 发送验证码邮件
try {
    $emailSent = false;
    
    // 优先尝试使用 PHPMailer 发送邮件
    // 首先尝试从 phpmailer 安装路径加载
    $phpmailerLoaded = false;
    if (file_exists('../phpmailer/autoload.php')) {
        require_once '../phpmailer/autoload.php';
        $phpmailerLoaded = true;
        error_log("PHPMailer loaded from manual installation directory");
    } 
    // 如果 phpmailer 安装路径不存在，尝试从 composer 安装路径加载
    else if (file_exists('../vendor/autoload.php')) {
        require_once '../vendor/autoload.php';
        $phpmailerLoaded = true;
        error_log("PHPMailer loaded from vendor directory");
    }
    
    if ($phpmailerLoaded) {
        // 使用 PHPMailer 发送邮件
        $mail = new PHPMailer\PHPMailer\PHPMailer(true);
        
        // 取消 USE_SIMPLE_MAIL 条件，始终使用 SMTP
        $mail->isSMTP();
        $mail->Host = MAIL_HOST;
        $mail->SMTPAuth = true;
        $mail->Username = MAIL_USERNAME;
        $mail->Password = MAIL_PASSWORD;
        $mail->SMTPSecure = MAIL_ENCRYPTION;
        $mail->Port = MAIL_PORT;
        error_log("Using SMTP configuration with: " . MAIL_HOST . ":" . MAIL_PORT);
        
        // 如果定义了禁用SSL证书验证，则设置
        if (defined('SMTP_VERIFY_PEER') && SMTP_VERIFY_PEER === false) {
            $mail->SMTPOptions = [
                'ssl' => [
                    'verify_peer' => false,
                    'verify_peer_name' => false,
                    'allow_self_signed' => true
                ]
            ];
            error_log("Warning: SSL certificate validation disabled");
        }

        // 调试模式
        if (defined('MAIL_DEBUG') && MAIL_DEBUG) {
            $mail->SMTPDebug = 2; // 输出调试信息
            $mail->Debugoutput = function($str, $level) {
                error_log("PHPMailer Debug: $str");
            };
        }
            
        $mail->setFrom(MAIL_FROM_ADDRESS, MAIL_FROM_NAME);
        $mail->addAddress($email);
            
        $mail->isHTML(true);
        $mail->Subject = "ReadAloud 验证码";
        $mail->Body = "
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; line-height: 1.6; }
                .container { max-width: 600px; margin: 0 auto; padding: 20px; }
                .code { font-size: 24px; font-weight: bold; color: #3366cc; }
                .footer { margin-top: 20px; font-size: 12px; color: #666; }
            </style>
        </head>
        <body>
            <div class='container'>
                <h2>ReadAloud 验证码</h2>
                <p>尊敬的用户：</p>
                <p>您的验证码是: <span class='code'>{$verificationCode}</span></p>
                <p>此验证码有效期为10分钟，请勿泄露给他人。</p>
                <div class='footer'>
                    <p>此邮件由系统自动发送，请勿回复。</p>
                </div>
            </div>
        </body>
        </html>";
        $mail->AltBody = "您的验证码是: {$verificationCode}，有效期10分钟，请勿泄露给他人。";
            
        $mail->CharSet = 'UTF-8';
        
        try {
            $mail->send();
            $emailSent = true;
            error_log("Email sent successfully using PHPMailer SMTP");
        } catch (Exception $mailException) {
            error_log("PHPMailer SMTP Error: " . $mailException->getMessage());
            // SMTP失败后，尝试使用直接发送方法
            $emailSent = false;
        }
    }
    
    // 如果PHPMailer不可用或SMTP发送失败，尝试备用方法
    if (!$phpmailerLoaded || !$emailSent) {
        if (defined('USE_DIRECT_MAIL_FUNCTION') && USE_DIRECT_MAIL_FUNCTION) {
            error_log("Falling back to direct mail function for sending verification code");
            
            // 准备邮件内容
            $subject = "ReadAloud 验证码";
            $htmlMessage = "
            <html>
            <head>
                <title>ReadAloud 验证码</title>
                <style>
                    body { font-family: Arial, sans-serif; line-height: 1.6; }
                    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
                    .code { font-size: 24px; font-weight: bold; color: #3366cc; }
                    .footer { margin-top: 20px; font-size: 12px; color: #666; }
                </style>
            </head>
            <body>
                <div class='container'>
                    <h2>ReadAloud 验证码</h2>
                    <p>尊敬的用户：</p>
                    <p>您的验证码是: <span class='code'>{$verificationCode}</span></p>
                    <p>此验证码有效期为10分钟，请勿泄露给他人。</p>
                    <div class='footer'>
                        <p>此邮件由系统自动发送，请勿回复。</p>
                    </div>
                </div>
            </body>
            </html>
            ";
            
            $textMessage = "您的ReadAloud验证码是: {$verificationCode}，有效期10分钟，请勿泄露给他人。";
            
            // 尝试多种不同的邮件发送方法
            // 方法1：基本发送
            $headers = "From: " . MAIL_FROM_NAME . " <" . MAIL_FROM_ADDRESS . ">\r\n";
            $result1 = mail($email, $subject, $textMessage, $headers);
            error_log("Mail method 1 result: " . ($result1 ? "success" : "failed"));
            
            // 方法2：HTML邮件
            $headers = "From: " . MAIL_FROM_NAME . " <" . MAIL_FROM_ADDRESS . ">\r\n";
            $headers .= "Reply-To: " . MAIL_FROM_ADDRESS . "\r\n";
            $headers .= "MIME-Version: 1.0\r\n";
            $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
            $result2 = mail($email, $subject, $htmlMessage, $headers);
            error_log("Mail method 2 result: " . ($result2 ? "success" : "failed"));
            
            // 方法3：使用服务器域名
            $serverName = $_SERVER['SERVER_NAME'] ?? 'localhost';
            $fromAddress = "noreply@$serverName";
            $headers = "From: ReadAloud <$fromAddress>\r\n";
            $headers .= "MIME-Version: 1.0\r\n";
            $headers .= "Content-Type: text/plain; charset=UTF-8\r\n";
            $result3 = mail($email, $subject, $textMessage, $headers);
            error_log("Mail method 3 result: " . ($result3 ? "success" : "failed"));
            
            // 方法4：添加额外参数
            $headers = "From: " . MAIL_FROM_NAME . " <" . MAIL_FROM_ADDRESS . ">\r\n";
            $additionalParams = "-f " . MAIL_FROM_ADDRESS;
            $result4 = mail($email, $subject, $textMessage, $headers, $additionalParams);
            error_log("Mail method 4 result: " . ($result4 ? "success" : "failed"));
            
            // 只要有一个方法成功就认为发送成功
            $emailSent = $result1 || $result2 || $result3 || $result4;
            error_log("Email sending final result: " . ($emailSent ? "success" : "failed"));
        } else {
            // 简单邮件发送
            error_log("Using simple mail() function as last resort");
            $subject = "ReadAloud 验证码";
            $message = "您的验证码是: {$verificationCode}，有效期10分钟。";
            $headers = "From: " . MAIL_FROM_ADDRESS . "\r\n";
            $headers .= "Content-Type: text/plain; charset=UTF-8\r\n";
            
            $emailSent = mail($email, $subject, $message, $headers);
            error_log("Simple mail result: " . ($emailSent ? "success" : "failed"));
        }
    }
} catch (Exception $e) {
    error_log("Email sending failed with exception: " . $e->getMessage());
    $emailSent = false;
}

if ($emailSent) {
    // 邮件发送成功
    echo json_encode([
        'status' => 'success',
        'message' => '验证码已发送到您的邮箱'
    ]);
} else {
    // 邮件发送失败，删除刚才保存的验证码
    $deleteQuery = "DELETE FROM verification_codes WHERE email = ?";
    $deleteStmt = $conn->prepare($deleteQuery);
    if ($deleteStmt) {
        $deleteStmt->bind_param("s", $email);
        $deleteStmt->execute();
        $deleteStmt->close();
    }
    
    echo json_encode([
        'status' => 'error',
        'message' => '验证码发送失败，请稍后再试'
    ]);
}

// 关闭数据库连接
$conn->close();
?> 