# 手动安装 PHPMailer 完整版

如果自动安装失败（例如，无法从 GitHub 下载文件），您可以按照以下步骤手动安装 PHPMailer：

## 1. 下载 PHPMailer

1. 访问 [PHPMailer GitHub 发布页面](https://github.com/PHPMailer/PHPMailer/releases)
2. 下载最新版本的 zip 文件 (例如 `PHPMailer-6.8.0.zip`)
3. 解压缩下载的文件

## 2. 上传核心文件

您需要上传以下文件到服务器的 `/admin/phpmailer/src/` 目录：

- `PHPMailer.php`
- `SMTP.php`
- `Exception.php`
- `POP3.php`
- `OAuth.php`

这些文件在解压缩的 PHPMailer 的 `/src` 目录中。

## 3. 创建自动加载文件

在 `/admin/phpmailer/` 目录中创建一个名为 `autoload.php` 的文件，内容如下：

```php
<?php
spl_autoload_register(function ($class) {
    // PHPMailer 命名空间前缀
    $prefix = "PHPMailer\\PHPMailer\\";
    
    // 命名空间前缀的基础目录
    $base_dir = __DIR__ . "/src/";
    
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

## 4. 配置 SMTP 设置

1. 访问 `/admin/setup_smtp.php` 页面
2. 勾选"使用 SMTP 服务器发送邮件"选项
3. 填写您的 SMTP 服务器信息：
   - 服务器地址（例如：smtp.zoho.com）
   - 端口（例如：465 用于 SSL）
   - 用户名（您的邮箱地址）
   - 密码
   - 加密方式（SSL 或 TLS）
4. 点击"保存配置"按钮

## 5. 测试邮件发送

1. 访问 `/admin/test_mail.php?email=您的邮箱@example.com` 测试邮件发送
2. 如果仍然出现问题，检查错误信息并相应调整配置

## 常见问题解决

1. **SSL证书问题**：如果遇到 SSL 证书验证错误，可以编辑 `mail_config.php` 文件，添加：
   ```php
   define('SMTP_VERIFY_PEER', false); // 禁用SSL证书验证
   ```

2. **端口阻塞**：某些主机可能阻止了 SMTP 端口，尝试不同的端口（25, 465, 587）

3. **认证失败**：确保您的用户名和密码正确，某些提供商（如 Gmail）可能需要应用专用密码或开启"不够安全的应用访问" 