-- =====================================================
-- テストデータリセット
-- 各テスト後に実行して初期状態に戻す
-- =====================================================
USE lock_test_db;

-- AUTO_INCREMENTリセットのためTRUNCATEを使用
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE orders;
TRUNCATE TABLE products;
SET FOREIGN_KEY_CHECKS = 1;

-- accountsはDELETE + 再INSERTでPKギャップを保持
DELETE FROM accounts;

-- accounts再挿入
INSERT INTO accounts (id, name, balance, status) VALUES
  (10, 'Alice',    1000.00, 'active'),
  (20, 'Bob',      2000.00, 'active'),
  (30, 'Charlie',  3000.00, 'active'),
  (40, 'Diana',     500.00, 'inactive'),
  (50, 'Eve',      4000.00, 'active');

-- orders再挿入
INSERT INTO orders (account_id, amount, status) VALUES
  (10, 100.00, 'completed'),
  (20, 200.00, 'completed'),
  (10, 150.00, 'pending'),
  (30, 300.00, 'pending'),
  (20, 250.00, 'pending');

-- products再挿入
INSERT INTO products (name, category_id, price, stock) VALUES
  ('Product A', 10, 1000.00, 100),
  ('Product B', 10, 2000.00,  50),
  ('Product C', 20, 1500.00, 200),
  ('Product D', 30,  800.00,  75),
  ('Product E', 30, 3000.00,  30);

SELECT 'データをリセットしました' AS message;
SELECT COUNT(*) AS accounts_count FROM accounts;
SELECT COUNT(*) AS orders_count   FROM orders;
SELECT COUNT(*) AS products_count FROM products;
