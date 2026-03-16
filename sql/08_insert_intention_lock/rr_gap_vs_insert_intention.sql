-- =====================================================
-- Insert Intention Lock vs Gap Lock
-- 目的: INSERT Intention LockがGap Lockと競合することを確認
--       LOCK_MODEに 'INSERT_INTENTION' が現れることを観察
-- =====================================================
USE lock_test_db;

-- accounts PK: 10, 20, 30, 40, 50
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - ギャップロック設定（INSERT防止）
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE id > 20 AND id < 40 FOR UPDATE;
-- -- ギャップ(20,30)と(30,40)にX,GAPロックが設定される

-- =====================================================
-- Step 2: Observer - ギャップロック確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- -- X,GAP が id=30, id=40 に設定されていることを確認

-- =====================================================
-- Step 3: Session B - ギャップ内へのINSERT試行
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'New', 100.00);
-- -- ← ブロック！
-- -- INSERT前に INSERT Intention Lock を取得しようとするが
-- -- 既存のGap Lock(X,GAP)と競合するためブロックされる

-- =====================================================
-- Step 4: Observer - INSERT Intention Lock の待機確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- -- 待機中のINSERT Intention Lockが表示される:
-- --   LOCK_MODE = 'X,INSERT_INTENTION', LOCK_STATUS = 'WAITING'
-- --   LOCK_DATA = '30'（挿入しようとしているギャップの上限）
--
-- source sql/helpers/observe_lock_waits.sql
-- -- 待機の詳細確認:
-- --   WAIT_LOCK_MODE: X,INSERT_INTENTION
-- --   BLOCK_LOCK_MODE: X,GAP

-- =====================================================
-- Gap Lock と INSERT Intention Lock の関係:
-- =====================================================
-- X,GAP      + X,INSERT_INTENTION = 競合（ブロック）
-- S,GAP      + X,INSERT_INTENTION = 競合（ブロック）
-- X,INSERT_INTENTION + X,INSERT_INTENTION = 互換（ブロックしない）
--
-- つまりGap Lockは「ギャップへの挿入を禁止する」ための仕組み
-- INSERT Intention Lock = "このギャップにINSERTしようとしている"というシグナル

-- =====================================================
-- Step 5: Session A - コミット（Session Bのブロック解除）
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
-- - INSERT Intention LockのLOCK_MODE: X,INSERT_INTENTION
-- - LOCK_STATUS（ブロック中）: WAITING
-- - ブロックの原因: X,GAP（Gap Lock）
-- - 備考:
