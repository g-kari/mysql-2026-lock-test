-- =====================================================
-- FOR SHARE（共有行ロック）- SERIALIZABLE
-- 目的: SERIALIZABLEでの FOR SHARE 挙動確認
--       通常SELECTも自動的にFOR SHARE相当になるため
--       明示的なFOR SHAREは冗長だが挙動は同じ
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - SERIALIZABLE で FOR SHARE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;
-- -- SERIALIZABLE では FOR SHARE = 通常SELECT（同じロック）

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   TABLE:  IS
--   RECORD: S,REC_NOT_GAP (id=30)
--
-- 比較: SERIALIZABLE での通常SELECT も同じロックを取得
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30;  -- FOR SHAREなしでも同じロック！

-- =====================================================
-- Step 3: Session B - FOR UPDATE は競合（ブロック）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- BEGIN;
-- -- FOR UPDATE はブロック（S + X 競合）
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
-- -- ← ブロック
--
-- -- 通常SELECT もブロック（SERIALIZABLEでは通常SELECTがS取得を試みる）
-- -- しかし S + S = 互換なのでブロックされない
-- SELECT * FROM accounts WHERE id = 30;
-- -- ← ブロックされない（S + S = OK）

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
-- - FOR SHAREのLOCK_MODE: S,REC_NOT_GAP
-- - 通常SELECTのLOCK_MODE（SERIALIZABLE）: S,REC_NOT_GAP（同じ）
-- - FOR UPDATEはブロック: あり
-- - 通常SELECT同士: ブロックなし
-- - 備考:
