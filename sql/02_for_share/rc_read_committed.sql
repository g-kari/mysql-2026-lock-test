-- =====================================================
-- FOR SHARE（共有行ロック）- READ COMMITTED
-- 目的: READ COMMITTEDでのFOR SHARE挙動確認
--       ギャップロックなし、コミット済みデータが常に見える
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - READ COMMITTED で FOR SHARE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力（REPEATABLE READと同じ）:
--   LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   TABLE     | IS            | NULL
--   RECORD    | S,REC_NOT_GAP | 30

-- =====================================================
-- Step 3: Session B - 他のセッションがコミット済みデータを変更
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- -- FOR SHARE中でも他セッションからのSELECT（通常）は可能
-- SELECT * FROM accounts WHERE id = 30;  -- 読み取りOK
--
-- -- READ COMMITTEDの特徴: Session Bがコミットすると
-- -- Session AのFOR SHARE中でも最新値が見える（Non-Repeatable Read）
-- -- Session A のFOR SHARE後にデモ:
-- --   Session B: UPDATE accounts SET balance = 9999 WHERE id = 20; COMMIT;
-- --   Session A: SELECT * FROM accounts WHERE id = 20;
-- --              → balance=9999 が見える（Non-Repeatable Read）

-- =====================================================
-- Step 4: Observer - ロック状態の再確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql

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
-- - LOCK_MODE: S,REC_NOT_GAP
-- - ギャップロック: なし
-- - Non-Repeatable Read: 確認できたか
-- - 備考:
