-- =====================================================
-- Gap Lock（ギャップロック）- READ COMMITTED ★最重要
-- 目的: READ COMMITTEDではギャップロックが発生しないことを確認
--       REPEATABLE READと比較して最大の違い
-- =====================================================
USE lock_test_db;

-- accounts PK: 10, 20, 30, 40, 50
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - READ COMMITTED で範囲検索 FOR UPDATE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- BEGIN;
-- SELECT * FROM accounts WHERE id > 20 AND id < 40 FOR UPDATE;
-- -- 結果: id=30 の1行
--
-- READ COMMITTEDでは:
--   TABLE:  IX
--   RECORD: X,REC_NOT_GAP on id=30    ← レコードロックのみ
--   ギャップロックは発生しない！

-- =====================================================
-- Step 2: Observer - ロック確認（ギャップロックなし！）
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   INDEX_NAME | LOCK_MODE     | LOCK_DATA
--   NULL       | IX            | NULL
--   PRIMARY    | X,REC_NOT_GAP | 30      ← レコードロックのみ
--
-- REPEATABLE READと比較:
--   REPEATABLE READ: X,REC_NOT_GAP + X,GAP（2種類）
--   READ COMMITTED:  X,REC_NOT_GAP のみ（1種類）
--
-- ギャップロック(X,GAP)が一切表示されないことを確認！

-- =====================================================
-- Step 3: Session B - ギャップ内へのINSERT（ブロックされない！）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- -- ギャップロックがないため、ギャップ内INSERTはブロックされない
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'New1', 100.00);
-- -- ← 即時完了！（REPEATABLE READでは ブロック）
--
-- INSERT INTO accounts (id, name, balance) VALUES (35, 'New2', 200.00);
-- -- ← 即時完了！
--
-- COMMIT;

-- =====================================================
-- Step 4: Observer - ロック状態再確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- -- Session BのINSERT後、data_locksに変化がないことを確認

-- =====================================================
-- Step 5: Session A - コミット
-- 別ターミナル(Session A)で実行
-- =====================================================
-- COMMIT;

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - LOCK_MODE: X,REC_NOT_GAP のみ（X,GAPなし）
-- - ギャップ内INSERT: ブロックなし（REPEATABLE READとの最大の違い）
-- - ファントムリード防止: なし（新しい行が見える可能性あり）
-- - 備考: READ COMMITTEDはギャップロックを取得しない
--         → INSERT競合なし、デッドロック発生率も低い
--         → ただしファントムリードが発生する
