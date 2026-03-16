-- =====================================================
-- FOR UPDATE（排他行ロック）- REPEATABLE READ
-- 目的: REPEATABLE READでのFOR UPDATEロック挙動確認
--       Next-Key Lock（ギャップ + レコード）が設定される
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - FOR UPDATE でロック取得
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
--
-- 期待されるロック:
--   TABLE:  IX（Intent Exclusive）
--   RECORD: X,REC_NOT_GAP on PRIMARY (id=30)
--
-- Note: PKによるポイント検索のためRecord Lockのみ（Gap Lockなし）
-- 範囲検索の場合はGap Lockも設定される（03_gap_lock/ 参照）

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- source sql/helpers/observe_trx.sql

-- =====================================================
-- Step 3: Session B - 競合する操作（ブロックされる）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- -- 排他ロック同士は競合 → ブロック
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
-- -- ← ERROR/タイムアウトまでブロック
--
-- -- 共有ロックも排他ロックと競合 → ブロック
-- -- SELECT * FROM accounts WHERE id = 30 FOR SHARE;
-- -- ← ブロック

-- =====================================================
-- Step 4: Observer - 待機状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_lock_waits.sql

-- =====================================================
-- Step 5: Session A - コミット（Session Bのブロック解除）
-- 別ターミナル(Session A)で実行
-- =====================================================
-- COMMIT;

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Session B: COMMIT;
-- Observer:  source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - LOCK_MODE: X,REC_NOT_GAP（PKポイント検索）
-- - ギャップロック: なし（PKポイント検索のため）
-- - ブロック(同一行 FOR UPDATE): あり
-- - ブロック(同一行 FOR SHARE): あり
-- - ブロック(別行): なし
-- - 備考:
