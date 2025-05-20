-- 在users表中添加剩余导入数量字段
ALTER TABLE `users` ADD COLUMN `remaining_import_count` INT NOT NULL DEFAULT 1 COMMENT '剩余可导入本地文档的数量';
 
-- 更新现有用户的导入数量（可选）
UPDATE `users` SET `remaining_import_count` = 1 WHERE `remaining_import_count` IS NULL; 