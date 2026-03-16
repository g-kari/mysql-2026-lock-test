#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MYSQL_DATA_DIR="$PROJECT_DIR/mysql-data"
MYSQL_PID_FILE="$MYSQL_DATA_DIR/mysql.pid"
MYSQL_SOCKET="$MYSQL_DATA_DIR/mysql.sock"

echo "=== MySQL 停止処理 ==="

if [ -f "$MYSQL_PID_FILE" ]; then
  PID=$(cat "$MYSQL_PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "MySQL停止中 (PID: $PID)..."
    mysqladmin shutdown --socket="$MYSQL_SOCKET" -u root 2>/dev/null || kill "$PID"
    sleep 2
    echo "MySQL停止完了"
  else
    echo "MySQLはすでに停止しています"
    rm -f "$MYSQL_PID_FILE"
  fi
else
  echo "PIDファイルが見つかりません: $MYSQL_PID_FILE"
  echo "mysqladmin でシャットダウンを試みます..."
  mysqladmin shutdown --socket="$MYSQL_SOCKET" -u root 2>/dev/null || true
fi

echo ""
read -p "データディレクトリを削除しますか？ (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -rf "$MYSQL_DATA_DIR"
  echo "データディレクトリを削除しました: $MYSQL_DATA_DIR"
else
  echo "データディレクトリは保持します: $MYSQL_DATA_DIR"
fi

echo "=== クリーンアップ完了 ==="
