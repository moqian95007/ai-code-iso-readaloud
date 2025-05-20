# ReadAloud 邮件系统手动安装指南

此指南适用于无法使用 Composer 或 `exec()` 函数的共享主机环境。

## 1. 手动安装 PHPMailer

有两种方式可以手动安装 PHPMailer：

### 方式一：使用内置脚本（推荐）

1. 访问 `http://您的网站/admin/install_phpmailer_manual.php`
2. 脚本会自动下载和配置 PHPMailer

### 方式二：手动上传文件

如果方式一不起作用，请按照以下步骤操作：

1. 从 GitHub 下载 PHPMailer：https://github.com/PHPMailer/PHPMailer/archive/refs/tags/v6.8.0.zip
2. 解压文件
3. 在服务器上创建 `admin/phpmailer` 目录
4. 将解压后的文件夹 `PHPMailer-6.8.0` 上传到 `admin/phpmailer` 目录
5. 创建文件 `admin/phpmailer/autoload.php`，内容如下：

```php
<?php
spl_autoload_register(function ($class) {
    // PHPMailer 命名空间前缀
    $prefix = "PHPMailer\\PHPMailer\\";
    
    // 命名空间前缀的基础目录
    $base_dir = __DIR__ . "/PHPMailer-6.8.0/src/";
    
    // 类是否使用命名空间前缀?
    $len = strlen($prefix);
    if (strncmp($prefix, $class, $len) !== 0) {
        // 不使用，交给下一个已注册的自动加载器
        return;
    }
    
    // 获取相对类名
    $relative_class = substr($class, $len);
    
    // 将命名空间前缀替换为基础目录，将类名中的命名空间分隔符替换
    // 为目录分隔符，并添加 .php 后缀
    $file = $base_dir . str_replace("\\", "/", $relative_class) . ".php";
    
    // 如果文件存在，则包含它
    if (file_exists($file)) {
        require $file;
    }
});
```

## 2. 配置邮件设置

编辑 `admin/mail_config.php` 文件，修改邮件配置：

### 使用简单邮件模式（共享主机推荐）

如果您的主机支持 PHP 内置的 `mail()` 函数，可以使用简单邮件模式：

```php
// 简单邮件模式
define('USE_SIMPLE_MAIL', true);

// 发件人设置
define('MAIL_FROM_ADDRESS', 'your_email@example.com'); // 修改为您的邮箱
define('MAIL_FROM_NAME', 'ReadAloud'); // 发件人名称
```

### 使用 SMTP 模式（如果简单模式不工作）

如果简单邮件模式不工作，您可以尝试使用 SMTP 模式：

```php
// 关闭简单邮件模式
define('USE_SIMPLE_MAIL', false);

// SMTP 配置
define('MAIL_HOST', 'smtp.example.com'); // 修改为您的SMTP服务器
define('MAIL_PORT', 587);                // 修改为正确的端口
define('MAIL_USERNAME', 'your_email@example.com'); // 修改为您的邮箱
define('MAIL_PASSWORD', 'your_password');  // 修改为您的密码或授权码
define('MAIL_ENCRYPTION', 'tls');      // 加密方式: tls 或 ssl
define('MAIL_FROM_ADDRESS', 'your_email@example.com'); // 修改为您的邮箱
define('MAIL_FROM_NAME', 'ReadAloud'); // 发件人名称
```

## 3. 测试邮件发送

配置完成后，可以使用测试脚本验证邮件是否能正常发送：

1. 访问 `http://您的网站/admin/test_mail.php?email=your_email@example.com`
2. 检查测试结果，查看是否收到测试邮件

## 4. 常见问题排查

1. **邮件发送失败**
   - 检查错误日志获取详细信息
   - 确认 `mail_config.php` 中的邮箱和密码是否正确
   - 对于 Gmail，确保允许"不够安全的应用访问"或使用应用专用密码
   - 对于 QQ 邮箱，需要在邮箱设置中生成授权码

2. **PHPMailer 加载失败**
   - 确认 PHPMailer 文件已正确上传
   - 检查 `admin/phpmailer/PHPMailer-6.8.0/src` 目录中是否有 PHPMailer.php 文件

3. **共享主机限制**
   - 部分共享主机限制发送邮件频率，可能需要联系主机服务商
   - 考虑使用第三方邮件服务如 SendGrid、Mailgun 等

## 5. 使用第三方邮件服务 (可选)

如果您的主机不允许发送邮件，可以考虑使用第三方邮件服务。这需要修改代码实现，请联系技术支持获取帮助。 