-- =====================================================
-- Gap Lock vs INSERT - ギャップ位置による差異
-- 目的: ロックされたギャップ内 vs 外でのINSERTの挙動差を詳細に確認
--       どのギャップがロックされているかを正確に把握する
-- =====================================================
USE lock_test_db;

-- accounts PK: 10, 20, 30, 40, 50
-- ギャップ一覧:
--   Gap A: (-∞, 10)
--   Gap B: (10, 20)
--   Gap C: (20, 30)  ← ロック対象
--   Gap D: (30, 40)  ← ロック対象
--   Gap E: (40, 50)
--   Gap F: (50, +∞)
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - 特定範囲にギャップロック設定
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE id > 20 AND id < 40 FOR UPDATE;
-- -- ロック対象:
-- --   Gap C: (20, 30) にギャップロック
-- --   Gap D: (30, 40) にギャップロック
-- --   id=30 にレコードロック

-- =====================================================
-- Step 2: Observer - ギャップロック範囲の確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- LOCK_DATA の解釈:
--   LOCK_DATA = '30' で LOCK_MODE = 'X,GAP' → id=30の「前のギャップ」 = (20,30)
--   LOCK_DATA = '40' で LOCK_MODE = 'X,GAP' → id=40の「前のギャップ」 = (30,40)

-- =====================================================
-- Step 3: Session B - 各ギャップへのINSERT試行
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
--
-- id=15 (Gap B: 10〜20 → ロックなし) → 即時完了
-- INSERT INTO accounts (id, name, balance) VALUES (15, 'New_GapB', 300.00);
-- SELECT ROW_COUNT();  -- 1
--
-- id=25 (Gap C: 20〜30 → ロックあり) → ブロック！
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'New_GapC', 100.00);
-- -- ← ブロック
--
-- id=35 (Gap D: 30〜40 → ロックあり) → ブロック！
-- INSERT INTO accounts (id, name, balance) VALUES (35, 'New_GapD', 200.00);
-- -- ← ブロック
--
-- id=45 (Gap E: 40〜50 → ロックなし) → 即時完了
-- INSERT INTO accounts (id, name, balance) VALUES (45, 'New_GapE', 400.00);
-- SELECT ROW_COUNT();  -- 1

-- =====================================================
-- Step 4: Observer - 待機状態確認（id=25 INSERTのブロック中）
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
-- - Gap B (10,20) へのINSERT: ブロックなし
-- - Gap C (20,30) へのINSERT: ブロックあり
-- - Gap D (30,40) へのINSERT: ブロックあり
-- - Gap E (40,50) へのINSERT: ブロックなし
-- - LOCK_DATAの解釈: ギャップの上限レコードのPK値
-- - 備考:
