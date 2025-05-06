<?php
/**
 * PHPMailer 直接安装脚本 - 完整版
 * 直接下载完整版 PHPMailer 以支持 SMTP 功能
 */

// 设置超时时间
set_time_limit(300);

// 创建目录
$phpmailerDir = __DIR__ . '/phpmailer';
if (!file_exists($phpmailerDir)) {
    if (!mkdir($phpmailerDir, 0755, true)) {
        die("无法创建目录: $phpmailerDir\n");
    }
    echo "创建目录: $phpmailerDir<br>\n";
}

$srcDir = $phpmailerDir . '/src';
if (!file_exists($srcDir)) {
    if (!mkdir($srcDir, 0755, true)) {
        die("无法创建目录: $srcDir\n");
    }
    echo "创建目录: $srcDir<br>\n";
}

// 下载 PHPMailer 文件
echo "开始下载 PHPMailer 核心文件...<br>\n";

// 文件列表：PHPMailer 核心文件
$files = [
    'PHPMailer.php' => 'https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/PHPMailer.php',
    'SMTP.php' => 'https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/SMTP.php',
    'Exception.php' => 'https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/Exception.php',
    'POP3.php' => 'https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/POP3.php',
    'OAuth.php' => 'https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/OAuth.php',
];

// 下载每个文件
$success = true;
foreach ($files as $filename => $url) {
    echo "下载文件: $filename<br>\n";
    $content = @file_get_contents($url);
    if ($content === false) {
        echo "<span style='color:red'>下载 $filename 失败</span><br>\n";
        $success = false;
        continue;
    }
    
    $filepath = $srcDir . '/' . $filename;
    if (file_put_contents($filepath, $content) === false) {
        echo "<span style='color:red'>保存 $filename 失败</span><br>\n";
        $success = false;
        continue;
    }
    
    echo "<span style='color:green'>$filename 下载成功</span><br>\n";
}

// 创建自动加载文件
echo "创建自动加载文件...<br>\n";
$autoloadContent = '<?php
spl_autoload_register(function ($class) {
    // PHPMailer 命名空间前缀
    $prefix = "PHPMailer\\\\PHPMailer\\\\";
    
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
    $file = $base_dir . str_replace("\\\\", "/", $relative_class) . ".php";
    
    // 如果文件存在，则包含它
    if (file_exists($file)) {
        require $file;
    }
});
';

file_put_contents($phpmailerDir . '/autoload.php', $autoloadContent);
echo "创建文件: autoload.php<br>\n";

// 更新 send_verification_code.php 文件中的引用
$sendVerificationCodeFile = __DIR__ . '/api/send_verification_code.php';
if (file_exists($sendVerificationCodeFile)) {
    $content = file_get_contents($sendVerificationCodeFile);
    $content = str_replace("require '../vendor/autoload.php';", "require '../phpmailer/autoload.php';", $content);
    file_put_contents($sendVerificationCodeFile, $content);
    echo "已更新 send_verification_code.php 中的 PHPMailer 引用<br>\n";
}

if ($success) {
    echo "<h2 style='color:green'>PHPMailer 完整版安装成功！</h2><br>\n";
    echo "支持 SMTP 发送、OAuth 认证等高级功能。<br>\n";
    echo "<a href='setup_smtp.php'>点击这里配置 SMTP 设置</a><br>\n";
    echo "<a href='test_mail.php'>点击这里测试邮件发送</a><br>\n";
} else {
    echo "<h2 style='color:red'>安装过程中出现一些错误</h2><br>\n";
    echo "您可能需要手动下载 PHPMailer 文件。<br>\n";
    echo "请参考 <a href='https://github.com/PHPMailer/PHPMailer'>PHPMailer GitHub 仓库</a> 获取帮助。<br>\n";
}

// 检查文件是否存在
echo "<h3>安装验证</h3><br>\n";
$requiredFiles = ['PHPMailer.php', 'SMTP.php', 'Exception.php'];
$allFilesExist = true;
foreach ($requiredFiles as $file) {
    $path = $srcDir . '/' . $file;
    if (file_exists($path)) {
        echo "文件 $file: <span style='color:green'>存在</span><br>\n";
    } else {
        echo "文件 $file: <span style='color:red'>不存在</span><br>\n";
        $allFilesExist = false;
    }
}

if ($allFilesExist) {
    echo "<br><strong>所有必要文件已安装，PHPMailer 应该可以正常工作了。</strong><br>\n";
} else {
    echo "<br><strong style='color:red'>一些必要文件可能丢失，PHPMailer 可能无法正常工作。</strong><br>\n";
}
?> 