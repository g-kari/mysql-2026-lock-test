-- =====================================================
-- Next-Key Lock - セカンダリインデックス（products.category_id）
-- 目的: セカンダリインデックスでのNext-Key Lock確認
--       セカンダリ + PK の両方にロックが設定される
-- =====================================================
USE lock_test_db;

-- products: id=1(cat=10), id=2(cat=10), id=3(cat=20), id=4(cat=30), id=5(cat=30)
-- idx_category のB-Treeイメージ:
--   (cat=10,id=1), (cat=10,id=2), (cat=20,id=3), (cat=30,id=4), (cat=30,id=5)
-- Next-Key Lock の範囲:
--   (-∞, (10,1)] | ((10,1), (10,2)] | ((10,2), (20,3)] | ((20,3), (30,4)] | ((30,4), (30,5)] | ((30,5), +∞)
SELECT id, name, category_id FROM products ORDER BY category_id, id;

-- =====================================================
-- Step 1: Session A - セカンダリインデックスで FOR UPDATE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM products WHERE category_id = 20 FOR UPDATE;
-- -- 結果: id=3 (category_id=20) の1行
--
-- 設定されるロック:
--   TABLE:  IX
--   idx_category: X on (cat=20, id=3)  = Next-Key Lock ((10,2), (20,3)]
--   idx_category: X,GAP on (cat=30, id=4) = Gap Lock ((20,3), (30,4))
--   PRIMARY: X,REC_NOT_GAP on id=3

-- =====================================================
-- Step 2: Observer - セカンダリ + PK ロック確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   INDEX_NAME   | LOCK_MODE     | LOCK_DATA
--   NULL         | IX            | NULL
--   idx_category | X             | 20, 3       ← セカンダリNext-Key Lock
--   idx_category | X,GAP         | 30, 4       ← セカンダリGap Lock
--   PRIMARY      | X,REC_NOT_GAP | 3           ← PKレコードロック
--
-- セカンダリインデックス検索時の2段階ロック:
--   1. idx_categoryにX（Next-Key Lock）とX,GAP
--   2. 対応するPKにX,REC_NOT_GAP
--
-- なぜPKにもロック?
--   → PKを直接更新されるのを防ぐため
--   → セカンダリだけロックしても、PK経由の更新は防げない

-- =====================================================
-- Step 3: Session B - 競合操作の確認
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- -- category_id=20 の行をPKで直接更新 → ブロック（PKにX,REC_NOT_GAPが設定されているため）
-- UPDATE products SET price = 9999.00 WHERE id = 3;
-- -- ← ブロック
--
-- -- category_id=25 のINSERT（ギャップ(20,30)内）→ ブロック
-- INSERT INTO products (name, category_id, price) VALUES ('NewProd', 25, 1000.00);
-- -- ← ブロック（idx_categoryのGap Lock）
--
-- -- category_id=10 のINSERT → ブロックされない
-- INSERT INTO products (name, category_id, price) VALUES ('NewProd10', 10, 999.00);
-- -- ← 即時完了

-- =====================================================
-- Step 4: Observer - 待機状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_lock_waits.sql

-- =====================================================
-- Step 5: Session A - コミット
-- 別ターミナル(Session A)で実行
-- =====================================================
-- COMMIT;

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Session B: ROLLBACK;
-- Observer:  source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - セカンダリのLOCK_DATA形式: "category_id値, id値"
-- - PKのLOCK_DATA形式: "id値"
-- - セカンダリGap Lockの範囲: (cat=20, id=3) 〜 (cat=30, id=4)
-- - 備考:
