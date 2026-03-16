-- =====================================================
-- AUTO-INC Lock - mode=1 (consecutive) の詳細検証
-- 目的: シンプルINSERTとバルクINSERTの挙動の違いを確認
--       シンプルINSERTは並行実行可能、バルクINSERTはテーブルロック
-- =====================================================
USE lock_test_db;

SHOW VARIABLES LIKE 'innodb_autoinc_lock_mode';
SELECT id, account_id, amount FROM orders ORDER BY id;

-- =====================================================
-- 分類: シンプルINSERT vs バルクINSERT
-- =====================================================
-- シンプルINSERT（行数が事前確定）:
--   INSERT INTO t VALUES (...)
--   INSERT INTO t VALUES (...), (...), (...)
--   → 軽量ロック（mutex）を短時間取得して連番を割り当て
--   → AUTO-INCテーブルロックは不要
--
-- バルクINSERT（行数が事前不明）:
--   INSERT INTO t SELECT ... FROM ...
--   LOAD DATA INFILE ...
--   → テーブルレベルAUTO-INCロックが必要（mode=1でも）
--   → 他のINSERTをブロック

-- =====================================================
-- シナリオ 1: シンプルINSERT の並行実行（ブロックなし）
-- =====================================================
-- Step 1: Session A
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status) VALUES (10, 111.00, 'pending');
-- INSERT INTO orders (account_id, amount, status) VALUES (10, 222.00, 'pending');

-- Step 2: Session B（Session AがCOMMITしていない間に実行）
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status) VALUES (20, 333.00, 'pending');
-- -- mode=1 のシンプルINSERT → 即時完了（ブロックなし）

-- Observer: data_locksにAUTO_INCロックが表示されないことを確認

-- 両セッション: COMMIT;
-- 結果確認:
-- SELECT id, account_id, amount FROM orders ORDER BY id;
-- -- Session Aとセッション Bの行が混在した連番になる可能性あり

-- =====================================================
-- シナリオ 2: バルクINSERT（テーブルロック発生）
-- =====================================================
-- source sql/helpers/reset_data.sql

-- Step 1: Session A - INSERT...SELECT（バルクINSERT）
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status)
--   SELECT account_id, amount * 1.1, 'pending'
--   FROM orders WHERE status = 'completed';
-- -- mode=1 でもバルクINSERTはAUTO-INCテーブルロックを取得

-- Step 2: Observer - AUTO-INCテーブルロック確認
-- source sql/helpers/observe_locks.sql
-- -- LOCK_MODE = 'AUTO_INC' が表示されることを確認

-- Step 3: Session B - シンプルINSERT試行
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status) VALUES (30, 999.00, 'pending');
-- -- ← ブロック（AUTO-INCテーブルロック中）

-- Step 4: Observer
-- source sql/helpers/observe_lock_waits.sql

-- Step 5: Session A: COMMIT;
-- Session B がブロック解除 → 即時完了

-- =====================================================
-- クリーンアップ
-- =====================================================
-- 両セッション: COMMIT;
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - シンプルINSERT並行実行: ブロックなし
-- - バルクINSERT（INSERT...SELECT）: AUTO-INCロック = あり/なし
-- - mode=1でのAUTO_INCテーブルロック表示: あり（バルク） / なし（シンプル）
-- - 備考:
