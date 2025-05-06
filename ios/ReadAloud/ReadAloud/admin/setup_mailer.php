<?php
/**
 * PHPMailer 安装脚本
 * 使用 Composer 安装 PHPMailer 库
 */

// 检查是否已安装 Composer
echo "正在检查 Composer 是否已安装...\n";

$composerExists = false;
$composerCommand = 'composer';

// 检查 composer 命令是否可用
exec('which composer 2>/dev/null', $output, $returnVar);
if ($returnVar === 0 && !empty($output)) {
    $composerExists = true;
    $composerCommand = $output[0];
    echo "找到 Composer: {$composerCommand}\n";
} else {
    exec('which composer.phar 2>/dev/null', $output, $returnVar);
    if ($returnVar === 0 && !empty($output)) {
        $composerExists = true;
        $composerCommand = $output[0];
        echo "找到 Composer (composer.phar): {$composerCommand}\n";
    }
}

if (!$composerExists) {
    echo "未找到 Composer，尝试下载安装...\n";
    
    // 下载 Composer 安装程序
    $installerUrl = 'https://getcomposer.org/installer';
    $installerPath = __DIR__ . '/composer-setup.php';
    
    echo "下载 Composer 安装程序...\n";
    $installerContent = @file_get_contents($installerUrl);
    
    if ($installerContent === false) {
        echo "下载 Composer 安装程序失败，请手动安装 Composer 并运行 'composer require phpmailer/phpmailer'\n";
        exit(1);
    }
    
    if (file_put_contents($installerPath, $installerContent) === false) {
        echo "无法保存 Composer 安装程序，请检查目录权限\n";
        exit(1);
    }
    
    echo "运行 Composer 安装程序...\n";
    exec("php {$installerPath}", $output, $returnVar);
    
    if ($returnVar !== 0) {
        echo "安装 Composer 失败，请手动安装 Composer 并运行 'composer require phpmailer/phpmailer'\n";
        @unlink($installerPath);
        exit(1);
    }
    
    // 清理安装程序
    @unlink($installerPath);
    
    $composerCommand = __DIR__ . '/composer.phar';
    echo "Composer 已成功安装到: {$composerCommand}\n";
}

// 检查是否已有 composer.json
$composerJsonPath = __DIR__ . '/composer.json';
if (!file_exists($composerJsonPath)) {
    echo "创建 composer.json 文件...\n";
    $composerJson = [
        'require' => [
            'phpmailer/phpmailer' => '^6.6'
        ]
    ];
    file_put_contents($composerJsonPath, json_encode($composerJson, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
}

// 安装 PHPMailer
echo "安装 PHPMailer...\n";
$command = "php {$composerCommand} require phpmailer/phpmailer";
exec($command, $output, $returnVar);

echo implode("\n", $output) . "\n";

if ($returnVar !== 0) {
    echo "安装 PHPMailer 失败，请手动运行 'composer require phpmailer/phpmailer'\n";
    exit(1);
}

echo "PHPMailer 安装成功！\n";
echo "请在 mail_config.php 文件中配置您的邮件服务器信息。\n";

// 验证安装
if (file_exists(__DIR__ . '/vendor/phpmailer/phpmailer/src/PHPMailer.php')) {
    echo "验证 PHPMailer 安装: 成功\n";
} else {
    echo "验证 PHPMailer 安装: 失败，未找到 PHPMailer 文件\n";
}

echo "安装过程完成。\n";
?> 