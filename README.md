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

> **注意**: 以下は実測後に記入するテンプレートです。「TODO」の欄は実際に調査を行った後に更新してください。

### FOR UPDATE（排他行ロック）

| 分離レベル | ギャップロック発生 | ブロック(同一行 FOR UPDATE) | ブロック(ギャップ内INSERT) |
|-----------|-------------------|---------------------------|--------------------------|
| READ UNCOMMITTED | TODO | TODO | TODO |
| READ COMMITTED | なし | TODO | なし |
| REPEATABLE READ | あり | TODO | あり |
| SERIALIZABLE | TODO | TODO | TODO |

### FOR SHARE（共有行ロック）

| 分離レベル | 同一行 FOR SHARE | 同一行 FOR UPDATE | ギャップ内INSERT |
|-----------|----------------|-------------------|----------------|
| READ UNCOMMITTED | TODO | TODO | TODO |
| READ COMMITTED | 互換（OK） | TODO | なし |
| REPEATABLE READ | 互換（OK） | ブロック | あり |
| SERIALIZABLE | TODO | TODO | TODO |

### Gap Lock（ギャップロック）

| 分離レベル | Gap Lock発生 | Gap内INSERT | Gap外INSERT |
|-----------|------------|-------------|------------|
| READ UNCOMMITTED | TODO | TODO | OK |
| READ COMMITTED | **なし** | OK | OK |
| REPEATABLE READ | **あり** | ブロック | OK |
| SERIALIZABLE | TODO | TODO | OK |

### Next-Key Lock（ネクストキーロック）

| 分離レベル | Next-Key Lock発生 | ファントムリード防止 |
|-----------|-----------------|------------------|
| READ UNCOMMITTED | TODO | × |
| READ COMMITTED | 部分的 | × |
| REPEATABLE READ | **あり** | ○ |
| SERIALIZABLE | TODO | ○ |

### AUTO-INC Lock（オートインクリメントロック）

| lock_mode | 動作 | 並行INSERT |
|-----------|------|-----------|
| 0 (traditional) | テーブルロック | ブロック |
| 1 (consecutive) | シンプルINSERTは軽量ロック | TODO |
| 2 (interleaved) | 全て軽量ロック | OK（連番ギャップあり） |

### Deadlock（デッドロック）

| パターン | 発生条件 | InnoDBの対応 |
|---------|---------|------------|
| 古典的デッドロック | 逆順ロック取得 | 自動検知・ロールバック |
| Gap Lockデッドロック | 重複ギャップロック | TODO |
| FK関連デッドロック | テーブル間の逆順 | TODO |

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
