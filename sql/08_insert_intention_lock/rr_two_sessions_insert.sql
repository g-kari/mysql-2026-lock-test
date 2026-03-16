-- =====================================================
-- INSERT Intention Lock 同士の互換性確認
-- 目的: INSERT Intention Lock同士は互換（互いをブロックしない）ことを確認
--       Gap Lockがなければ同一ギャップへの同時INSERTは可能
-- =====================================================
USE lock_test_db;

-- accounts PK: 10, 20, 30, 40, 50
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- 前提: Gap Lockがない状態での検証
-- （Session AがFOR UPDATEなどのギャップロックを保持していない状態）
-- =====================================================

-- Step 1: Session A - INSERT開始（コミットしない）
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'NewA', 100.00);
-- -- INSERT Intention Lock を取得: X,INSERT_INTENTION on gap (20,30)
-- -- まだCOMMITしていない

-- Step 2: Session B - 同一ギャップ内の別idへのINSERT
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- INSERT INTO accounts (id, name, balance) VALUES (28, 'NewB', 200.00);
-- -- ← ブロックされない！
-- -- INSERT Intention Lock同士は互換
-- -- X,INSERT_INTENTION + X,INSERT_INTENTION = 互換（OK）

-- Step 3: Observer - 両方のINSERT Intentionが GRANTED であることを確認
-- source sql/helpers/observe_locks.sql
-- -- 期待される出力:
-- --   LOCK_MODE           | LOCK_STATUS | LOCK_DATA
-- --   X,INSERT_INTENTION  | GRANTED     | 30        (Session A: id=25挿入)
-- --   X,INSERT_INTENTION  | GRANTED     | 30        (Session B: id=28挿入)
-- --   X,REC_NOT_GAP       | GRANTED     | 25        (Session A: レコードロック)
-- --   X,REC_NOT_GAP       | GRANTED     | 28        (Session B: レコードロック)
--
-- source sql/helpers/observe_lock_waits.sql
-- -- 待機なし（data_lock_waitsが空）

-- =====================================================
-- Gap Lock があった場合との対比:
-- =====================================================
-- Gap LockなしのケースでINSERT Intention同士は互換 → 問題なし
-- Gap LockありのケースではINSERT Intentionはブロック → rr_gap_vs_insert_intention.sql参照

-- =====================================================
-- Step 4: 両セッションをコミット（PKユニーク制約の確認）
-- =====================================================
-- Session A: COMMIT;  -- id=25 が挿入される
-- Session B: COMMIT;  -- id=28 が挿入される
--
-- 確認:
-- SELECT id, name, balance FROM accounts ORDER BY id;
-- -- id=25と28が両方存在することを確認

-- =====================================================
-- 同一idへのINSERT（ユニーク制約違反のケース）
-- =====================================================
-- Session A: BEGIN; INSERT INTO accounts (id,name,balance) VALUES (55,'X',100);
-- Session B: BEGIN; INSERT INTO accounts (id,name,balance) VALUES (55,'Y',200);
-- -- Session BはSession AのCOMMITを待つ（レコードの重複チェックで待機）
-- Session A: COMMIT;
-- -- Session B: ERROR 1062 (23000): Duplicate entry '55' for key 'PRIMARY'
-- Session B: ROLLBACK;

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - INSERT Intention同士の互換性: 互換（ブロックなし）
-- - 同一idへのINSERT: ユニーク制約でエラー（COMMITまで待機）
-- - 備考:
