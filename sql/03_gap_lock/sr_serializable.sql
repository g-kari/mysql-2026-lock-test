-- =====================================================
-- Gap Lock（ギャップロック）- SERIALIZABLE
-- 目的: SERIALIZABLEでのギャップロック挙動確認
--       通常SELECTでもギャップロックが発生することを確認
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - SERIALIZABLE で範囲SELECT（ギャップロック自動取得）
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- BEGIN;
-- SELECT * FROM accounts WHERE id > 20 AND id < 40;
-- -- SERIALIZABLE: FOR SHAREなしでも共有ギャップロックを取得
--
-- 期待されるロック:
--   TABLE:  IS
--   RECORD: S,REC_NOT_GAP on id=30    ← 共有レコードロック
--   RECORD: S,GAP on id=30            ← 共有ギャップロック (20,30)
--   RECORD: S,GAP on id=40            ← 共有ギャップロック (30,40)

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- REPEATABLE READとの違い:
--   REPEATABLE READ + FOR UPDATE: X,GAP（排他ギャップ）
--   SERIALIZABLE + 通常SELECT:    S,GAP（共有ギャップ）

-- =====================================================
-- Step 3: Session B - ギャップ内へのINSERT（ブロックされる）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'New1', 100.00);
-- -- ← ブロック（S,GAP と INSERT Intention Lock が競合）
--
-- 共有ギャップロック(S,GAP) vs INSERT:
--   S,GAP + INSERT = 競合（ブロック）
--   共有であっても、ギャップへのINSERTはブロックする

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
-- - 通常SELECTのGap LOCK_MODE: S,GAP
-- - ギャップ内INSERT: ブロックあり（S,GAPでもINSERTはブロック）
-- - REPEATABLE READ + FOR UPDATEとの違い: X,GAP vs S,GAP
-- - 備考:
