#!/usr/bin/env bash
# ロック観察用接続スクリプト
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MYSQL_DATA_DIR="$PROJECT_DIR/mysql-data"
MYSQL_SOCKET="$MYSQL_DATA_DIR/mysql.sock"

echo "=== Observer 接続（ロック観察用） ==="
echo "ソケット: $MYSQL_SOCKET"
echo ""
echo "ヒント:"
echo "  source sql/helpers/observe_locks.sql      -- 現在のロック一覧"
echo "  source sql/helpers/observe_lock_waits.sql -- ロック待機状態"
echo "  source sql/helpers/observe_trx.sql        -- アクティブトランザクション"
echo "  source sql/helpers/show_engine_status.sql -- InnoDB内部状態"
echo "  source sql/helpers/reset_data.sql         -- データリセット"
echo ""

mysql \
  --socket="$MYSQL_SOCKET" \
  -u root \
  --prompt="Observer> " \
  performance_schema
