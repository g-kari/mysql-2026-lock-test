-- =====================================================
-- 現在のInnoDB行ロック確認
-- performance_schema.data_locks を使用
-- Observer ターミナルで実行
-- =====================================================
USE performance_schema;

SELECT
  r.ENGINE_LOCK_ID,
  r.ENGINE_TRANSACTION_ID AS TRX_ID,
  r.THREAD_ID,
  r.OBJECT_SCHEMA,
  r.OBJECT_NAME,
  r.INDEX_NAME,
  r.LOCK_TYPE,
  r.LOCK_MODE,
  r.LOCK_STATUS,
  r.LOCK_DATA
FROM performance_schema.data_locks r
ORDER BY r.ENGINE_TRANSACTION_ID, r.LOCK_TYPE DESC, r.LOCK_MODE;
