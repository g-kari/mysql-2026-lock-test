-- =====================================================
-- レコードロック（Record Lock）- READ COMMITTED
-- 目的: REPEATABLE READと同じレコードロック挙動を確認
--       READ COMMITTEDでもFOR UPDATEは X,REC_NOT_GAP を取得する
-- =====================================================
USE lock_test_db;

-- 事前確認
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - READ COMMITTED で FOR UPDATE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
--
-- READ COMMITTEDでも同じく X,REC_NOT_GAP が設定される
-- （ただしギャップロックは発生しない）

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力（REPEATABLE READと同じ）:
--   LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   TABLE     | IX            | NULL
--   RECORD    | X,REC_NOT_GAP | 30

-- =====================================================
-- Step 3: Session B - 同一行へのUPDATE（ブロックされる）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- UPDATE accounts SET balance = 9999.00 WHERE id = 30;
-- -- ← ブロック（REPEATABLE READと同じ挙動）

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
-- - LOCK_MODE: X,REC_NOT_GAP（REPEATABLE READと同じ）
-- - ギャップロック: なし
-- - ブロック(同一行UPDATE): あり
-- - 備考: PKによるポイント検索はどの分離レベルでも同じレコードロック
