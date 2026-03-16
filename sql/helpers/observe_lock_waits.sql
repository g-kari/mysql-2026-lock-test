-- =====================================================
-- ロック待機状態確認
-- performance_schema.data_lock_waits を使用
-- Observer ターミナルで実行
-- =====================================================
USE performance_schema;

SELECT
  w.ENGINE,
  w.REQUESTING_ENGINE_TRANSACTION_ID AS WAIT_TRX_ID,
  w.BLOCKING_ENGINE_TRANSACTION_ID   AS BLOCK_TRX_ID,
  -- 待機しているロックの詳細
  req.OBJECT_NAME  AS WAIT_TABLE,
  req.INDEX_NAME   AS WAIT_INDEX,
  req.LOCK_TYPE    AS WAIT_LOCK_TYPE,
  req.LOCK_MODE    AS WAIT_LOCK_MODE,
  req.LOCK_DATA    AS WAIT_LOCK_DATA,
  -- ブロックしているロックの詳細
  blk.OBJECT_NAME  AS BLOCK_TABLE,
  blk.INDEX_NAME   AS BLOCK_INDEX,
  blk.LOCK_TYPE    AS BLOCK_LOCK_TYPE,
  blk.LOCK_MODE    AS BLOCK_LOCK_MODE,
  blk.LOCK_DATA    AS BLOCK_LOCK_DATA
FROM performance_schema.data_lock_waits w
JOIN performance_schema.data_locks req
  ON w.REQUESTING_ENGINE_LOCK_ID = req.ENGINE_LOCK_ID
JOIN performance_schema.data_locks blk
  ON w.BLOCKING_ENGINE_LOCK_ID = blk.ENGINE_LOCK_ID;
