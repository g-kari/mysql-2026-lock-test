-- =====================================================
-- レコードロック（Record Lock）- REPEATABLE READ
-- 目的: 最もシンプルなベースライン確認
--       PKによるポイント検索では X,REC_NOT_GAP が設定される
-- =====================================================
USE lock_test_db;

-- 事前確認
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - FOR UPDATE でレコードロック取得
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
-- -- 期待されるロック:
-- --   TABLE: lock_test_db/accounts, LOCK_TYPE=TABLE, LOCK_MODE=IX
-- --   ROW:   lock_test_db/accounts, LOCK_TYPE=ROW,   LOCK_MODE=X,REC_NOT_GAP, LOCK_DATA='30'

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- source sql/helpers/observe_trx.sql
--
-- 期待される出力:
--   LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   TABLE     | IX            | NULL
--   RECORD    | X,REC_NOT_GAP | 30
--
-- REC_NOT_GAP = ギャップロックなし（レコードのみ）

-- =====================================================
-- Step 3: Session B - 同一行へのUPDATE（ブロックされる）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- UPDATE accounts SET balance = 9999.00 WHERE id = 30;
-- -- ← ここでブロック（Session Aがリリースするまで待機）
--
-- 別の行(id=20)はブロックされない:
-- UPDATE accounts SET balance = 8888.00 WHERE id = 20;
-- -- ← 即時完了（異なる行へのロック）

-- =====================================================
-- Step 4: Observer - 待機状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_lock_waits.sql
--
-- WAIT_TRX_IDがSession Bのトランザクション
-- BLOCK_TRX_IDがSession AのトランザクションIDになることを確認

-- =====================================================
-- Step 5: Session A - コミット（Session Bのブロック解除）
-- 別ターミナル(Session A)で実行
-- =====================================================
-- COMMIT;
-- -- Session BのUPDATEが完了する

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
-- - ギャップロック: なし（PKによるポイント検索のため）
-- - ブロック(同一行UPDATE): あり
-- - ブロック(別行UPDATE): なし
-- - 備考:
