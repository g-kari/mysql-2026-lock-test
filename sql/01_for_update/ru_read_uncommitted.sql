-- =====================================================
-- FOR UPDATE（排他行ロック）- READ UNCOMMITTED
-- 目的: READ UNCOMMITTEDでもFOR UPDATEは排他ロックを取得することを確認
--       ダーティリードが可能でも書き込みロックは発生する
-- =====================================================
USE lock_test_db;

SELECT id, name, balance FROM accounts ORDER BY id;

-- =====================================================
-- Step 1: Session A - READ UNCOMMITTED で FOR UPDATE
-- 別ターミナル(Session A)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
--
-- READ UNCOMMITTEDの特徴:
--   読み取り: ダーティリード可能（他トランザクションの未コミットデータが見える）
--   書き込みロック: FOR UPDATEは排他ロックを取得する（変わらず）

-- =====================================================
-- Step 2: Observer - ロック状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力（他の分離レベルと同じ）:
--   LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   TABLE     | IX            | NULL
--   RECORD    | X,REC_NOT_GAP | 30
--
-- READ UNCOMMITTEDでもFOR UPDATEは X,REC_NOT_GAP を取得する

-- =====================================================
-- Step 3: Session B - ダーティリードの確認
-- 別ターミナル(Session B)で実行
-- =====================================================
-- SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- BEGIN;
-- -- まず Session A で balance を変更（まだCOMMITしない）
-- -- Session A: UPDATE accounts SET balance = 9999.00 WHERE id = 30;
--
-- -- Session B からダーティリードで未コミット値が見える
-- SELECT * FROM accounts WHERE id = 30;
-- -- READ UNCOMMITTEDなら balance=9999.00 が見える（未コミット）
-- -- 他の分離レベルなら balance=3000.00 が見える（コミット済みの値）
--
-- FOR UPDATE でブロックされることも確認:
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;
-- -- ← ブロック（ダーティリード可能でも排他ロック競合は起きる）

-- =====================================================
-- Step 4: Observer - 待機状態確認
-- 別ターミナル(Observer)で実行
-- =====================================================
-- source sql/helpers/observe_lock_waits.sql

-- =====================================================
-- Step 5: Session A - コミットまたはロールバック
-- 別ターミナル(Session A)で実行
-- =====================================================
-- ROLLBACK;
-- -- Session A がロールバックすると Session B のダーティリードが「幻」になる
-- -- これがダーティリードの危険性

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Session B: ROLLBACK;
-- Observer:  source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - LOCK_MODE: X,REC_NOT_GAP（他の分離レベルと同じ）
-- - ダーティリード: 確認できたか
-- - ブロック(同一行 FOR UPDATE): あり
-- - 備考: READ UNCOMMITTEDは読み取りの分離性が最も低いが、書き込みロックは発生する
