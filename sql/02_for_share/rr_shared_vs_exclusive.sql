-- =====================================================
-- FOR SHARE vs FOR UPDATE 競合シナリオ
-- 目的: 共有ロック・排他ロック互換性マトリクスの実証
--       S+S=OK, S+X=NG, X+X=NG を確認
-- =====================================================
USE lock_test_db;

-- ロック互換性マトリクス（InnoDB行ロック）:
--
--            要求ロック
--           | S (FOR SHARE) | X (FOR UPDATE)
-- 保持ロック |---------------|---------------
-- S (SHARE)  |      ○        |      ×
-- X (UPDATE) |      ×        |      ×

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- シナリオ 1: S + S = 互換（ブロックなし）
-- =====================================================
-- Step 1: Session A
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;  -- S取得

-- Step 2: Session B
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;  -- S + S = OK → 即時取得
-- -- ← ブロックされない！

-- Step 3: Observer
-- source sql/helpers/observe_locks.sql
-- -- 2つのSロックが同時に保持されていることを確認
-- -- LOCK_STATUS = 'GRANTED' が2件

-- 両セッション: ROLLBACK;

-- =====================================================
-- シナリオ 2: S + X = 競合（ブロックあり）
-- =====================================================
-- Step 1: Session A
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;  -- S取得

-- Step 2: Session B
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE; -- X + S = NG → ブロック
-- -- ← ブロック！

-- Step 3: Observer
-- source sql/helpers/observe_lock_waits.sql
-- -- WAIT_LOCK_MODE = X, BLOCK_LOCK_MODE = S

-- Session A: COMMIT;  -- Session Bがブロック解除
-- Session B: COMMIT;

-- =====================================================
-- シナリオ 3: X + X = 競合（ブロックあり）
-- =====================================================
-- Step 1: Session A
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;  -- X取得

-- Step 2: Session B
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;  -- X + X = NG → ブロック
-- -- ← ブロック！

-- Step 3: Observer
-- source sql/helpers/observe_lock_waits.sql

-- Session A: COMMIT;
-- Session B: COMMIT;

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- シナリオ1 (S+S): ブロック = なし
-- シナリオ2 (S+X): ブロック = あり
-- シナリオ3 (X+X): ブロック = あり
-- 備考:
