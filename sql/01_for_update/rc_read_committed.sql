-- =====================================================
-- FOR UPDATE（排他行ロック）- READ COMMITTED
-- 目的: READ COMMITTEDでのFOR UPDATE挙動確認
--       ギャップロックが発生しないことを確認
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - READ COMMITTED で FOR UPDATE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
--
-- READ COMMITTEDの特徴:
--   - ギャップロックは発生しない
--   - 既存レコードへのRecord Lockのみ
--   - 存在しない行への検索ではロックなし

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力（REPEATABLE READと同じ結果）:
--   LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   TABLE     | IX            | NULL
--   RECORD    | X,REC_NOT_GAP | 30

-- =====================================================
-- Step 3: Session B - 競合する操作
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- -- 同一行はブロック
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;   -- ブロック
--
-- -- 存在しない行（id=25）への検索 → ロックなし → ブロックされない
-- SELECT * FROM accounts WHERE id = 25 FOR UPDATE;   -- 即時返却（行が存在しないためロックなし）

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
-- - LOCK_MODE: X,REC_NOT_GAP
-- - ギャップロック: なし（READ COMMITTEDはギャップロックを取得しない）
-- - ブロック(同一行 FOR UPDATE): あり
-- - ブロック(存在しない行 FOR UPDATE): なし
-- - 備考: REPEATABLE READと同じRecord Lock、ただしギャップロックなし
