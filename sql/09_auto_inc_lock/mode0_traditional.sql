-- =====================================================
-- AUTO-INC Lock - lock_mode 確認と動作検証
-- 目的: AUTO_INCREMENT ロックの挙動を確認
--       innodb_autoinc_lock_mode の値による違いを理解する
-- =====================================================
USE lock_test_db;

-- AUTO-INC ロックモードの確認
SHOW VARIABLES LIKE 'innodb_autoinc_lock_mode';
-- 返り値:
--   0 = traditional : 全INSERTでテーブルレベルのAUTO-INCロック
--   1 = consecutive : シンプルINSERTは軽量ロック（MySQL 8.4デフォルト）
--   2 = interleaved : 全て軽量ロック（最速、ROWバイナリログ必須）

SELECT id, account_id, amount, status FROM orders ORDER BY id;

-- =====================================================
-- AUTO-INC ロックモードの説明
-- =====================================================
-- mode=0 (traditional):
--   - INSERT ステートメントの間、テーブル全体に AUTO-INC ロック（テーブルレベル）
--   - 他のセッションの INSERT は完全にブロック
--   - 連番の保証: ステートメント内では必ず連番
--   - バイナリログの安全性: statement-based でも安全
--
-- mode=1 (consecutive) - MySQL 8.4 デフォルト:
--   - シンプルINSERT（行数が判明）: 軽量ロック（mutex）で連番割り当て
--   - バルクINSERT（行数不明 = INSERT...SELECT等）: テーブルレベルAUTO-INCロック
--   - シンプルINSERTは並行実行可能
--
-- mode=2 (interleaved):
--   - 全INSERTで軽量ロック（mutex）
--   - 最高の並行性
--   - ただし異なるINSERT間で連番がインターリーブされる可能性
--   - バイナリログはROW形式が必要（statement-based では危険）

-- =====================================================
-- Step 1: Session A - AUTO_INCREMENTのロック観察
-- 別ターミナル(Session A)で実行
-- =====================================================
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status) VALUES (10, 999.00, 'pending');
-- -- まだCOMMITしない

-- =====================================================
-- Step 2: Observer - AUTO-INC ロック確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
-- -- mode=0 の場合:
-- --   LOCK_TYPE = TABLE, LOCK_MODE = 'AUTO_INC' が表示される
-- --
-- -- mode=1 の場合（シンプルINSERT）:
-- --   AUTO-INC テーブルロックは表示されない（軽量mutexのため）
-- --   → data_locks には通常の行ロックのみ
-- --
-- -- mode=2 の場合:
-- --   AUTO-INC テーブルロックは表示されない

-- =====================================================
-- Step 3: Session B - 並行 INSERT 試行
-- 別ターミナル(Session B)で実行
-- =====================================================
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status) VALUES (20, 888.00, 'pending');
-- -- mode=0: ブロック（AUTO-INCテーブルロック中）
-- -- mode=1: 即時完了（シンプルINSERTは軽量ロック）
-- -- mode=2: 即時完了

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
-- -- mode=0 の場合: Session B がブロック解除

-- =====================================================
-- AUTO_INCREMENTの連番確認
-- =====================================================
-- 両セッションCOMMIT後:
-- SELECT id, account_id, amount FROM orders ORDER BY id;
-- -- 連番が振られていることを確認

-- =====================================================
-- クリーンアップ
-- =====================================================
-- 両セッション: COMMIT;
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - 現在のinnodb_autoinc_lock_mode:
-- - mode=1でのAUTO_INCテーブルロック: data_locksに表示されるか
-- - 並行INSERTのブロック: あり/なし
-- - 備考:
