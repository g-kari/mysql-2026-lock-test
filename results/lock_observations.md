# ロック挙動実測結果

実行日: 2026-03-16
MySQL バージョン: 8.0.45（devbox mysql80@latest）
innodb_autoinc_lock_mode: 1（consecutive）
デフォルト分離レベル: REPEATABLE-READ

---

## 1. FOR UPDATE 全分離レベル比較

### PKポイント検索（`WHERE id = 30 FOR UPDATE`）

| 分離レベル | TABLE | ROW LOCK_MODE | ギャップロック |
|-----------|-------|--------------|--------------|
| READ UNCOMMITTED | IX | **X,REC_NOT_GAP** | なし |
| READ COMMITTED | IX | **X,REC_NOT_GAP** | なし |
| REPEATABLE READ | IX | **X,REC_NOT_GAP** | なし |
| SERIALIZABLE | IX | **X,REC_NOT_GAP** | なし |

→ PKポイント検索は全分離レベルで `X,REC_NOT_GAP`（ギャップロックなし）

### 範囲検索（`WHERE id > 20 AND id < 40 FOR UPDATE`）

| 分離レベル | TABLE | ロック一覧 |
|-----------|-------|----------|
| READ UNCOMMITTED | IX | `X,REC_NOT_GAP` (id=30) のみ |
| READ COMMITTED | IX | `X,REC_NOT_GAP` (id=30) のみ |
| REPEATABLE READ | IX | `X` (id=30) + `X,GAP` (id=40) |
| SERIALIZABLE | IX | `X` (id=30) + `X,GAP` (id=40) |

**重要な観察:**
- `LOCK_MODE = 'X'`（REC_NOT_GAP なし）= Next-Key Lock（レコード + 前のギャップ）
- `LOCK_MODE = 'X,GAP'` = Gap Lock のみ（レコードなし）
- READ UNCOMMITTED / READ COMMITTED は Gap Lock を取得しない
- REPEATABLE READ / SERIALIZABLE は Gap Lock を取得する

---

## 2. Gap Lock の詳細（最重要）

### REPEATABLE READ + `WHERE id > 20 AND id < 40 FOR UPDATE`

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IX            | NULL
RECORD    | X             | 30   ← Next-Key Lock: ギャップ(20,30] + レコード
RECORD    | X,GAP         | 40   ← Gap Lock: ギャップ(30,40)のみ
```

### READ COMMITTED + `WHERE id > 20 AND id < 40 FOR UPDATE`

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IX            | NULL
RECORD    | X,REC_NOT_GAP | 30   ← Record Lock のみ（Gap なし）
```

**LOCK_DATA の解釈:**
- `LOCK_DATA = '30'` で `LOCK_MODE = 'X'` → id=30 の前のギャップ (20,30] を含む Next-Key Lock
- `LOCK_DATA = '40'` で `LOCK_MODE = 'X,GAP'` → id=40 の前のギャップ (30,40) のみの Gap Lock

---

## 3. Next-Key Lock 詳細（`WHERE id >= 20 FOR UPDATE`）

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IX            | NULL
RECORD    | X,REC_NOT_GAP | 20                    ← 範囲先頭: Record Lockのみ
RECORD    | X             | 30                    ← Next-Key Lock (20,30]
RECORD    | X             | 40                    ← Next-Key Lock (30,40]
RECORD    | X             | 50                    ← Next-Key Lock (40,50]
RECORD    | X             | supremum pseudo-record ← Gap (50,+∞)
```

**観察:**
- 範囲の最初のレコード（id=20）は `X,REC_NOT_GAP`（前のギャップは不要）
- 2番目以降は `X`（Next-Key Lock = レコード + 前のギャップ）
- `supremum pseudo-record` = 最大値より大きいギャップ（50,+∞）

---

## 4. セカンダリインデックスのロック

### `WHERE category_id = 20 FOR UPDATE`（REPEATABLE READ）

```
OBJECT_NAME | INDEX_NAME   | LOCK_TYPE | LOCK_MODE     | LOCK_DATA
products    | NULL         | TABLE     | IX            | NULL
products    | idx_category | RECORD    | X             | 20, 3   ← Next-Key Lock
products    | idx_category | RECORD    | X,GAP         | 30, 4   ← Gap Lock（次カテゴリ防止）
products    | PRIMARY      | RECORD    | X,REC_NOT_GAP | 3       ← PK Record Lock
```

**観察:**
- セカンダリ: `X`（Next-Key Lock）+ `X,GAP`（Gap Lock）の2つ
- PKにも `X,REC_NOT_GAP`（Record Lock）が追加設定される
- `LOCK_DATA` 形式: セカンダリは `"インデックス値, PK値"`

---

## 5. FOR SHARE（共有ロック）

| 操作 | TABLE | ROW LOCK_MODE |
|------|-------|--------------|
| REPEATABLE READ + FOR SHARE | **IS** | **S,REC_NOT_GAP** |
| READ COMMITTED + FOR SHARE | **IS** | **S,REC_NOT_GAP** |
| SERIALIZABLE + FOR SHARE | **IS** | **S,REC_NOT_GAP** |

**ロックアップグレード（同一トランザクション内 S → X）:**
```
FOR SHARE 後に FOR UPDATE を同一行に発行:
  TABLE: IS + IX（両方保持）
  RECORD: S,REC_NOT_GAP + X,REC_NOT_GAP（両方保持）
```

---

## 6. SERIALIZABLE

| 操作 | TABLE | ROW LOCK_MODE |
|------|-------|--------------|
| 通常 SELECT（PKポイント） | IS | S,REC_NOT_GAP |
| 通常 SELECT（範囲） | IS | S（Next-Key） + S,GAP |

**重要:** SERIALIZABLE では `FOR SHARE` なしの通常 SELECT でも自動的にロックを取得する

```
SERIALIZABLE + 通常 SELECT WHERE id > 20 AND id < 40:
  TABLE: IS
  RECORD: S (id=30) ← Next-Key Lock
  RECORD: S,GAP (id=40) ← Gap Lock
```

---

## 7. Intention Lock（インテンションロック）

| 操作 | テーブルの LOCK_MODE |
|------|-------------------|
| FOR UPDATE | **IX**（Intent Exclusive） |
| FOR SHARE | **IS**（Intent Shared） |
| SERIALIZABLE 通常 SELECT | **IS** |

**アドバイザリロック（performance_schema.metadata_locks）:**
```
OBJECT_TYPE    | OBJECT_NAME    | LOCK_TYPE | LOCK_STATUS
USER LEVEL LOCK| test_advisory  | EXCLUSIVE | GRANTED
```
- `GET_LOCK('name', timeout)` → 1=成功, 0=タイムアウト, NULL=エラー
- `IS_FREE_LOCK('name')` → 0（使用中）→ 1（解放後）
- COMMIT/ROLLBACK でもアドバイザリロックは解放されない（セッション切断で解放）

---

## 8. AUTO-INC Lock（mode=1）

| シナリオ | data_locksの LOCK_MODE | AUTO_INCテーブルロック |
|---------|----------------------|---------------------|
| シンプルINSERT（mode=1） | TABLE:IX のみ | **なし（軽量mutex）** |
| AUTO-INC 連番ギャップ | - | ROLLBACK後も連番は戻らない |

**連番ギャップ:**
- ROLLBACK してもAUTO_INCカウンタは巻き戻らない
- 再INSERTすると ROLLBACK 分のIDをスキップした値になる

---

## 9. Deadlock（古典的デッドロック）

**実証結果:**
- Session A: `id=10 FOR UPDATE` → `id=20 FOR UPDATE`
- Session B: `id=20 FOR UPDATE` → `id=10 FOR UPDATE`
- 結果: **Session A が ERROR 1213 でロールバック**、Session B がコミット成功

**InnoDB の被害者選択基準:**
- `TRANSACTION (1) HOLDS: id=20, WAITING: id=10`（Session B相当）
- `TRANSACTION (2) HOLDS: id=10, WAITING: id=20`（Session A相当）
- ロールバックコストが小さい方（修正行数が少ない方）が被害者

**SHOW ENGINE INNODB STATUS の LATEST DETECTED DEADLOCK で確認できる情報:**
- デッドロック検知タイムスタンプ
- 各トランザクションが保持・待機していたロックの詳細（物理レコードの16進数含む）
- `WE ROLL BACK TRANSACTION` で被害者を明示

---

## 10. Gap Lock デッドロック（実証済み）

### 成立シナリオ

```
Session A: BEGIN; SELECT * FROM products WHERE id > 20 AND id < 40 FOR UPDATE;
  → GRANTED: X (id=30), X,GAP (id=40)

Session B: BEGIN; SELECT * FROM products WHERE id > 10 AND id < 30 FOR UPDATE;
  → GRANTED: X (id=20), X,GAP (id=30)
  ※ Gap Lock 同士は互換のため両者 GRANTED

Session B: INSERT INTO products (id, name, category_id) VALUES (35, 'test', 10);
  → INSERT_INTENTION on gap (30,40) → Session A の X,GAP on 40 で WAIT

Session A: INSERT INTO products (id, name, category_id) VALUES (25, 'test', 10);
  → INSERT_INTENTION on gap (20,30) → Session B の X,GAP on 30 で WAIT
  → 循環待機 → ERROR 1213: Deadlock found
  → Session A がロールバック被害者（修正行数が少ない側）
```

### SHOW ENGINE INNODB STATUS — LATEST DETECTED DEADLOCK で確認した情報

- デッドロック検知タイムスタンプ
- Transaction 1（Session B相当）: `HOLDS X,GAP on id=30`, `WAITING X,INSERT_INTENTION on gap (30,40)`
- Transaction 2（Session A相当）: `HOLDS X,GAP on id=40`, `WAITING X,INSERT_INTENTION on gap (20,30)`
- `WE ROLL BACK TRANSACTION (2)` — Session A が被害者として明示

### 重要な観察

- **Gap Lock 同士は互換**: 両セッションが重複するギャップにロックを取得できる
- **INSERT_INTENTION vs Gap Lock は非互換**: INSERT が Gap Lock 保持セッションを待機させる
- **循環待機の成立**: A が B のギャップを待ち、B が A のギャップを待つ → デッドロック
- Gap Lock デッドロックは REPEATABLE READ / SERIALIZABLE でのみ発生（Gap Lock が存在しないため）

---

## 11. READ UNCOMMITTED 追加実測

### FOR UPDATE PK 検索（`WHERE id = 30 FOR UPDATE`）

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IX            | NULL
RECORD    | X,REC_NOT_GAP | 30   ← Record Lock のみ（Gap なし）
```

### FOR UPDATE 範囲検索（`WHERE id > 20 AND id < 40 FOR UPDATE`）

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IX            | NULL
RECORD    | X,REC_NOT_GAP | 30   ← Record Lock のみ（Gap なし）
```

→ RU では範囲検索でも `X,REC_NOT_GAP` のみ。Gap Lock・Next-Key Lock は一切取得しない。

### FOR SHARE（`WHERE id = 30 FOR SHARE`）

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IS            | NULL
RECORD    | S,REC_NOT_GAP | 30   ← 共有 Record Lock のみ
```

### RU セッションの INSERT が RR の Gap Lock でブロック

```
Session A (REPEATABLE READ): WHERE id > 20 AND id < 40 FOR UPDATE
  → GRANTED: X (id=30), X,GAP (id=40)

Session B (READ UNCOMMITTED): INSERT INTO products (id, ...) VALUES (25, ...);
  → INSERT_INTENTION on gap (20,30) → Session A の X (id=30) の前ギャップで WAIT
  → ERROR 1205: Lock wait timeout exceeded after 50s
```

**観察:** Gap Lock の効果は**ロックを保持する側の分離レベル**で決まる。INSERT 側が RU でも、RR セッションの Gap Lock によってブロックされる。

---

## 12. SERIALIZABLE 追加実測

### FOR UPDATE PK 検索（`WHERE id = 30 FOR UPDATE`）

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IX            | NULL
RECORD    | X,REC_NOT_GAP | 30   ← Record Lock のみ（Gap なし）
```

→ PK ポイント検索は SERIALIZABLE でも `X,REC_NOT_GAP`（Gap Lock なし）。

### FOR UPDATE 範囲検索（`WHERE id > 20 AND id < 40 FOR UPDATE`）

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IX            | NULL
RECORD    | X             | 30   ← Next-Key Lock: gap(20,30] + レコード
RECORD    | X,GAP         | 40   ← Gap Lock: gap(30,40) のみ
```

→ REPEATABLE READ と同一のロックパターン。

### 通常 SELECT 範囲（`WHERE id > 20 AND id < 40`、FOR SHARE なし）

```
LOCK_TYPE | LOCK_MODE | LOCK_DATA
TABLE     | IS        | NULL
RECORD    | S         | 30   ← 共有 Next-Key Lock（自動付与）
RECORD    | S,GAP     | 40   ← 共有 Gap Lock（自動付与）
```

**観察:** SERIALIZABLE では `FOR SHARE` なしの通常 SELECT でも共有ロックが自動付与される。これが SERIALIZABLE がファントムリードを完全防止できる理由。

---

## 分離レベルごとのロック挙動 完全サマリ（実測）

### ロック種類と LOCK_MODE 対応表

| ロック種類 | LOCK_TYPE | LOCK_MODE | 説明 |
|-----------|-----------|-----------|------|
| Record Lock | RECORD | `X,REC_NOT_GAP` | レコードのみ（ギャップなし）|
| Record Lock（共有）| RECORD | `S,REC_NOT_GAP` | 共有レコードロック |
| Next-Key Lock | RECORD | `X` | レコード + 前のギャップ |
| Next-Key Lock（共有）| RECORD | `S` | 共有 Next-Key Lock |
| Gap Lock | RECORD | `X,GAP` | ギャップのみ（レコードなし）|
| Gap Lock（共有）| RECORD | `S,GAP` | 共有ギャップロック |
| Insert Intention Lock | RECORD | `X,INSERT_INTENTION` | INSERT前の意図ロック |
| Intent Exclusive | TABLE | `IX` | FOR UPDATE 時のテーブルロック |
| Intent Shared | TABLE | `IS` | FOR SHARE 時のテーブルロック |
| AUTO-INC | TABLE | `AUTO_INC` | AUTO-INCテーブルロック（mode=0/バルク）|

### 分離レベル別 Gap Lock 発生有無

| 分離レベル | PKポイント検索 | 範囲検索 | ファントムリード防止 |
|-----------|-------------|---------|-----------------|
| READ UNCOMMITTED | なし | **なし** | × |
| READ COMMITTED | なし | **なし** | × |
| REPEATABLE READ | なし | **あり** | ○ |
| SERIALIZABLE | なし | **あり** | ○ |
