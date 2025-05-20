<?php
/**
 * 邮件服务器配置文件
 * 请替换以下配置为实际的SMTP服务器信息
 */

// 简单邮件模式（适用于共享主机环境）
define('USE_SIMPLE_MAIL', true); // 设置为 true 使用PHP内置的mail()函数，无需SMTP配置

// 发件人设置 - 重要！
// 在许多共享主机上，发件人地址必须是服务器上存在的有效邮箱地址
// 尝试使用网站管理员邮箱或您主机提供的邮箱地址
define('MAIL_FROM_ADDRESS', 'admin@readaloud.ai-toolkit.top'); // 修改为服务器上有效的邮箱
define('MAIL_FROM_NAME', 'ReadAloud系统'); // 发件人名称

// PHP mail()函数配置（当USE_SIMPLE_MAIL为true时使用）
// 一些服务器需要指定以下参数
define('MAIL_ADDITIONAL_PARAMETERS', ''); // 一些服务器需要额外参数，如'-f admin@yourdomain.com'

// SMTP 服务器配置（当 USE_SIMPLE_MAIL 为 false 时使用）
define('MAIL_HOST', 'smtp.example.com'); // 邮件服务器地址，如 smtp.gmail.com 或 smtp.qq.com
define('MAIL_PORT', 587);              // 端口号，常用有 25, 465, 587
define('MAIL_USERNAME', 'your_email@example.com'); // 邮箱账号
define('MAIL_PASSWORD', 'your_password');  // 邮箱密码或授权码
define('MAIL_ENCRYPTION', 'tls');      // 加密方式: tls 或 ssl

// 备用配置 - 如果使用第三方邮件服务如SendGrid、Mailgun等
define('USE_ALTERNATIVE_MAILER', false); // 是否使用备用邮件服务
define('API_KEY', ''); // 如果使用API Key认证的邮件服务，请在此填写

// 调试模式
define('MAIL_DEBUG', true); // 设置为 true 会在日志中输出更多调试信息

// 使用直接发送函数
define('USE_DIRECT_MAIL_FUNCTION', true); // 使用不依赖PHPMailer的备用发送方法

// SSL证书验证 - 如果遇到SSL证书问题，设置为false
define('SMTP_VERIFY_PEER', false); // 禁用SSL证书验证，解决证书错误问题
?> 