-- =====================================================
-- READ COMMITTED - ギャップロックなし = INSERT Intention 競合なし
-- 目的: READ COMMITTEDではギャップロックが発生しないため
--       INSERT Intention Lockもギャップロックと競合しないことを確認
-- =====================================================
USE lock_test_db;

-- accounts PK: 10, 20, 30, 40, 50
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - READ COMMITTED で範囲 FOR UPDATE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- BEGIN;
-- SELECT * FROM accounts WHERE id > 20 AND id < 40 FOR UPDATE;
-- -- READ COMMITTED: X,REC_NOT_GAP on id=30 のみ（Gap Lockなし）

-- =====================================================
-- Step 2: Observer - ロック確認（Gap Lockなし）
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- -- X,REC_NOT_GAP のみ（X,GAP は表示されない）

-- =====================================================
-- Step 3: Session B - ギャップ内へのINSERT（即時完了）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'New1', 100.00);
-- -- ← 即時完了！（Gap Lockがないため INSERT Intentionも競合なし）
--
-- INSERT INTO accounts (id, name, balance) VALUES (35, 'New2', 200.00);
-- -- ← 即時完了！
--
-- COMMIT;

-- =====================================================
-- Step 4: Observer - ロック状態の確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- -- Session BのINSERT後もGap Lockは発生していないことを確認

-- =====================================================
-- Step 5: Session A - コミット
-- 別ターミナル(Session A)で実行
-- =====================================================
-- COMMIT;

-- =====================================================
-- REPEATABLE READ vs READ COMMITTED の比較サマリ
-- =====================================================
-- 操作: SELECT ... WHERE id > 20 AND id < 40 FOR UPDATE
--
-- REPEATABLE READ:
--   - X,REC_NOT_GAP on id=30（レコードロック）
--   - X,GAP on id=30, id=40（ギャップロック）
--   - ギャップ内INSERT → ブロック（INSERT Intentionとの競合）
--   - ファントムリード防止: ○
--
-- READ COMMITTED:
--   - X,REC_NOT_GAP on id=30（レコードロックのみ）
--   - ギャップ内INSERT → ブロックなし
--   - ファントムリード防止: ×（ファントムリードが発生する）

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - READ COMMITTEDのLOCK_MODE: X,REC_NOT_GAP のみ
-- - ギャップ内INSERT: 即時完了（ブロックなし）
-- - REPEATABLE READとの比較: Gap Lock有無が最大の違い
-- - 備考:
