-- =====================================================
-- performance_schema instruments 有効化
-- ロック情報を取得するために必要
-- =====================================================
USE performance_schema;

-- InnoDB行ロックのinstruments有効化
UPDATE setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/lock/innodb/%';

-- テーブルロックのinstruments有効化
UPDATE setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/lock/table/%';

-- data_locks / data_lock_waits consumers有効化
UPDATE setup_consumers
SET ENABLED = 'YES'
WHERE NAME IN (
  'events_waits_current',
  'events_waits_history',
  'events_waits_history_long'
);

-- 設定確認
SELECT NAME, ENABLED, TIMED
FROM setup_instruments
WHERE NAME LIKE 'wait/lock/%'
ORDER BY NAME;

SELECT NAME, ENABLED
FROM setup_consumers
WHERE NAME LIKE 'events_waits%'
ORDER BY NAME;

SELECT 'performance_schema instruments を有効化しました' AS message;
