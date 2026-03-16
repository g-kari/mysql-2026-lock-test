-- =====================================================
-- FOR UPDATE（排他行ロック）- SERIALIZABLE
-- 目的: SERIALIZABLEでのFOR UPDATE挙動確認
--       通常SELECTも共有ロックを取得するため、競合パターンが増える
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - SERIALIZABLE で FOR UPDATE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   TABLE     | IX            | NULL
--   RECORD    | X,REC_NOT_GAP | 30

-- =====================================================
-- Step 3: Session B - 複数パターンで競合確認
-- 別ターミナル(Session B)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- BEGIN;
--
-- パターン1: FOR UPDATE → ブロック（X vs X 競合）
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
--
-- パターン2: 通常SELECT → ブロック（X vs S 競合）
-- SERIALIZABLEでは通常SELECTも共有ロックを取得しようとするため
-- Session Aの排他ロックと競合してブロックされる
-- SELECT * FROM accounts WHERE id = 30;
--
-- パターン3: 別の行 → ブロックされない
-- SELECT * FROM accounts WHERE id = 20 FOR UPDATE;  -- 即時完了

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
-- Session B: COMMIT;
-- Observer:  source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - LOCK_MODE: X,REC_NOT_GAP
-- - ブロック(FOR UPDATE): あり
-- - ブロック(通常SELECT): あり（SERIALIZABLEの特徴）
-- - ブロック(別行): なし
-- - 備考:
