-- =====================================================
-- レコードロック - PKロック vs セカンダリインデックスロック比較
-- 目的: セカンダリインデックスで検索すると2段階のロックが発生することを確認
--       セカンダリ + PKの両方にロックが設定される
-- =====================================================
USE lock_test_db;

-- 事前確認
SELECT id, name, balance FROM accounts ORDER BY id;
-- balance index: 500.00(id=40), 1000.00(id=10), 2000.00(id=20), 3000.00(id=30), 4000.00(id=50)

-- =====================================================
-- Case 1: PKによる検索（ロックは1つ）
-- =====================================================

-- Step 1a: Session A - PKで検索
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE id = 30 FOR UPDATE;

-- Step 2a: Observer - PKロック確認
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   OBJECT_NAME | INDEX_NAME | LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   accounts    | NULL       | TABLE     | IX            | NULL
--   accounts    | PRIMARY    | RECORD    | X,REC NOT GAP | 30
--
-- PKのみ → ロックは2エントリ（テーブルIX + 行X）

-- Step 3a: Session A ROLLBACK
-- ROLLBACK;

-- =====================================================
-- Case 2: セカンダリインデックスによる検索（ロックは2つ）
-- =====================================================

-- Step 1b: Session A - セカンダリインデックスで検索
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- BEGIN;
-- SELECT * FROM accounts WHERE balance = 3000.00 FOR UPDATE;
-- -- balance=3000.00 はid=30

-- Step 2b: Observer - セカンダリ + PKロック確認
-- source sql/helpers/observe_locks.sql
--
-- 期待される出力:
--   OBJECT_NAME | INDEX_NAME  | LOCK_TYPE | LOCK_MODE     | LOCK_DATA
--   accounts    | NULL        | TABLE     | IX            | NULL
--   accounts    | idx_balance | RECORD    | X             | 3000.00, 30  ← セカンダリにNext-Key Lock
--   accounts    | PRIMARY     | RECORD    | X,REC_NOT_GAP | 30           ← PKにRecord Lock
--
-- セカンダリインデックス使用 → ロックが2段階発生
--   1. セカンダリインデックス idx_balance にX（Next-Key Lock）
--   2. 対応するPKにX,REC_NOT_GAP（Record Lock）
--
-- なぜPKにもロックが必要か:
--   セカンダリインデックスを経由してPKを特定し、
--   他のセッションがPKを直接更新するのを防ぐため

-- Step 3b: Session A ROLLBACK
-- ROLLBACK;

-- =====================================================
-- クリーンアップ
-- =====================================================
-- Observer: source sql/helpers/reset_data.sql

-- =====================================================
-- 調査結果メモ
-- =====================================================
-- 実測後にここに記入:
-- - PKのみ: ロック数 = 2（TABLE:IX + RECORD:X,REC_NOT_GAP）
-- - セカンダリ: ロック数 = 3（TABLE:IX + セカンダリ:X + PRIMARY:X,REC_NOT_GAP）
-- - セカンダリのLOCK_DATA形式: "balance値, id値"
-- - 備考:
