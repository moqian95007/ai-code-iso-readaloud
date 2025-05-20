<?php
/**
 * PHPMailer 手动安装脚本
 * 不依赖 Composer 或 exec 函数
 */

// 设置超时时间
set_time_limit(300);

// 创建目录
$vendorDir = __DIR__ . '/phpmailer';
if (!file_exists($vendorDir)) {
    if (!mkdir($vendorDir, 0755, true)) {
        die("无法创建目录: $vendorDir\n");
    }
    echo "创建目录: $vendorDir\n";
}

// PHPMailer 下载链接
$phpmailerUrl = 'https://github.com/PHPMailer/PHPMailer/archive/refs/tags/v6.8.0.zip';
$zipFile = __DIR__ . '/phpmailer.zip';

echo "开始下载 PHPMailer...\n";
$zipContent = file_get_contents($phpmailerUrl);
if ($zipContent === false) {
    die("下载 PHPMailer 失败，请手动下载: $phpmailerUrl\n");
}

if (file_put_contents($zipFile, $zipContent) === false) {
    die("保存 PHPMailer 压缩包失败\n");
}
echo "PHPMailer 下载完成\n";

// 解压文件
echo "开始解压 PHPMailer...\n";
$zip = new ZipArchive;
if ($zip->open($zipFile) !== true) {
    die("无法打开 PHPMailer 压缩包\n");
}

if (!$zip->extractTo($vendorDir)) {
    $zip->close();
    die("解压 PHPMailer 失败\n");
}
$zip->close();
echo "PHPMailer 解压完成\n";

// 清理下载的 zip 文件
unlink($zipFile);

// 创建自动加载文件
echo "创建自动加载文件...\n";
$extractedDir = $vendorDir . '/PHPMailer-6.8.0';
$autoloadContent = '<?php
spl_autoload_register(function ($class) {
    // PHPMailer 命名空间前缀
    $prefix = "PHPMailer\\\\PHPMailer\\\\";
    
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
    $file = $base_dir . str_replace("\\\\", "/", $relative_class) . ".php";
    
    // 如果文件存在，则包含它
    if (file_exists($file)) {
        require $file;
    }
});
';

file_put_contents($vendorDir . '/autoload.php', $autoloadContent);

// 验证安装
if (file_exists($extractedDir . '/src/PHPMailer.php')) {
    echo "PHPMailer 安装成功！\n";
} else {
    echo "PHPMailer 安装不完整，请检查文件是否正确解压\n";
}

// 更新 send_verification_code.php 文件中的引用
$sendVerificationCodeFile = __DIR__ . '/api/send_verification_code.php';
if (file_exists($sendVerificationCodeFile)) {
    $content = file_get_contents($sendVerificationCodeFile);
    $content = str_replace("require '../vendor/autoload.php';", "require '../phpmailer/autoload.php';", $content);
    file_put_contents($sendVerificationCodeFile, $content);
    echo "已更新 send_verification_code.php 中的 PHPMailer 引用\n";
}

echo "PHPMailer 手动安装完成，请在 mail_config.php 文件中配置您的邮件服务器信息。\n";
?> 