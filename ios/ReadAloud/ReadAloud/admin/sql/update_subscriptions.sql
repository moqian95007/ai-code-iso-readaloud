-- 创建用户订阅表
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