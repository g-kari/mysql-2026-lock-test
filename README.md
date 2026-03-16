# MySQL 8.4 LTS ロック挙動調査

MySQL 8.4 LTS の各トランザクション分離レベルにおけるロック挙動を包括的に調査したプロジェクトです。
ブログ記事「0g0-blog」の素材として、実際の動作結果をもとにまとめています。

## 環境

| 項目 | 内容 |
|------|------|
| MySQL | 8.4.x LTS |
| 環境構築 | devbox |
| データディレクトリ | `./mysql-data` |
| ポート | 13306（標準ポート衝突回避） |

## セットアップ

### 1. devbox shell に入る

```bash
devbox shell
```

### 2. MySQL 初期化・起動

```bash
./scripts/setup.sh
```

### 3. データベース・テーブル作成

```bash
mysql --socket=./mysql-data/mysql.sock -u root < sql/00_setup/01_create_database.sql
mysql --socket=./mysql-data/mysql.sock -u root < sql/00_setup/02_create_tables.sql
mysql --socket=./mysql-data/mysql.sock -u root < sql/00_setup/03_insert_data.sql
mysql --socket=./mysql-data/mysql.sock -u root < sql/00_setup/04_enable_instruments.sql
```

### 4. 3つのターミナルを開く

| ターミナル | 役割 | 起動コマンド |
|-----------|------|------------|
| Terminal 1 | Session A（操作） | `./scripts/connect-a.sh` |
| Terminal 2 | Session B（競合） | `./scripts/connect-b.sh` |
| Terminal 3 | Observer（観察） | `./scripts/observe-locks.sh` |

## テストテーブル設計

### accounts（行ロック・ギャップロック検証用）

```
id: 10, 20, 30, 40, 50（意図的なギャップあり）
ギャップ: (-∞,10) | 10 | (10,20) | 20 | (20,30) | 30 | (30,40) | 40 | (40,50) | 50 | (50,+∞)
```

### orders（AUTO-INCロック検証用）

```
AUTO_INCREMENT PK, account_idにセカンダリインデックス
```

### products（セカンダリインデックスNext-Keyロック検証用）

```
category_id: 10, 10, 20, 30, 30（重複あり）
```

## 推奨実行順序

複雑さの低い順に実行することで、段階的に理解を深められます:

```
1. sql/05_record_lock/     — 最もシンプル、ベースライン
2. sql/01_for_update/      — レコードロックの応用
3. sql/02_for_share/       — 共有 vs 排他の比較
4. sql/06_intention_lock/  — テーブルレベルの理解
5. sql/03_gap_lock/        — ★重要: READ COMMITTED vs REPEATABLE READの違い
6. sql/04_next_key_lock/   — ギャップロックの発展
7. sql/08_insert_intention_lock/ — ギャップロックとの関連
8. sql/09_auto_inc_lock/   — INSERT特有のロック
9. sql/07_advisory_lock/   — 独立した仕組み
10. sql/10_deadlock/       — 総合シナリオ
```

## ロック種類別サマリマトリクス

> 実測環境: MySQL 8.0.45 / innodb_autoinc_lock_mode=1 / 詳細は `results/lock_observations.md` 参照

### FOR UPDATE（排他行ロック）

| 分離レベル | LOCK_MODE（PK検索） | ギャップロック発生 | ブロック(同一行 FOR UPDATE) | ブロック(ギャップ内INSERT) |
|-----------|-------------------|-----------------|---------------------------|--------------------------|
| READ UNCOMMITTED | X,REC_NOT_GAP（推定） | なし（推定） | あり | なし（推定） |
| READ COMMITTED | **X,REC_NOT_GAP** ✓実測 | **なし** ✓実測 | あり | **なし** ✓実測 |
| REPEATABLE READ | **X,REC_NOT_GAP** ✓実測 | **あり (X,GAP)** ✓実測 | あり | **あり** ✓実測 |
| SERIALIZABLE | X,REC_NOT_GAP（推定） | あり（推定） | あり | あり（推定） |

### FOR SHARE（共有行ロック）

| 分離レベル | LOCK_MODE | テーブルロック | 同一行 FOR SHARE | 同一行 FOR UPDATE |
|-----------|-----------|------------|----------------|-----------------|
| READ UNCOMMITTED | S,REC_NOT_GAP（推定） | IS | 互換（OK） | あり |
| READ COMMITTED | **S,REC_NOT_GAP** ✓実測 | **IS** ✓実測 | 互換（OK） | あり |
| REPEATABLE READ | **S,REC_NOT_GAP** ✓実測 | **IS** ✓実測 | 互換（OK） | あり |
| SERIALIZABLE | **S,REC_NOT_GAP** ✓実測 | **IS** ✓実測 | 互換（OK） | あり |

### Gap Lock（ギャップロック）

| 分離レベル | Gap Lock発生 | LOCK_MODE | Gap内INSERT |
|-----------|------------|-----------|------------|
| READ UNCOMMITTED | なし（推定） | X,REC_NOT_GAP | なし（推定） |
| READ COMMITTED | **なし** ✓実測 | **X,REC_NOT_GAP のみ** | **なし** |
| REPEATABLE READ | **あり** ✓実測 | **X + X,GAP** | **ブロック** |
| SERIALIZABLE | あり（推定） | S + S,GAP | ブロック（推定） |

### Next-Key Lock（ネクストキーロック）

| 分離レベル | LOCK_MODE | supremum pseudo-record | ファントムリード防止 |
|-----------|-----------|----------------------|-----------------|
| READ UNCOMMITTED | X,REC_NOT_GAP（推定） | なし | × |
| READ COMMITTED | **X,REC_NOT_GAP**（Recordのみ） ✓実測 | なし | × |
| REPEATABLE READ | **X**（Next-Key）✓実測 | **あり** ✓実測 | ○ |
| SERIALIZABLE | X（推定） | あり（推定） | ○ |

> Next-Key Lock は `LOCK_MODE = 'X'`（REC_NOT_GAP なし）で表現される。
> 範囲検索の **最初のレコード** のみ `X,REC_NOT_GAP`（前のギャップ不要のため）。

### セカンダリインデックスのロック（実測）

`WHERE category_id = 20 FOR UPDATE`（REPEATABLE READ）:

| INDEX_NAME  | LOCK_MODE     | LOCK_DATA | 意味 |
|-------------|---------------|-----------|------|
| NULL        | IX            | NULL      | テーブルIX |
| idx_category| **X**         | 20, 3     | Next-Key Lock (cat=20, id=3) |
| idx_category| **X,GAP**     | 30, 4     | Gap Lock（次カテゴリへの挿入防止） |
| PRIMARY     | **X,REC_NOT_GAP** | 3     | PK Record Lock |

### AUTO-INC Lock（innodb_autoinc_lock_mode=1）

| lock_mode | シンプルINSERT | data_locksの表示 | 並行INSERT |
|-----------|-------------|----------------|-----------|
| 0 (traditional) | AUTO_INCテーブルロック | `AUTO_INC` | ブロック |
| **1 (consecutive) ✓実測** | 軽量mutex | **TABLE IX のみ**（AUTO_INC表示なし） | **ブロックなし** |
| 2 (interleaved) | 軽量mutex | TABLE IX のみ | ブロックなし |

### Deadlock（デッドロック）

| パターン | 発生条件 | InnoDBの対応 |
|---------|---------|------------|
| 古典的デッドロック | 逆順ロック取得 | 自動検知・被害者をROLLBACK |
| Gap Lockデッドロック | 重複ギャップ + INSERT | 自動検知・被害者をROLLBACK |
| テーブル間デッドロック | テーブル間の逆順ロック | 自動検知・被害者をROLLBACK |

## Observer でのロック確認コマンド

Observer ターミナル（`./scripts/observe-locks.sh`接続後）で使用:

```sql
-- 現在のロック一覧
source sql/helpers/observe_locks.sql

-- ロック待機状態
source sql/helpers/observe_lock_waits.sql

-- アクティブトランザクション
source sql/helpers/observe_trx.sql

-- InnoDB内部状態（デッドロック情報含む）
source sql/helpers/show_engine_status.sql

-- データリセット（テスト後）
source sql/helpers/reset_data.sql
```

## ディレクトリ構成

```
mysql-2026-lock-test/
├── devbox.json
├── .gitignore
├── README.md
├── scripts/
│   ├── setup.sh              # MySQL初期化・起動
│   ├── teardown.sh           # MySQL停止・クリーンアップ
│   ├── connect-a.sh          # Session A接続
│   ├── connect-b.sh          # Session B接続
│   └── observe-locks.sh      # ロック観察用接続
├── sql/
│   ├── 00_setup/             # データベース・テーブル初期化
│   ├── 01_for_update/        # FOR UPDATE（排他行ロック）
│   ├── 02_for_share/         # FOR SHARE（共有行ロック）
│   ├── 03_gap_lock/          # ギャップロック ★重要
│   ├── 04_next_key_lock/     # ネクストキーロック
│   ├── 05_record_lock/       # レコードロック（ベースライン）
│   ├── 06_intention_lock/    # インテンションロック
│   ├── 07_advisory_lock/     # アドバイザリロック
│   ├── 08_insert_intention_lock/ # インサートインテンションロック
│   ├── 09_auto_inc_lock/     # AUTO-INCロック
│   ├── 10_deadlock/          # デッドロック
│   └── helpers/              # 観察用SQLヘルパー
└── results/                  # 実行結果記録用（.gitignore対象）
```

## トラブルシューティング

### MySQL が起動しない

```bash
# エラーログ確認
cat ./mysql-data/mysql-error.log

# データディレクトリをリセットして再初期化
rm -rf ./mysql-data
./scripts/setup.sh
```

### ポート 13306 が使用中

```bash
# 使用中のプロセス確認
lsof -i :13306

# または別のポートを scripts/setup.sh で指定
```

### ソケットファイルが見つからない

```bash
# MySQLが起動しているか確認
ls ./mysql-data/mysql.sock

# 起動していない場合
./scripts/setup.sh
```

### ロック待機がタイムアウトする

デフォルトの `innodb_lock_wait_timeout` は 50 秒です。テスト中はステップを素早く実行するか:

```sql
SET SESSION innodb_lock_wait_timeout = 300;  -- 5分に延長
```

### devbox で mysql コマンドが見つからない

```bash
devbox shell  # devbox環境に入ってから実行
```

## 停止

```bash
./scripts/teardown.sh
```

## 参考リンク

- [MySQL 8.4 InnoDB Locking](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking.html)
- [InnoDB Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-isolation-levels.html)
- [Performance Schema data_locks](https://dev.mysql.com/doc/refman/8.4/en/performance-schema-data-locks-table.html)
- [InnoDB AUTO_INCREMENT Lock Modes](https://dev.mysql.com/doc/refman/8.4/en/innodb-auto-increment-handling.html)
