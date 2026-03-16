# ロック挙動実測結果

実行日: 2026-03-16
MySQL バージョン: 8.0.45（devbox mysql80@latest）
innodb_autoinc_lock_mode: 1（consecutive）
デフォルト分離レベル: REPEATABLE-READ

---

## 1. Record Lock（05_record_lock）

### REPEATABLE READ + `WHERE id = 30 FOR UPDATE`（PKポイント検索）

```
LOCK_TYPE | LOCK_MODE     | INDEX_NAME | LOCK_DATA
TABLE     | IX            | NULL       | NULL
RECORD    | X,REC_NOT_GAP | PRIMARY    | 30
```

- **ギャップロック**: なし（PKポイント検索のため）
- **LOCK_MODE**: `X,REC_NOT_GAP` = Record Lock のみ

---

## 2. Gap Lock（03_gap_lock）★最重要

### REPEATABLE READ + `WHERE id > 20 AND id < 40 FOR UPDATE`

```
LOCK_TYPE | LOCK_MODE     | INDEX_NAME | LOCK_DATA
TABLE     | IX            | NULL       | NULL
RECORD    | X             | PRIMARY    | 30   ← Next-Key Lock (20,30]
RECORD    | X,GAP         | PRIMARY    | 40   ← Gap Lock (30,40)
```

- **ギャップロック**: あり
  - `X`（LOCK_DATA=30）= Next-Key Lock（ギャップ(20,30] + レコード）
  - `X,GAP`（LOCK_DATA=40）= Gap Lock のみ（ギャップ(30,40)）

### READ COMMITTED + `WHERE id > 20 AND id < 40 FOR UPDATE`

```
LOCK_TYPE | LOCK_MODE     | INDEX_NAME | LOCK_DATA
TABLE     | IX            | NULL       | NULL
RECORD    | X,REC_NOT_GAP | PRIMARY    | 30
```

- **ギャップロック**: なし（`X,GAP` が一切表示されない）
- **LOCK_MODE**: `X,REC_NOT_GAP` のみ

---

## 3. Next-Key Lock（04_next_key_lock）

### REPEATABLE READ + `WHERE id >= 20 FOR UPDATE`

```
LOCK_TYPE | LOCK_MODE     | INDEX_NAME | LOCK_DATA
TABLE     | IX            | NULL       | NULL
RECORD    | X,REC_NOT_GAP | PRIMARY    | 20   ← 最初のレコード（gapなし）
RECORD    | X             | PRIMARY    | 30   ← Next-Key Lock (20,30]
RECORD    | X             | PRIMARY    | 40   ← Next-Key Lock (30,40]
RECORD    | X             | PRIMARY    | 50   ← Next-Key Lock (40,50]
RECORD    | X             | PRIMARY    | supremum pseudo-record ← Gap (50,+∞)
```

- `LOCK_MODE = 'X'`（REC_NOT_GAP なし）= Next-Key Lock
- `supremum pseudo-record` = 最大値より大きい無限大ギャップ
- id=20 は `X,REC_NOT_GAP`（検索範囲の先頭のため gap 前は不要）

---

## 4. セカンダリインデックス Next-Key Lock（04_next_key_lock/rr_secondary_index）

### REPEATABLE READ + `WHERE category_id = 20 FOR UPDATE`

```
OBJECT_NAME | INDEX_NAME  | LOCK_TYPE | LOCK_MODE     | LOCK_DATA
products    | NULL        | TABLE     | IX            | NULL
products    | idx_category| RECORD    | X             | 20, 3   ← セカンダリ Next-Key Lock
products    | idx_category| RECORD    | X,GAP         | 30, 4   ← セカンダリ Gap Lock
products    | PRIMARY     | RECORD    | X,REC_NOT_GAP | 3       ← PK Record Lock
```

- セカンダリ: `X`（category_id=20, id=3）= Next-Key Lock
- セカンダリ: `X,GAP`（category_id=30, id=4）= Gap Lock（次のカテゴリへの挿入防止）
- PRIMARY: `X,REC_NOT_GAP`（id=3）= PK Record Lock
- **LOCK_DATA形式**: セカンダリは `"インデックス値, PK値"` の形式

---

## 5. FOR SHARE（02_for_share）

### REPEATABLE READ + `WHERE id = 30 FOR SHARE`

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IS            | NULL
RECORD    | S,REC_NOT_GAP | 30
```

- テーブルロック: `IS`（Intent Shared）← FOR UPDATE の IX と異なる
- 行ロック: `S,REC_NOT_GAP`

---

## 6. SERIALIZABLE（05_record_lock/sr_serializable）

### SERIALIZABLE + `WHERE id = 30`（通常 SELECT、FOR SHARE なし）

```
LOCK_TYPE | LOCK_MODE     | LOCK_DATA
TABLE     | IS            | NULL
RECORD    | S,REC_NOT_GAP | 30
```

- 通常 SELECT でも `S,REC_NOT_GAP` を自動取得（他分離レベルとの最大の違い）
- FOR SHARE と同一のロック = SERIALIZABLE では明示的 FOR SHARE は冗長

---

## 7. AUTO-INC Lock（09_auto_inc_lock）

### mode=1（consecutive）+ シンプル INSERT

```
OBJECT_NAME | LOCK_TYPE | LOCK_MODE | LOCK_STATUS
orders      | TABLE     | IX        | GRANTED
```

- `AUTO_INC` テーブルロックは表示されない（mode=1 のシンプルINSERTは軽量mutex）
- `data_locks` には TABLE IX のみ

---

## 分離レベルごとのロック挙動サマリ（実測）

| 操作 | READ UNCOMMITTED | READ COMMITTED | REPEATABLE READ | SERIALIZABLE |
|------|:---:|:---:|:---:|:---:|
| FOR UPDATE（PK）の LOCK_MODE | X,REC_NOT_GAP | X,REC_NOT_GAP | X,REC_NOT_GAP | X,REC_NOT_GAP |
| 範囲 FOR UPDATE の Gap Lock | TODO | **なし** | **あり** (X,GAP) | TODO |
| 通常 SELECT のロック | なし | なし | なし | **S,REC_NOT_GAP** |
| FOR SHARE の LOCK_MODE | TODO | S,REC_NOT_GAP | S,REC_NOT_GAP | S,REC_NOT_GAP |
| テーブル IS/IX | IX | IX | IX | IS (FOR SHARE) |
