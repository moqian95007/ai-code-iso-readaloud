# ReadAloud 后台管理系统

这是ReadAloud iOS应用的后台管理系统。使用PHP 7.4开发，提供用户管理、数据查看和API接口功能。

## 系统要求

- PHP 7.4+
- MySQL 5.7+
- Web服务器（Apache/Nginx）

## 安装步骤

1. 将整个`admin`目录上传到宝塔面板的网站根目录
2. 创建MySQL数据库`readaloud`（如已创建则跳过此步骤）
3. 导入数据库初始化脚本：`sql/init.sql`
4. 配置Web服务器（宝塔面板会自动配置）

## 数据库配置

数据库配置信息已包含在`config.php`文件中：

- 数据库名：readaloud
- 用户名：readaloud
- 密码：Yj5YB76hsRLXxJdM

## 默认管理员账号

- 用户名：admin
- 密码：admin123

首次登录后请立即修改密码。

## 系统功能

本系统提供以下功能：

1. **管理员登录**：安全的登录系统
2. **用户管理**：查看、编辑和更新用户状态
3. **用户数据**：查看用户持久化数据
4. **API接口**：提供登录、注册和数据管理的API接口

## API接口说明

系统提供以下API接口：

1. 用户注册：`/api/register.php`
2. 用户登录：`/api/login.php`
3. 获取用户数据：`/api/get_user_data.php`
4. 保存用户数据：`/api/save_user_data.php`

详细API使用文档可在管理系统登录后查看。

## 目录结构

```
admin/
  ├── api/                 # API接口文件
  │   ├── register.php     # 用户注册接口
  │   ├── login.php        # 用户登录接口
  │   ├── get_user_data.php # 获取用户数据接口
  │   └── save_user_data.php # 保存用户数据接口
  ├── sql/                 # SQL脚本
  │   └── init.sql         # 数据库初始化脚本
  ├── config.php           # 数据库配置文件
  ├── functions.php        # 通用函数库
  ├── index.php            # 登录页面
  ├── dashboard.php        # 仪表盘
  ├── users.php            # 用户管理页面
  ├── edit_user.php        # 用户编辑页面
  ├── user_data.php        # 用户数据页面
  ├── api.php              # API接口文档页面
  ├── logout.php           # 退出登录
  ├── README.md            # 说明文档
  └── admin-README.MD      # 原始需求文档
```

## 安全注意事项

1. 所有密码均使用安全的哈希算法存储
2. API请求均需验证令牌
3. 所有用户输入均经过过滤和验证
4. 使用参数化查询防止SQL注入攻击

## 联系方式

如有任何问题，请联系管理员。 