#!/usr/bin/env bash
# Session B 接続スクリプト
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MYSQL_DATA_DIR="$PROJECT_DIR/mysql-data"
MYSQL_SOCKET="$MYSQL_DATA_DIR/mysql.sock"

echo "=== Session B 接続 ==="
echo "ソケット: $MYSQL_SOCKET"
echo ""

mysql \
  --socket="$MYSQL_SOCKET" \
  -u root \
  --prompt="SessionB> " \
  lock_test_db
