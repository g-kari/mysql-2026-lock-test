-- =====================================================
-- レコードロック - SERIALIZABLE
-- 目的: SERIALIZABLEでは通常SELECTも共有ロックを自動取得することを確認
--       SELECT が暗黙的に FOR SHARE 相当になる
-- =====================================================
USE lock_test_db;

-- 事前確認
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - SERIALIZABLE で通常SELECT
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30;
-- -- SERIALIZABLE では FOR SHARE なしでも共有ロックを取得
-- -- （他の分離レベルではロックを取得しない）

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   TABLE     | IS            | NULL        ← Intent Shared（SERIALIZABLEの特徴）
--   RECORD    | S,REC_NOT_GAP | 30          ← 共有ロック（通常SELECTなのにロック取得！）
--
-- 他の分離レベルとの違い:
--   READ UNCOMMITTED / READ COMMITTED / REPEATABLE READ:
--     通常SELECT はロックを取得しない（スナップショット読み取り）
--   SERIALIZABLE:
--     通常SELECT でも S,REC_NOT_GAP を取得する

-- =====================================================
-- Step 3: Session B - FOR UPDATE を試行（ブロックされる）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
-- -- ← Session AのS（共有）ロックとX（排他）ロックが競合 → ブロック
--
-- Session B が通常SELECTなら:
-- SELECT * FROM accounts WHERE id = 30;
-- -- ← SERIALIZABLEでは S+S = 互換 → ブロックされない

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
-- - 通常SELECTのLOCK_MODE: S,REC_NOT_GAP（SERIALIZABLEのみ）
-- - テーブルロックのLOCK_MODE: IS（Intent Shared）
-- - ブロック(FOR UPDATE vs 通常SELECT): あり（S+X競合）
-- - ブロック(通常SELECT同士): なし（S+S互換）
-- - 備考:
