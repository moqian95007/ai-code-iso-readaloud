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
INSERT INTO `system_info` (`key`, `value`) VALUES ('db_version', '1.1') ON DUPLICATE KEY UPDATE `value` = '1.1'; 