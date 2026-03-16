#!/usr/bin/env bash
# 空テーブル・対象不在のロック挙動実測スクリプト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SOCK="$PROJECT_DIR/mysql-data/mysql.sock"
MYSQL="$PROJECT_DIR/.devbox/nix/profile/default/bin/mysql"
MYSQL_CMD="$MYSQL --socket=$SOCK -u root lock_test_db"

OBSERVE_SQL="SELECT CONCAT(l.LOCK_TYPE,'|',l.LOCK_MODE,'|',IFNULL(l.LOCK_DATA,'NULL'))
FROM performance_schema.data_locks l
JOIN information_schema.INNODB_TRX t ON l.ENGINE_TRANSACTION_ID = t.TRX_ID
ORDER BY l.LOCK_TYPE DESC, l.LOCK_DATA;"

run_scenario() {
  local desc="$1"
  local iso="$2"
  local sql="$3"

  echo ""
  echo "### $desc ($iso)"

  # Session A: BEGIN + ロック取得してスリープ（バックグラウンド）
  $MYSQL_CMD -N -s <<SQL &
SET SESSION TRANSACTION ISOLATION LEVEL $iso;
BEGIN;
$sql
SELECT SLEEP(5);
ROLLBACK;
SQL
  local bg_pid=$!

  # ロック取得待機
  sleep 0.8

  # Observer: data_locks を観測
  local result
  result=$($MYSQL_CMD -N -s -e "$OBSERVE_SQL" 2>/dev/null)

  if [ -z "$result" ]; then
    echo "  （ROW ロックなし — テーブル TABLE IX のみ）"
  else
    echo "$result" | while IFS='|' read -r lock_type lock_mode lock_data; do
      printf "  LOCK_TYPE=%-8s LOCK_MODE=%-22s LOCK_DATA=%s\n" "$lock_type" "$lock_mode" "$lock_data"
    done
  fi

  wait $bg_pid 2>/dev/null || true
}

echo "================================================================"
echo " 実測: 空テーブル・対象不在のロック挙動"
echo " MySQL: $($MYSQL_CMD -N -s -e 'SELECT VERSION();' 2>/dev/null)"
echo " 日時: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"

# ==============================
# シナリオ1: テーブルを空にして実測
# ==============================
echo ""
echo "=============================="
echo "シナリオ1: テーブル空"
echo "=============================="
$MYSQL_CMD -e "DELETE FROM products;" 2>/dev/null
echo "（テーブルを DELETE で空にした）"

echo ""
echo "--- 1-1: 範囲 FOR UPDATE (WHERE id > 20 AND id < 40) ---"
for iso in "READ UNCOMMITTED" "READ COMMITTED" "REPEATABLE READ" "SERIALIZABLE"; do
  run_scenario "テーブル空 + 範囲 FOR UPDATE" "$iso" \
    "SELECT * FROM products WHERE id > 20 AND id < 40 FOR UPDATE;"
done

echo ""
echo "--- 1-2: PK ポイント FOR UPDATE (WHERE id = 30) ---"
for iso in "READ UNCOMMITTED" "READ COMMITTED" "REPEATABLE READ" "SERIALIZABLE"; do
  run_scenario "テーブル空 + PK FOR UPDATE" "$iso" \
    "SELECT * FROM products WHERE id = 30 FOR UPDATE;"
done

echo ""
echo "--- 1-3: 通常 SELECT 範囲（SERIALIZABLE 比較） ---"
for iso in "REPEATABLE READ" "SERIALIZABLE"; do
  run_scenario "テーブル空 + 通常 SELECT 範囲" "$iso" \
    "SELECT * FROM products WHERE id > 20 AND id < 40;"
done

# ==============================
# シナリオ2: データ復元して「不在PK」実測
# ==============================
echo ""
echo "=============================="
echo "シナリオ2: データあり・不在PK"
echo "=============================="
$MYSQL_CMD -e "
INSERT INTO products (id,name,category_id,price,stock) VALUES
(10,'A',10,100.00,10),(20,'B',10,200.00,20),(30,'C',20,300.00,30),
(40,'D',30,400.00,40),(50,'E',30,500.00,50);" 2>/dev/null
echo "（id: 10, 20, 30, 40, 50 を INSERT）"

echo ""
echo "--- 2-1: 不在PK=25（20と30の間）FOR UPDATE ---"
for iso in "READ UNCOMMITTED" "READ COMMITTED" "REPEATABLE READ" "SERIALIZABLE"; do
  run_scenario "不在PK=25 (20<x<30) FOR UPDATE" "$iso" \
    "SELECT * FROM products WHERE id = 25 FOR UPDATE;"
done

echo ""
echo "--- 2-2: 不在PK=99（最大値50超）FOR UPDATE ---"
for iso in "READ UNCOMMITTED" "READ COMMITTED" "REPEATABLE READ" "SERIALIZABLE"; do
  run_scenario "不在PK=99 (50<x) FOR UPDATE" "$iso" \
    "SELECT * FROM products WHERE id = 99 FOR UPDATE;"
done

echo ""
echo "--- 2-3: 不在PK=5（最小値10未満）FOR UPDATE ---"
for iso in "READ UNCOMMITTED" "READ COMMITTED" "REPEATABLE READ" "SERIALIZABLE"; do
  run_scenario "不在PK=5 (x<10) FOR UPDATE" "$iso" \
    "SELECT * FROM products WHERE id = 5 FOR UPDATE;"
done

echo ""
echo "--- 2-4: 不在PK=25 FOR SHARE ---"
for iso in "READ UNCOMMITTED" "READ COMMITTED" "REPEATABLE READ" "SERIALIZABLE"; do
  run_scenario "不在PK=25 FOR SHARE" "$iso" \
    "SELECT * FROM products WHERE id = 25 FOR SHARE;"
done

echo ""
echo "================================================================"
echo " 実測完了"
echo "================================================================"
