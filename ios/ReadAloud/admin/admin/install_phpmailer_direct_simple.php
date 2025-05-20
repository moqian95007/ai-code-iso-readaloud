<?php
/**
 * PHPMailer 直接安装脚本 - 简化版
 * 只下载必要的核心文件，减少资源使用
 */

// 设置超时时间和内存限制
set_time_limit(60);
ini_set('memory_limit', '32M');

// 创建目录
$phpmailerDir = __DIR__ . '/phpmailer';
if (!file_exists($phpmailerDir)) {
    if (!mkdir($phpmailerDir, 0755, true)) {
        die("无法创建目录: $phpmailerDir<br>");
    }
    echo "创建目录: $phpmailerDir<br>";
}

$srcDir = $phpmailerDir . '/src';
if (!file_exists($srcDir)) {
    if (!mkdir($srcDir, 0755, true)) {
        die("无法创建目录: $srcDir<br>");
    }
    echo "创建目录: $srcDir<br>";
}

// 下载 PHPMailer 文件 - 只下载必要的三个核心文件
echo "开始下载 PHPMailer 核心文件...<br>";

// 文件列表：只包含最基本的三个文件
$files = [
    'PHPMailer.php' => 'https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/PHPMailer.php',
    'SMTP.php' => 'https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/SMTP.php',
    'Exception.php' => 'https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/Exception.php',
];

// 下载每个文件，一次只处理一个文件
$success = true;
foreach ($files as $filename => $url) {
    echo "下载文件: $filename<br>";
    flush(); // 输出缓冲区刷新
    
    $content = @file_get_contents($url);
    if ($content === false) {
        echo "<span style='color:red'>下载 $filename 失败</span><br>";
        $success = false;
        continue;
    }
    
    $filepath = $srcDir . '/' . $filename;
    if (file_put_contents($filepath, $content) === false) {
        echo "<span style='color:red'>保存 $filename 失败</span><br>";
        $success = false;
        continue;
    }
    
    echo "<span style='color:green'>$filename 下载成功</span><br>";
    flush(); // 输出缓冲区刷新
}

// 创建自动加载文件
echo "创建自动加载文件...<br>";
$autoloadContent = '<?php
spl_autoload_register(function ($class) {
    // PHPMailer 命名空间前缀
    $prefix = "PHPMailer\\\\PHPMailer\\\\";
    
    // 命名空间前缀的基础目录
    $base_dir = __DIR__ . "/src/";
    
    // 类是否使用命名空间前缀?
    $len = strlen($prefix);
    if (strncmp($prefix, $class, $len) !== 0) {
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
echo "创建文件: autoload.php<br>";

if ($success) {
    echo "<h2 style='color:green'>PHPMailer 安装成功！</h2><br>";
    echo "已安装必要的核心文件，支持 SMTP 发送功能。<br>";
    echo "<a href='setup_smtp.php'>点击这里配置 SMTP 设置</a><br>";
    echo "<a href='test_mail.php'>点击这里测试邮件发送</a><br>";
} else {
    echo "<h2 style='color:orange'>部分文件安装失败</h2><br>";
    echo "请参考 <a href='README_MANUAL_INSTALL.md'>手动安装指南</a> 完成安装。<br>";
}

// 检查文件是否存在
echo "<h3>安装验证</h3><br>";
$requiredFiles = ['PHPMailer.php', 'SMTP.php', 'Exception.php'];
$allFilesExist = true;
foreach ($requiredFiles as $file) {
    $path = $srcDir . '/' . $file;
    if (file_exists($path)) {
        echo "文件 $file: <span style='color:green'>存在</span><br>";
    } else {
        echo "文件 $file: <span style='color:red'>不存在</span><br>";
        $allFilesExist = false;
    }
}

if ($allFilesExist) {
    echo "<br><strong>所有必要文件已安装，PHPMailer 应该可以正常工作了。</strong><br>";
} else {
    echo "<br><strong style='color:red'>一些必要文件可能丢失，PHPMailer 可能无法正常工作。</strong><br>";
    echo "请参考 <a href='README_MANUAL_INSTALL.md'>手动安装指南</a> 手动上传缺失的文件。<br>";
}
?> 