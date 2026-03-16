-- =====================================================
-- ファントムリード防止の検証
-- 目的: REPEATABLE READのNext-Key Lockがファントムリードを防ぐことを確認
--       READ COMMITTEDでは発生するファントムリードとの比較
-- =====================================================
USE lock_test_db;

-- accounts: id=10(bal=1000), 20(bal=2000), 30(bal=3000), 40(bal=500), 50(bal=4000)
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- シナリオ 1: REPEATABLE READ - ファントムリード防止
-- =====================================================

-- Step 1a: Session A - 最初の範囲SELECT
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE balance > 1500.00 ORDER BY id;
-- -- 結果: id=20(2000), 30(3000), 50(4000) の3行
-- -- この時点でGap LockとRecord Lockが設定される

-- Step 1b: Session B - 条件に合う新行のINSERT試行
-- BEGIN;
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'Phantom', 2500.00);
-- -- ← REPEATABLE READではブロック！（idx_balanceのGap Lockが保護）

-- Step 1c: Session A - 再度同じ範囲SELECT
-- SELECT * FROM accounts WHERE balance > 1500.00 ORDER BY id;
-- -- 結果: 変わらず id=20, 30, 50 の3行（ファントムリードなし）

-- Session A: COMMIT;
-- Session B: ROLLBACK;  -- ブロックが解除されたらROLLBACK

-- =====================================================
-- シナリオ 2: READ COMMITTED - ファントムリード発生
-- =====================================================

-- Step 2a: Session A - 最初の範囲SELECT
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- BEGIN;
-- SELECT * FROM accounts WHERE balance > 1500.00 ORDER BY id;
-- -- 結果: id=20(2000), 30(3000), 50(4000) の3行

-- Step 2b: Session B - 新行のINSERT（即時完了）
-- BEGIN;
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'Phantom', 2500.00);
-- -- ← 即時完了！（READ COMMITTEDはGap Lockなし）
-- COMMIT;

-- Step 2c: Session A - 再度同じ範囲SELECT
-- SELECT * FROM accounts WHERE balance > 1500.00 ORDER BY id;
-- -- 結果: id=20, 25(!), 30, 50 の4行
-- -- ← ファントムリード発生！Session Bの新行が見える

-- Session A: COMMIT;

-- =====================================================
-- Observer での確認（Step 1 実行中）
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- -- REPEATABLE READ では idx_balance にもGap Lockが設定されることを確認

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- シナリオ1（REPEATABLE READ）:
-- - Session BのINSERT: ブロックあり
-- - 2回目のSELECT結果: 変化なし（ファントムリードなし）
-- シナリオ2（READ COMMITTED）:
-- - Session BのINSERT: 即時完了
-- - 2回目のSELECT結果: 新行が見える（ファントムリード発生！）
-- 備考:
