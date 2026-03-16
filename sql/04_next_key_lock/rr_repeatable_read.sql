-- =====================================================
-- Next-Key Lock（ネクストキーロック）- REPEATABLE READ
-- 目的: Next-Key Lock = Record Lock + Gap Lock の組み合わせを確認
--       REPEATABLE READのデフォルトロック方式
-- =====================================================
USE lock_test_db;

-- accounts PK: 10, 20, 30, 40, 50
-- Next-Key Lock の範囲（左開き右閉じの区間）:
--   (-∞, 10] | (10, 20] | (20, 30] | (30, 40] | (40, 50] | (50, +∞)
SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - 範囲検索 FOR UPDATE（Next-Key Lock 発生）
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE id >= 20 FOR UPDATE;
-- -- 結果: id=20, 30, 40, 50 の4行
--
-- 設定されるNext-Key Lock:
--   (10, 20]: X（id=20のNext-Key Lock）
--   (20, 30]: X（id=30のNext-Key Lock）
--   (30, 40]: X（id=40のNext-Key Lock）
--   (40, 50]: X（id=50のNext-Key Lock）
--   (50, +∞): X（supremum pseudo-record のギャップ）
--
-- Note: data_locksでは X と X,GAP の組み合わせで表現される
--   X             = Next-Key Lock（レコード + 前のギャップ）
--   X,REC_NOT_GAP = Record Lock のみ（ギャップなし）
--   X,GAP         = Gap Lock のみ（レコードなし）

-- =====================================================
-- Step 2: Observer - Next-Key Lock 確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   LOCK_MODE | LOCK_DATA
--   IX        | NULL            (テーブル)
--   X         | 20              (Next-Key Lock: (10,20])
--   X         | 30              (Next-Key Lock: (20,30])
--   X         | 40              (Next-Key Lock: (30,40])
--   X         | 50              (Next-Key Lock: (40,50])
--   X         | supremum pseudo-record  (Gap: (50,+∞))
--
-- LOCK_MODE = 'X'（REC_NOT_GAPなし）= Next-Key Lock（Gap + Record）

-- =====================================================
-- Step 3: Session B - 各種操作でブロック確認
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- -- id=15 へのINSERT（ギャップ (10,20] 内）→ ブロック
-- INSERT INTO accounts (id, name, balance) VALUES (15, 'New1', 100.00);
-- -- ← ブロック
--
-- -- id=5 へのINSERT（ギャップ (-∞,10) 内）→ ブロックされない
-- INSERT INTO accounts (id, name, balance) VALUES (5, 'New2', 200.00);
-- -- ← 即時完了（ロック範囲外）
--
-- -- id=60 へのINSERT（supremumギャップ内）→ ブロック
-- INSERT INTO accounts (id, name, balance) VALUES (60, 'New3', 300.00);
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
-- - LOCK_MODE = 'X'（REC_NOT_GAPなし）: Next-Key Lock
-- - supremum pseudo-record: 最大値より大きいギャップ
-- - ロック範囲内INSERT: ブロックあり
-- - ロック範囲外INSERT: ブロックなし
-- - 備考:
