-- =====================================================
-- テーブル作成
-- =====================================================
USE lock_test_db;

-- accounts テーブル
-- PKに意図的なギャップ（10,20,30,40,50）を持たせる
-- Gap Lock / Next-Key Lock の検証に使用
DROP TABLE IF EXISTS accounts;
CREATE TABLE accounts (
  id         INT           NOT NULL,
  name       VARCHAR(100)  NOT NULL,
  balance    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  status     VARCHAR(20)   NOT NULL DEFAULT 'active',
  created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_balance (balance),
  INDEX idx_status (status)
) ENGINE=InnoDB;

-- orders テーブル
-- AUTO_INCREMENT PK（AUTO-INCロック検証用）
-- idx_account でセカンダリインデックスのロック検証
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
  id         INT           NOT NULL AUTO_INCREMENT,
  account_id INT           NOT NULL,
  amount     DECIMAL(10,2) NOT NULL,
  status     VARCHAR(20)   NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_account (account_id),
  INDEX idx_status (status)
) ENGINE=InnoDB;

-- products テーブル
-- category_id に重複値（10,10,20,30,30）を持たせる
-- セカンダリインデックスのNext-Key Lock検証に使用
DROP TABLE IF EXISTS products;
CREATE TABLE products (
  id          INT           NOT NULL AUTO_INCREMENT,
  name        VARCHAR(100)  NOT NULL,
  category_id INT           NOT NULL,
  price       DECIMAL(10,2) NOT NULL,
  stock       INT           NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  INDEX idx_category (category_id),
  INDEX idx_price (price)
) ENGINE=InnoDB;

SELECT 'テーブルを作成しました: accounts, orders, products' AS message;
SHOW TABLES;
