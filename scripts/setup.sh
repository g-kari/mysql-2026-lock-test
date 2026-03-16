#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MYSQL_DATA_DIR="$PROJECT_DIR/mysql-data"
MYSQL_PORT=13306
MYSQL_SOCKET="$MYSQL_DATA_DIR/mysql.sock"
MYSQL_PID_FILE="$MYSQL_DATA_DIR/mysql.pid"
MYSQL_LOG="$MYSQL_DATA_DIR/mysql-error.log"

echo "=== MySQL 8.4 LTS セットアップ開始 ==="

# データディレクトリ作成・初期化
# mysql.ibd の存在でDBが初期化済みかを判定（ログファイルのみの場合は未初期化）
mkdir -p "$MYSQL_DATA_DIR"
if [ ! -f "$MYSQL_DATA_DIR/mysql.ibd" ]; then
  echo "MySQLデータディレクトリを初期化中..."
  # --initialize はディレクトリにファイルがあると失敗するため、ログファイルを事前に除去
  rm -f "$MYSQL_DATA_DIR"/*.log "$MYSQL_DATA_DIR"/*.err
  mysqld --initialize-insecure \
    --datadir="$MYSQL_DATA_DIR" \
    --user="$(whoami)" \
    --log-error="$MYSQL_LOG" \
    2>&1
  echo "初期化完了"
else
  echo "既存のデータディレクトリを使用: $MYSQL_DATA_DIR"
fi

# MySQL起動
if [ -f "$MYSQL_PID_FILE" ] && kill -0 "$(cat "$MYSQL_PID_FILE")" 2>/dev/null; then
  echo "MySQLはすでに起動しています (PID: $(cat "$MYSQL_PID_FILE"))"
else
  echo "MySQL起動中 (ポート: $MYSQL_PORT)..."
  mysqld \
    --datadir="$MYSQL_DATA_DIR" \
    --socket="$MYSQL_SOCKET" \
    --port="$MYSQL_PORT" \
    --pid-file="$MYSQL_PID_FILE" \
    --log-error="$MYSQL_LOG" \
    --innodb-autoinc-lock-mode=1 \
    --general-log=ON \
    --general-log-file="$MYSQL_DATA_DIR/general.log" \
    --performance-schema=ON \
    --daemonize

  # 起動待機
  echo -n "起動待機中"
  for i in $(seq 1 30); do
    if mysqladmin ping --socket="$MYSQL_SOCKET" --silent 2>/dev/null; then
      echo " 完了"
      break
    fi
    echo -n "."
    sleep 1
  done
fi

echo ""
echo "=== MySQL 起動完了 ==="
echo "ポート: $MYSQL_PORT"
echo "ソケット: $MYSQL_SOCKET"
echo "ログ: $MYSQL_LOG"
echo ""
echo "次のステップ:"
echo "  1. mysql --socket=$MYSQL_SOCKET -u root < sql/00_setup/01_create_database.sql"
echo "  2. mysql --socket=$MYSQL_SOCKET -u root < sql/00_setup/02_create_tables.sql"
echo "  3. mysql --socket=$MYSQL_SOCKET -u root < sql/00_setup/03_insert_data.sql"
echo "  4. mysql --socket=$MYSQL_SOCKET -u root < sql/00_setup/04_enable_instruments.sql"
echo "  5. ./scripts/connect-a.sh でSession Aを接続"
