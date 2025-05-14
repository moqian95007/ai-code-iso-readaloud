-- 数据库结构更新脚本

-- 添加account_id和login_type字段
ALTER TABLE users ADD COLUMN account_id VARCHAR(255) NULL AFTER email;
ALTER TABLE users ADD COLUMN login_type ENUM('email', 'apple', 'google') DEFAULT 'email' AFTER account_id;

-- 创建索引，确保account_id和login_type的组合唯一性
ALTER TABLE users ADD UNIQUE INDEX idx_account_login (account_id, login_type);

-- 更新现有数据
-- 对于已有的email用户，使用email作为account_id，登录类型为email
UPDATE users SET account_id = email, login_type = 'email' WHERE account_id IS NULL AND email IS NOT NULL AND email != '';

-- 对于已有的Apple用户，使用apple_id作为account_id，登录类型为apple
UPDATE users SET account_id = apple_id, login_type = 'apple' WHERE account_id IS NULL AND apple_id IS NOT NULL AND apple_id != '';

-- 对于已有的Google用户，使用google_id作为account_id，登录类型为google
UPDATE users SET account_id = google_id, login_type = 'google' WHERE account_id IS NULL AND google_id IS NOT NULL AND google_id != '';

-- 移除email的唯一约束（如果存在）
ALTER TABLE users DROP INDEX email; -- 如果email列上有唯一索引，请取消注释此行

-- 注意：此脚本仅供参考，执行前请备份数据库 