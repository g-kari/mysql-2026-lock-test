-- =====================================================
-- AUTO-INC Lock - mode=2 (interleaved) の動作確認
-- 目的: mode=2での並行INSERT確認と連番のギャップ・インターリーブを観察
--       バイナリログとの関係を理解する
-- =====================================================
USE lock_test_db;

SHOW VARIABLES LIKE 'innodb_autoinc_lock_mode';
SHOW VARIABLES LIKE 'binlog_format';

SELECT id, account_id, amount FROM orders ORDER BY id;

-- =====================================================
-- mode=2 の特徴
-- =====================================================
-- - 全てのINSERT（シンプル・バルク問わず）で軽量ロック（mutex）
-- - AUTO-INCテーブルロックは一切発生しない
-- - 最高の並行INSERT性能
-- - ただし:
--   a) 異なるINSERT文の連番がインターリーブする可能性
--   b) ロールバック時に連番がスキップされる
--   c) バイナリログは ROW 形式が必要
--      （STATEMENT形式では複製が不正確になる）
--
-- MySQL 8.4 デフォルトは mode=1
-- バイナリログが ROW 形式の環境では mode=2 を検討

-- =====================================================
-- シナリオ: mode=2 での並行INSERT（インターリーブの確認）
-- =====================================================
-- Note: mode=2 をテストするにはMySQL起動時のオプション変更が必要
-- 通常は setup.sh に --innodb-autoinc-lock-mode=2 を追加して再起動

-- Step 1: セッション確認
-- SHOW VARIABLES LIKE 'innodb_autoinc_lock_mode';
-- -- 2 であることを確認

-- Step 2: Session A - 大量INSERT開始（遅いクエリをシミュレート）
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status)
--   SELECT account_id, amount, 'pending'
--   FROM orders;  -- バルクINSERT

-- Step 3: Session B - 並行してシンプルINSERT
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status) VALUES (99, 1.00, 'test');
-- -- mode=2 なら即時完了（AUTO-INCテーブルロックなし）

-- Step 4: Observer - AUTO-INCテーブルロックが表示されないことを確認
-- source sql/helpers/observe_locks.sql
-- -- LOCK_MODE = 'AUTO_INC' が表示されないことを確認

-- Step 5: 両セッションCOMMIT後の連番確認
-- SELECT id, account_id, amount FROM orders ORDER BY id;
-- -- Session BのINSERTがSession Aのバルクの間に挿入された連番を持つ可能性
-- -- 例: 1,2,3,...,N, [B's id], N+1, N+2,...

-- =====================================================
-- バイナリログ形式との関係
-- =====================================================
-- SHOW VARIABLES LIKE 'binlog_format';
-- -- ROW が推奨（STATEMENT だと複製に問題）

-- =====================================================
-- AUTO_INCREMENTのギャップについて
-- =====================================================
-- トランザクションのロールバックでも AUTO_INCREMENT は巻き戻らない
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status) VALUES (99, 9.99, 'test');
-- SELECT LAST_INSERT_ID();  -- 新しいid
-- ROLLBACK;
-- -- 次のINSERTは LAST_INSERT_ID()+1 からではなく、その次の値から始まる
-- -- → 連番に「ギャップ」が生じる（これは正常動作）
--
-- BEGIN;
-- INSERT INTO orders (account_id, amount, status) VALUES (99, 1.00, 'real');
-- -- id はロールバックされた id+1 になる（ギャップあり）
-- COMMIT;

-- =====================================================
-- クリーンアップ
-- =====================================================
-- 両セッション: COMMIT;
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - 現在のmode:
-- - AUTO_INCテーブルロック表示: あり/なし
-- - 連番のインターリーブ: 確認できたか
-- - ロールバック後の連番ギャップ: 確認できたか
-- - 備考:
