-- =====================================================
-- Next-Key Lock - READ COMMITTED（Gap部分なし）
-- 目的: READ COMMITTEDではNext-Key LockのGap部分が発生しないことを確認
--       Record部分のみ（X,REC_NOT_GAP）
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - READ COMMITTED で範囲 FOR UPDATE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- BEGIN;
-- SELECT * FROM accounts WHERE id >= 20 FOR UPDATE;
-- -- 結果: id=20, 30, 40, 50 の4行
--
-- READ COMMITTEDでは:
--   各レコードに X,REC_NOT_GAP のみ
--   Gap部分（X,GAP）は設定されない

-- =====================================================
-- Step 2: Observer - ロック確認（Gapなし）
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   LOCK_MODE     | LOCK_DATA
--   IX            | NULL
--   X,REC_NOT_GAP | 20
--   X,REC_NOT_GAP | 30
--   X,REC_NOT_GAP | 40
--   X,REC_NOT_GAP | 50
--
-- REPEATABLE READとの比較:
--   REPEATABLE READ: LOCK_MODE = 'X'（Next-Key = Gap+Record）
--   READ COMMITTED:  LOCK_MODE = 'X,REC_NOT_GAP'（Record のみ）

-- =====================================================
-- Step 3: Session B - ギャップ内INSERTは即時完了
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- -- ギャップ(10,20)内へのINSERT → 即時完了（ギャップロックなし）
-- INSERT INTO accounts (id, name, balance) VALUES (15, 'New1', 100.00);
-- -- ← 即時完了！
--
-- -- ギャップ(50,+∞)内へのINSERT → 即時完了
-- INSERT INTO accounts (id, name, balance) VALUES (60, 'New2', 200.00);
-- -- ← 即時完了！
--
-- -- 既存レコード(id=30)の更新 → ブロック（Record Lockあり）
-- UPDATE accounts SET balance = 9999.00 WHERE id = 30;
-- -- ← ブロック

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
-- Session B: ROLLBACK;
-- Observer:  source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - LOCK_MODE: X,REC_NOT_GAP のみ（X,GAPなし）
-- - ギャップ内INSERT: ブロックなし
-- - 既存レコード更新: ブロックあり
-- - 備考: READ COMMITTEDはGap Lockを取得しない = Next-Key LockのRecord部分のみ
