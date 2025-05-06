<?php
/**
 * PHPMailer 文件内容
 * 您可以直接复制这些内容到相应的文件中
 */
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHPMailer 文件内容</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background-color: #fff;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1, h2 {
            color: #333;
            border-bottom: 1px solid #ddd;
            padding-bottom: 10px;
        }
        .file-content {
            background-color: #f8f8f8;
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 10px;
            margin-bottom: 20px;
            font-family: monospace;
            white-space: pre-wrap;
            max-height: 500px;
            overflow-y: auto;
        }
        .button {
            background-color: #4CAF50;
            color: white;
            padding: 10px 15px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            margin-bottom: 20px;
        }
        .button:hover {
            background-color: #45a049;
        }
        .instructions {
            background-color: #e9f7ef;
            padding: 15px;
            border-radius: 4px;
            margin-bottom: 20px;
        }
        .instructions ol {
            margin-top: 10px;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>PHPMailer 文件内容</h1>
        
        <div class="instructions">
            <h2>使用说明</h2>
            <p>请按照以下步骤手动安装 PHPMailer：</p>
            <ol>
                <li>在服务器上创建目录：<code>/admin/phpmailer/src/</code></li>
                <li>在 <code>/admin/phpmailer/src/</code> 目录中创建以下三个文件：
                    <ul>
                        <li><code>Exception.php</code></li>
                        <li><code>PHPMailer.php</code></li>
                        <li><code>SMTP.php</code></li>
                    </ul>
                </li>
                <li>从下方复制每个文件的内容，粘贴到相应的文件中</li>
                <li>在 <code>/admin/phpmailer/</code> 目录中创建 <code>autoload.php</code> 文件，内容也在下方</li>
                <li>完成后，访问 <a href="setup_smtp.php">SMTP 配置页面</a> 进行邮件设置</li>
            </ol>
        </div>
        
        <h2>1. Exception.php</h2>
        <button class="button" onclick="copyToClipboard('exception-content')">复制内容</button>
        <div id="exception-content" class="file-content">
<?php echo htmlspecialchars('<?php
/**
 * PHPMailer Exception class.
 * PHP Version 5.5.
 *
 * @see       https://github.com/PHPMailer/PHPMailer/ The PHPMailer GitHub project
 *
 * @author    Marcus Bointon (Synchro/coolbru) <phpmailer@synchromedia.co.uk>
 * @author    Jim Jagielski (jimjag) <jimjag@gmail.com>
 * @author    Andy Prevost (codeworxtech) <codeworxtech@users.sourceforge.net>
 * @author    Brent R. Matzelle (original founder)
 * @copyright 2012 - 2020 Marcus Bointon
 * @copyright 2010 - 2012 Jim Jagielski
 * @copyright 2004 - 2009 Andy Prevost
 * @license   http://www.gnu.org/copyleft/lesser.html GNU Lesser General Public License
 * @note      This program is distributed in the hope that it will be useful - WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.
 */

namespace PHPMailer\PHPMailer;

/**
 * PHPMailer exception handler.
 *
 * @author Marcus Bointon <phpmailer@synchromedia.co.uk>
 */
class Exception extends \Exception
{
    /**
     * Prettify error message output.
     *
     * @return string
     */
    public function errorMessage()
    {
        return "<strong>" . htmlspecialchars($this->getMessage()) . "</strong><br />\n";
    }
}'); ?>
        </div>
        
        <h2>2. SMTP.php</h2>
        <p>由于文件太长，只显示了部分内容。您可以点击下面的链接下载完整文件：</p>
        <p><a href="https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/SMTP.php" target="_blank">下载 SMTP.php</a></p>
        
        <h2>3. PHPMailer.php</h2>
        <p>由于文件太长，只显示了部分内容。您可以点击下面的链接下载完整文件：</p>
        <p><a href="https://raw.githubusercontent.com/PHPMailer/PHPMailer/master/src/PHPMailer.php" target="_blank">下载 PHPMailer.php</a></p>
        
        <h2>4. autoload.php</h2>
        <button class="button" onclick="copyToClipboard('autoload-content')">复制内容</button>
        <div id="autoload-content" class="file-content">
<?php echo htmlspecialchars('<?php
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
});'); ?>
        </div>
    </div>
    
    <script>
        function copyToClipboard(elementId) {
            var element = document.getElementById(elementId);
            var text = element.innerText;
            
            var textArea = document.createElement("textarea");
            textArea.value = text;
            document.body.appendChild(textArea);
            textArea.select();
            document.execCommand("copy");
            document.body.removeChild(textArea);
            
            alert("内容已复制到剪贴板");
        }
    </script>
</body>
</html> 