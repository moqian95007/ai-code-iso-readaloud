# ReadAloud 邮件系统配置指南

针对禁用了 `exec()` 函数和 Composer 的共享主机环境特别指南

## 方案选择

根据您的服务器环境，我们提供了以下几种安装方式：

1. **简化版 PHPMailer** (推荐，仅支持基本邮件功能，但无需额外安装)
2. **手动安装 PHPMailer** (功能完整，但需要手动下载和解压)

## 方案一：使用简化版 PHPMailer

1. 访问 `http://您的网站/admin/install_phpmailer_direct.php`
2. 脚本会自动创建所需的文件

这个方案会安装一个精简版的 PHPMailer，只包含基本的邮件发送功能，但完全能满足验证码发送需求。

## 方案二：手动安装 PHPMailer

如果您希望使用完整版的 PHPMailer：

1. 从 GitHub 下载 PHPMailer: https://github.com/PHPMailer/PHPMailer/archive/refs/tags/v6.8.0.zip
2. 解压后，将 `PHPMailer-6.8.0` 目录上传到您服务器的 `admin/phpmailer/` 目录
3. 创建 `admin/phpmailer/autoload.php` 文件，内容请参考 `INSTALL_MANUAL.md`

## 邮件配置

无论选择哪种方案，您都需要配置邮件设置：

1. 编辑 `admin/mail_config.php` 文件
2. 确保 `USE_SIMPLE_MAIL` 设置为 `true`
3. 设置正确的发件人邮箱 `MAIL_FROM_ADDRESS` 和名称 `MAIL_FROM_NAME`

示例配置：

```php
// 使用简单邮件模式
define('USE_SIMPLE_MAIL', true);

// 发件人设置 - 必须配置！
define('MAIL_FROM_ADDRESS', 'your_email@example.com'); // 改为您的实际邮箱
define('MAIL_FROM_NAME', 'ReadAloud App'); // 发件人名称
```

## 测试邮件功能

配置完成后，使用我们提供的测试脚本验证邮件是否能正常发送：

```
http://您的网站/admin/test_mail.php?email=您的测试邮箱@example.com
```

## 常见问题

### 1. 无法发送邮件

许多共享主机限制了邮件发送功能。可能的解决方案：

- 联系您的主机提供商，询问如何启用邮件发送功能
- 询问主机提供商推荐的邮件发送设置
- 考虑使用第三方邮件服务，如SendGrid、Mailgun等

### 2. 我的发件人地址不起作用

某些主机要求发件人地址必须是该服务器上的有效邮箱地址。请尝试：

- 使用您在主机上的邮箱作为发件人
- 确保主机允许您使用该邮箱发送邮件

### 3. 邮件发送成功但未收到

- 检查垃圾邮件文件夹
- 确认邮箱地址输入正确
- 部分服务器的邮件可能会被接收方的邮件服务器标记为垃圾邮件

## 日志查看

如需查看详细的错误信息，请检查PHP错误日志文件：
- cPanel主机通常在 `/home/username/logs/error_log`
- Plesk主机通常在 `/var/www/vhosts/domain.com/logs/`

请根据主机提供商的说明找到正确的日志文件位置。 