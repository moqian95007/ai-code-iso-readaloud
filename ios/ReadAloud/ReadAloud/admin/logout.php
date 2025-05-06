<?php
require_once 'functions.php';

// 销毁所有会话变量
$_SESSION = array();

// 如果使用会话cookie，则将其清除
if (ini_get("session.use_cookies")) {
    $params = session_get_cookie_params();
    setcookie(session_name(), '', time() - 42000,
        $params["path"], $params["domain"],
        $params["secure"], $params["httponly"]
    );
}

// 最后销毁会话
session_destroy();

// 重定向到登录页面
redirect('index.php');
?> 