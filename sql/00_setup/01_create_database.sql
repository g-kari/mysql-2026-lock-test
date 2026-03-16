-- =====================================================
-- データベース作成
-- =====================================================
DROP DATABASE IF EXISTS lock_test_db;
CREATE DATABASE lock_test_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE lock_test_db;

SELECT 'データベース lock_test_db を作成しました' AS message;
