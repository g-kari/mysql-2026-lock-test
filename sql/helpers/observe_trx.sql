-- =====================================================
-- アクティブトランザクション確認
-- information_schema.INNODB_TRX を使用
-- Observer ターミナルで実行
-- =====================================================
USE information_schema;

SELECT
  t.trx_id,
  t.trx_state,
  t.trx_started,
  t.trx_wait_started,
  t.trx_mysql_thread_id,
  t.trx_query,
  t.trx_operation_state,
  t.trx_tables_in_use,
  t.trx_tables_locked,
  t.trx_lock_structs,
  t.trx_rows_locked,
  t.trx_rows_modified,
  t.trx_isolation_level
FROM information_schema.INNODB_TRX t
ORDER BY t.trx_started;
