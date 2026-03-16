-- =====================================================
-- Gap Lock（ギャップロック）- REPEATABLE READ ★最重要
-- 目的: REPEATABLE READでギャップロックが発生することを確認
--       ギャップ内へのINSERTがブロックされることを実証
-- =====================================================
USE lock_test_db;

-- accounts PK: 10, 20, 30, 40, 50
-- ギャップ:
--   (-∞, 10) | 10 | (10, 20) | 20 | (20, 30) | 30 | (30, 40) | 40 | (40, 50) | 50 | (50, +∞)
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - 範囲検索 FOR UPDATE（ギャップロック発生）
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE id > 20 AND id < 40 FOR UPDATE;
-- -- 結果: id=30 の1行
--
-- このクエリで設定されるロック:
--   TABLE:  IX
--   RECORD: X,REC_NOT_GAP on id=30    ← レコードロック
--   RECORD: X,GAP on id=30 (gap before 30 = (20,30)) ← ギャップロック
--   RECORD: X,GAP on id=40 (gap before 40 = (30,40)) ← ギャップロック
--
-- Note: MySQL 8.4では GAP Lock は LOCK_MODE = 'X,GAP' と表示される

-- =====================================================
-- Step 2: Observer - ギャップロック確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   INDEX_NAME | LOCK_MODE     | LOCK_DATA
--   NULL       | IX            | NULL         (テーブルIX)
--   PRIMARY    | X,REC_NOT_GAP | 30           (レコードロック)
--   PRIMARY    | X,GAP         | 30           (ギャップ (20,30))
--   PRIMARY    | X,GAP         | 40           (ギャップ (30,40))
--
-- X,GAP = ギャップロック（レコード自体はロックしない、間のみ）

-- =====================================================
-- Step 3: Session B - ギャップ内へのINSERT（ブロックされる）
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- -- ギャップ(20,30)内へのINSERT → ブロック
-- INSERT INTO accounts (id, name, balance) VALUES (25, 'New1', 100.00);
-- -- ← ブロック！ INSERT Intention LockがGap Lockと競合
--
-- -- ギャップ(30,40)内へのINSERT → ブロック
-- -- INSERT INTO accounts (id, name, balance) VALUES (35, 'New2', 200.00);
-- -- ← ブロック！
--
-- -- ギャップ(10,20)内へのINSERT → ブロックされない
-- -- INSERT INTO accounts (id, name, balance) VALUES (15, 'New3', 300.00);
-- -- ← 即時完了（ロックされていないギャップ）

-- =====================================================
-- Step 4: Observer - 待機状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_lock_waits.sql
--
-- WAIT_LOCK_MODE に 'INSERT_INTENTION' が含まれる

-- =====================================================
-- Step 5: Session A - コミット（Session Bのブロック解除）
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
-- - LOCK_MODE一覧: X,REC_NOT_GAP（レコード） + X,GAP（ギャップ）
-- - ギャップ内INSERT: ブロックあり
-- - ギャップ外INSERT: ブロックなし
-- - LOCK_DATAの意味: ギャップの上限レコードのPK値
-- - 備考: READ COMMITTEDとの最大の違い（03_gap_lock/rc_read_committed.sql と比較）
