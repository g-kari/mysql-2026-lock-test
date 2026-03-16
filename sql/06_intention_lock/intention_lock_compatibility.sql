-- =====================================================
-- Intention Lock 互換性マトリクスの実証
-- 目的: IS/IX同士の互換性と、S/X テーブルロックとの競合を実際に確認
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- シナリオ 1: IX + IX = 互換（異なる行）
-- =====================================================
-- Step 1: Session A
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;  -- テーブルIX + 行X

-- Step 2: Session B
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 20 FOR UPDATE;  -- テーブルIX + 行X
-- -- ← ブロックされない！（IX + IX = 互換、異なる行なのでX同士も競合しない）

-- Step 3: Observer
-- source sql/helpers/observe_locks.sql
-- -- テーブルIXが2つ（両セッション分）表示されることを確認

-- 両セッション: ROLLBACK;

-- =====================================================
-- シナリオ 2: IS + IX = 互換（テーブルレベルは互換だが行レベルで競合可）
-- =====================================================
-- Step 1: Session A
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;  -- テーブルIS + 行S

-- Step 2: Session B
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;  -- テーブルIX + 行X
-- -- テーブルレベル: IS + IX = 互換（ブロックなし）
-- -- 行レベル: S + X = 競合（ブロックあり）
-- -- ← 行ロックでブロック！（テーブルは通過できるが行で止まる）

-- Step 3: Observer
-- source sql/helpers/observe_locks.sql
-- source sql/helpers/observe_lock_waits.sql

-- Session A: COMMIT;
-- Session B: COMMIT;

-- =====================================================
-- シナリオ 3: IX + テーブルX = 競合
-- =====================================================
-- Step 1: Session A
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;  -- テーブルIX

-- Step 2: Session B
-- LOCK TABLES accounts WRITE;  -- テーブルX
-- -- ← ブロック！（IX + テーブルX = 競合）

-- Session A: COMMIT;
-- Session B: UNLOCK TABLES;

-- =====================================================
-- シナリオ 4: IS + テーブルS = 互換
-- =====================================================
-- Step 1: Session A
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR SHARE;  -- テーブルIS

-- Step 2: Session B
-- LOCK TABLES accounts READ;  -- テーブルS
-- -- ← ブロックされない！（IS + テーブルS = 互換）

-- Step 3: Session B がテーブル共有ロックを保持中に行更新を試みる
-- UPDATE accounts SET balance = 1234 WHERE id = 20;
-- -- ← ERROR: Table 'accounts' was locked with a READ lock and can't be updated

-- Session A: COMMIT;
-- Session B: UNLOCK TABLES;

-- =====================================================
-- Observer の使用
-- =====================================================
-- 各シナリオでロック状態を確認:
-- source sql/helpers/observe_locks.sql
-- source sql/helpers/observe_lock_waits.sql

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- シナリオ1（IX+IX）: テーブルブロックなし、行ブロックなし（異なる行）
-- シナリオ2（IS+IX）: テーブルブロックなし、行ブロックあり（同一行S+X）
-- シナリオ3（IX+テーブルX）: ブロックあり
-- シナリオ4（IS+テーブルS）: ブロックなし
-- 備考:
