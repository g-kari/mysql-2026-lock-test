-- =====================================================
-- FOR SHARE（共有行ロック）- REPEATABLE READ
-- 目的: REPEATABLE READでのFOR SHARE挙動確認
--       共有ロック同士は互換、排他ロックとは競合することを確認
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - FOR SHARE でロック取得
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;
--
-- 期待されるロック:
--   TABLE:  IS（Intent Shared）
--   RECORD: S,REC_NOT_GAP（共有レコードロック）

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   TABLE     | IS            | NULL        ← Intent Shared
--   RECORD    | S,REC_NOT_GAP | 30          ← 共有レコードロック

-- =====================================================
-- Step 3: Session B - 共有ロック（互換 → ブロックされない）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- -- 共有ロック同士は互換 → 即時取得
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;
-- -- ← ブロックされない！（S + S = 互換）

-- =====================================================
-- Step 3b: Session B - 排他ロック（競合 → ブロック）
-- =====================================================
-- -- 前のFOR SHAREをROLLBACKしてから:
-- ROLLBACK;
-- BEGIN;
-- -- 排他ロックは共有ロックと競合 → ブロック
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
-- -- ← ブロック（S + X = 競合）

-- =====================================================
-- Step 4: Observer - 待機状態確認（Step 3b実行後）
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
-- - LOCK_MODE: S,REC_NOT_GAP（テーブルはIS）
-- - 共有ロック同士（S+S）: 互換（ブロックなし）
-- - 共有+排他（S+X）: 競合（ブロックあり）
-- - 備考:
