-- 向users表添加apple_id字段
ALTER TABLE `users` 
ADD COLUMN `apple_id` VARCHAR(255) NULL AFTER `email`,
ADD UNIQUE INDEX `apple_id_UNIQUE` (`apple_id` ASC);

-- 向users表添加google_id字段（为未来扩展）
ALTER TABLE `users` 
ADD COLUMN `google_id` VARCHAR(255) NULL AFTER `apple_id`,
ADD UNIQUE INDEX `google_id_UNIQUE` (`google_id` ASC);

-- 创建system_info表（如果不存在）
CREATE TABLE IF NOT EXISTS `system_info` (
  `key` VARCHAR(50) NOT NULL,
  `value` TEXT NULL,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`key`)
);

-- 记录数据库更新版本
INSERT INTO `system_info` (`key`, `value`) VALUES ('db_version', '1.2') ON DUPLICATE KEY UPDATE `value` = '1.2';

-- 更新用户表结构
ALTER TABLE `users` 
  ADD COLUMN IF NOT EXISTS `phone` varchar(20) DEFAULT NULL AFTER `email`;

-- 创建用户订阅表（如果不存在）
CREATE TABLE IF NOT EXISTS `user_subscriptions` (
  `id` varchar(36) NOT NULL COMMENT 'UUID形式的唯一标识',
  `user_id` int(11) NOT NULL COMMENT '关联的用户ID',
  `subscription_type` enum('monthly','quarterly','halfYearly','yearly') NOT NULL COMMENT '订阅类型',
  `start_date` datetime NOT NULL COMMENT '订阅开始日期',
  `end_date` datetime NOT NULL COMMENT '订阅结束日期',
  `subscription_id` varchar(255) NOT NULL COMMENT '订阅标识符（来自App Store）',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否为当前活跃订阅',
  `created_at` datetime NOT NULL COMMENT '创建时间',
  `updated_at` datetime NOT NULL COMMENT '最后更新时间',
  PRIMARY KEY (`id`),
  KEY `user_id_idx` (`user_id`),
  KEY `is_active_idx` (`is_active`),
  CONSTRAINT `user_subscriptions_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;