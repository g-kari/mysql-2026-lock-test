-- =====================================================
-- テストデータ挿入
-- PKに意図的なギャップを持たせる設計
-- =====================================================
USE lock_test_db;

-- accounts: PK = 10, 20, 30, 40, 50（ギャップあり）
-- ギャップ: (-∞,10), (10,20), (20,30), (30,40), (40,50), (50,+∞)
INSERT INTO accounts (id, name, balance, status) VALUES
  (10, 'Alice',    1000.00, 'active'),
  (20, 'Bob',      2000.00, 'active'),
  (30, 'Charlie',  3000.00, 'active'),
  (40, 'Diana',     500.00, 'inactive'),
  (50, 'Eve',      4000.00, 'active');

-- orders: AUTO_INCREMENT（1から連番）
INSERT INTO orders (account_id, amount, status) VALUES
  (10, 100.00, 'completed'),
  (20, 200.00, 'completed'),
  (10, 150.00, 'pending'),
  (30, 300.00, 'pending'),
  (20, 250.00, 'pending');

-- products: category_id に重複あり
-- category_id: 10, 10, 20, 30, 30
-- ギャップ: (-∞,10) | 10 | (10,10) | 10 | (10,20) | 20 | (20,30) | 30 | (30,30) | 30 | (30,+∞)
INSERT INTO products (name, category_id, price, stock) VALUES
  ('Product A', 10, 1000.00, 100),
  ('Product B', 10, 2000.00,  50),
  ('Product C', 20, 1500.00, 200),
  ('Product D', 30,  800.00,  75),
  ('Product E', 30, 3000.00,  30);

-- 挿入結果確認
SELECT '=== accounts ===' AS '';
SELECT id, name, balance, status FROM accounts ORDER BY id;

SELECT '=== orders ===' AS '';
SELECT id, account_id, amount, status FROM orders ORDER BY id;

SELECT '=== products ===' AS '';
SELECT id, name, category_id, price FROM products ORDER BY id;
