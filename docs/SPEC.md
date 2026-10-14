# SPEC.md — moonbit-multiindex API 规格(唯一真源)

> **本文件是 API 的唯一真源**:签名、返回类型、语义有疑问时,以此为准。
> 行为不确定且本文件未写清时,以参考实现真实行为为准,并在 `CHANGELOG.md` 记录裁定。
> 设计动机见 [`DEVPLAN.md`](DEVPLAN.md);文档地图见 [`README.md`](README.md)。

---

## §0 参考实现(Rust 生态)—— 已核实(2026-10-14)

| 库 | 版本 | **许可证** | 下载量 | 最近更新 | 与本库的关系 |
|---|---|---|---|---|---|
| **`multi_index_map`**(lun3x) | 0.15.1 | **MIT** | 377,774 | 2026-01-18 | **主蓝本**:同为"记录 + N 索引"容器 |
| `indexmap`(indexmap-rs) | 2.14.2 | Apache-2.0 OR MIT | 16.8 亿 | 2026-09-05 | 有序哈希表(同作者已有 MoonBit 版) |
| `bimap`(billyrieger) | 0.6.3 | Apache-2.0/MIT | 5079 万 | 2023-03-19 | 双向映射(同作者已有 MoonBit 版) |
| `slotmap`(orlp) | 1.1.1 | **Zlib** | 1.15 亿 | 2025-12-06 | 稳定键 + 槽复用(**无索引**) |
| `thunderdome` | 0.6.1 | MIT OR Apache-2.0 | 111 万 | 2023-06-25 | 紧凑代际索引竞技场 |
| `generational-arena` | 0.2.9 | **MPL-2.0** | 1033 万 | 2023-05-22 | 代际索引(**弱 copyleft**) |
| `hecs` | 0.11.2 | MIT OR Apache-2.0 | 609 万 | 2026-10-04 | ECS,记录表组织方式 |

> 数据来源:crates.io API(`https://crates.io/api/v1/crates/<name>`)与各仓库 README,2026-10-14 实测。

**许可证结论**:主蓝本 `multi_index_map` 为 **MIT**,与本库 Apache-2.0 **兼容**(可参考语义与接口形态,
须在 `README.md`/`CHANGELOG.md` 保留归属);`slotmap` 为 Zlib(宽松);`generational-arena` 是
**MPL-2.0(弱 copyleft)**——**只借鉴思路,不复制代码**。

### §0.1 主蓝本 `multi_index_map` 的实现(已核实)

用 **derive 宏** `#[derive(MultiIndexMap)]` 标注记录结构体,由宏生成容器类型:

```rust
#[derive(MultiIndexMap, Debug)]
struct Order {
    #[multi_index(hashed_unique)]     order_id: u32,
    #[multi_index(ordered_unique)]    timestamp: u64,
    #[multi_index(hashed_non_unique)] trader_name: String,
    filled: bool,        // 未索引字段
    volume: u64,
}
// 宏生成(摘要):
struct MultiIndexOrderMap {
    _store: slab::Slab<Order>,                            // 后备存储(连续内存 + 空洞)
    _order_id_index: HashMap<u32, usize>,                 // 唯一哈希索引
    _timestamp_index: BTreeMap<u64, usize>,               // 有序唯一索引
    _trader_name_index: HashMap<String, BTreeSet<usize>>, // 非唯一索引
}
```

- **索引种类**:`hashed_unique` / `hashed_non_unique` / `ordered_unique` / `ordered_non_unique`
  —— 与本库"唯一 / 非唯一 / 有序"三类一一对应,证明分类合理。
- **后备存储用 `Slab`**(连续内存 + 可能空洞)——与本库 `rows : Array[V?]` **同构**。
- **非唯一索引用 `BTreeSet<usize>`** 存同键集合。
- **唯一性冲突不改变容器**:`try_insert` 返回 `Err`,元素归还调用方 —— 与本库"冲突前检查、零变更"一致。
- **API 形态**(每字段一套方法):`try_insert` / `insert` / `get_by_X`(唯一→`Option`、非唯一→`Vec`)/
  `get_mut_by_X`(仅未索引字段)/ `update_by_X`(未索引字段)/ `modify_by_X`(整记录,触发重索引)/
  `remove_by_X` / `iter` / `iter_by_X`。
- **官方 Future work** 里明确写着"允许插入重复唯一键时覆盖并返回被顶替元素""用 vector-map 优化小整数键"
  —— 前者本库**不做**(选择显式 `Err`),后者与本库 `Array[Int]` 桶方向一致。

### §0.2 本库相对主蓝本的原创新增(申报书要点)

1. **代际 `RowId`(ABA 防护)** —— 主蓝本的 `Slab` 槽位复用**不带代际号**,陈旧下标会静默命中
   复用该槽的**新**元素;本库 `RowId{slot, gen}` 拒绝陈旧句柄(探针实测删除返回 `None`)。
2. **运行时注册索引**(闭包投影)—— MoonBit 无等价 derive 宏,改为
   `register_unique(name, (V) -> K)`;代价是索引名运行时校验,收益是**可动态增删索引、可枚举索引名**。
3. **插入序语义** —— 主蓝本按槽位序遍历后备存储;本库额外维护 `order`,提供插入序遍历。
4. **公开 `verify_invariants()`** —— 主蓝本没有一致性自检 API。
5. **索引名统一为 `String`** —— 主蓝本的方法名是编译期生成的,无法运行时枚举;本库可 `index_names()`。

### §0.3 明确的取舍(记入 `CHANGELOG.md` Notes/Deviations)

| 取舍点 | 主蓝本 | 本库 | 理由 |
|---|---|---|---|
| 非唯一桶结构 | `BTreeSet<usize>`:删 O(log k)、自动去重、有序 | `Array[Int]`:删 O(k)、保持插入序 | 桶通常很短,常量更小;去重由不变量 I3 保证;保留插入序 |
| 冲突语义 | `try_insert`→`Err`;`insert`→覆盖/panic | **一律 `Err`,绝不静默覆盖** | 与同作者 `bimap` 的显式冲突上报风格一致 |
| 索引定义方式 | derive 宏(编译期) | 运行时闭包注册 | MoonBit 无等价宏机制 |
| 句柄 | `usize`(槽下标) | `RowId{slot, gen}` | ABA 防护 |

---

**许可证纪律**:本库以 **Apache-2.0** 发布。参考 MPL 系实现
(`generational-arena`)时**只借鉴思路、不复制代码**;采用某库语义时须在 `README.md` 致谢与
`CHANGELOG.md` Notes/Deviations 写明来源与参考范围。

---

## §1 定位与概念辨析(过审关键)

| 结构 | 索引数 | 键唯一性 | 记录身份 | 索引间关系 |
|---|---|---|---|---|
| `aurasuisui/indexmap` | 1(主键) | 唯一 | 键本身 | — |
| `aurasuisui/bimap` | **2** | 两个方向都唯一 | 左键 | **必须互为逆函数**(强耦合) |
| **`aurasuisui/multiindex`** | **N** | **每索引独立**(唯一/非唯一/有序) | **稳定 `RowId`** | **彼此无关** |

**一句话**:`BiMap` 是"两个互为逆的唯一索引"的特例;本库把它泛化为 **N 个彼此独立的索引**,
并引入 bimap 完全没有的两个概念:**记录身份**(`RowId`)与**非唯一索引**。

### 与生态既有项目的边界

| 既有项目 | 它是什么 | 为什么不是重复 |
|---|---|---|
| `Milky2018/slotmap` | 稳定键 + 槽复用 + 副表 | **无索引投影、无唯一性约束、无按键查找** |
| `kesmeey/IndexMap` / `wqbcs/moon_collections` / `Hhsqoo/moon-collections` | 有序哈希表(保留插入序) | 单索引"键→值",目标是保序;本库目标是**多路查找** |
| `dowdiness/btree` / `order-tree` | 计数 B 树(位置索引) | 单一有序结构,无多索引一致性维护 |

> 检索证据(2026-10-13):`moon search "multi index"` / `"secondary index"` 在 mooncakes 上无相关结果;
> GitHub `moonbit+multi-index`、`moonbit+secondary+index` 均为 0 结果。

---

## §2 公开类型

### §2.1 `RowId` — 稳定记录句柄

```moonbit
pub struct RowId {
  slot : Int
  gen : Int
} derive(Eq, Hash, Debug)
```

- `slot` 是 `rows` 中的下标;`gen` 是该槽的代际号,**每次槽被复用(删除后)递增 1**。
- **语义**:`RowId` 只在 `gen` 与槽当前代际一致时有效。用陈旧 `RowId` 调用 `remove` / `update` /
  `get` 一律返回 `None` / `false` / `Err`,**绝不静默命中槽的新占用者**(ABA 防护)。
  > 已由探针实测:删除后槽位被新记录复用,用旧 `RowId` 删除返回 `None`。
- 不保证 `RowId` 可跨进程/跨版本持久化(见 §11)。

### §2.2 `Conflict[K]` — 唯一性冲突上报

```moonbit
pub enum Conflict[K] {
  UniqueViolation(String, K, RowId)
} derive(Debug, Eq)
```

- `UniqueViolation(index_name, key, holder)`:唯一索引 `index_name` 已把 `key` 映射到活记录 `holder`。
- **故意没有「无冲突」变体**:无冲突用 `Option::None` 表达。
  加变体会 ① 与 `Option::None` 在 match 位置混淆;② 迫使调用方匹配一个不可能出现的 `Err`。
  > 两条均由探针实测(见 §9)。

### §2.3 `Table[K, V]` — 记录表

```moonbit
pub struct Table[K, V] {
  // 私有字段见 DEVPLAN §2
}
```

**类型参数约束**:MoonBit 的结构体泛型**不能**带 trait 约束,因此 `K : Hash + Eq`(以及
`SortedIndex` 需要的 `K : Compare`)**写在每个方法上**,按方法最小化。

---

## §3 API 规划(v0.1.0,实现时按本节锁定签名)

> 状态:规划中。实现落定后本节的签名即为契约,并由 `pkg.generated.mbti` 与测试共同钉死。

### §3.1 构造与索引注册

| 方法 | 说明 |
|---|---|
| `Table::new() -> Table[K, V]` | 空表 |
| `Table::with_capacity(cap : Int)` | 预留容量 |
| `register_unique(name : String, project : (V) -> K) -> Unit` | 注册唯一索引 |
| `register_non_unique(name : String, project : (V) -> K) -> Unit` | 注册非唯一索引 |
| `register_sorted(name : String, project : (V) -> K)` (需 `K : Compare`) | 注册有序索引 |
| `has_index(name : String) -> Bool` | 索引是否存在 |

**注册语义(待锁定)**:重名注册应报错还是覆盖?**倾向**:返回 `Result[Unit, ...]`,
重名报错(与"冲突不静默覆盖"的整体风格一致)。

**对已有数据注册索引**:注册时表非空则必须回填扫描(`insert` 全部活记录),复杂度 O(len)。
须在 SPEC 中明确,并由测试钉死。

### §3.2 写入

| 方法 | 返回 | 说明 |
|---|---|---|
| `insert(v : V) -> Result[RowId, Conflict[K]]` | 新记录句柄 | 冲突时**不做任何变更** |
| `update(id : RowId, v : V) -> Result[Unit, Conflict[K]]` | 成功/冲突 | **排除自身**的冲突检查;陈旧 id → `Err` |
| `remove(id : RowId) -> V?` | 被删记录 | 陈旧 id → `None` |
| `clear() -> Unit` | — | 清空所有记录与索引 |

### §3.3 查询

| 方法 | 返回 | 说明 |
|---|---|---|
| `get_by(name : String, key : K) -> RowId?` | 唯一索引命中 | 非唯一索引上的语义待定(倾向返回首个,`iter_by` 才是正解) |
| `iter_by(name : String, key : K)` | 该键下所有记录 | 非唯一索引 |
| `range_by(name : String, lo : K, hi : K)` (需 `Compare`) | 区间内记录 | 有序索引 |
| `get(id : RowId) -> V?` | 按句柄取记录 | 陈旧 id → `None` |
| `contains(id : RowId) -> Bool` | — | |
| `len() -> Int` / `is_empty() -> Bool` | — | |
| `iter()` | 插入序遍历 | fail-fast(比照 `version`) |
| `index_names() -> Array[String]` | 已注册索引名 | |

### §3.4 诊断(拿分点,也是自测手段)

| 方法 | 说明 |
|---|---|
| `verify_invariants() -> Bool` | **公开**的白盒自检:校验 I1–I8 |
| `index_stats(name : String) -> ...` | 桶数 / 最长桶 / 平均桶长 |

> `verify_invariants` 是**公开 API**而非仅测试辅助:调用方可在自己的断言里使用它。
> 这与 bimap 的 `check_bijection`(仅测试内)不同 —— 多索引的一致性更难自查,值得公开。

---

## §4 核心不变量(属性测试的靶子)

```
I1  order 中每个槽位都是活记录,且无重复
I2  活记录数 == len == order.length()
I3  每条索引的每个桶内,槽位无重复
I4  桶内每个槽位 s 满足 (idx.project)(rows[s]) == 桶键
I5  唯一索引的每个桶长度 <= 1
I6  free 中无重复,且 free 与活记录集合不相交
I7  每个活记录恰好出现在每条索引的对应桶中(无遗漏、无悬挂)
I8  version 仅在真实变更时递增
```

**I5 与 I7 必须成对校验**:I7 防"漏",I5 防"多"。
> I5 是探针实测漏洞反推出来的:最初的校验只查 I3/I4,`update` 又漏了冲突检查,
> 结果一次"更新成已占用的唯一键"让唯一桶出现两个持有人,而校验仍返回 true。

---

## §5 变更汇聚点与三条高危路径

**汇聚点**:`insert_impl` / `remove_impl` / `update_impl` 是**唯一**允许同时触碰
`rows` + `order` + `indexes` + `gens` + `free` 的地方。

1. **`update` 必须做"排除自身"的冲突检查** —— 记录更新成自身已有的唯一键不算冲突。
2. **冲突检查在任何变更之前完成** —— 返回 `Err` 时表必须与调用前等价。
3. **删旧桶与加新桶之间不得有可观察中间态** —— 键不变时走快路径。

---

## §6 复杂度

| 操作 | 复杂度 |
|---|---|
| `insert` | O(I + Σ桶代价),I = 索引数 |
| `get_by` | 均摊 O(1) |
| `range_by` | O(log n + k) |
| `remove` / `update` | O(I + Σ桶长) |
| `iter` | O(len) |
| 空间 | O(len + Σ索引条目) |

---

## §7 错误语义

- **唯一冲突不覆盖**:`insert` / `update` 返回 `Err(UniqueViolation(...))`,且**返回前零变更**。
- **陈旧句柄**:`remove`/`get` 返回 `None`,`update` 返回 `Err`;**不 panic、不误伤新占用者**。
- **未知索引名**:查询类返回空(`None` / 空数组);写入类因索引名由 `register_*` 给定的闭包投影驱动,
  不存在"写入时索引名未知"的路径。错误类型形态待 §0 调研后锁定。

---

## §8 Trait 实现规划

| Trait | 规划 |
|---|---|
| `Debug` / `Show` | `RowId`、`Conflict`、`Table`(手写 `Show`,不用 deprecated 的 `derive(Show)`) |
| `Default` | `Table::new()` |
| `Eq` | `Table` 为**记录集合**语义;索引是派生视图,**不参与相等性** |
| `Hash` | 与 `Eq` 一致(顺序无关正则形,比照 bimap 的 sort-fold) |
| `ToJson` / `FromJson` | JSON 往返;"索引不参与序列化,反序列化后重建索引" |
| `Arbitrary` | QuickCheck 生成器 |

---

## §9 设计教训(探针实测,2026-10-14)

| 教训 | 说明 |
|---|---|
| 结构体泛型不能带 trait 约束 | `struct Index[K : Hash + Eq, V]` 是语法错误;约束写在方法上 |
| 错误枚举不要「无错」变体 | 与 `Option` 重复,且迫使调用方匹配不可能的 `Err` |
| 变体名不要叫 `None_` | 与 `Option::None` 在 match 位置混淆(探针实际踩中) |
| 不变量校验要成对 | 只查"漏"(I7)不查"多"(I5)会让漏洞逃逸(探针实际踩中) |
| 闭包投影可作字段 | `project : (V) -> K` 作为结构体字段可正常调用 |
| 有序索引可直接用 `SortedMap` | `@sorted_map.SortedMap[K, Array[Int]]` 满足范围查询需求 |

---

## §10 完整 API 速查表

> 实现落定后由本节汇总全部公开签名(与 `README.md` 的 API 表同源)。

---

## §11 明确不实现(避免范围蔓延)

- **不提供**持久化 `RowId`(跨进程/跨版本稳定):代际号不保证跨会话一致。
- **不提供**并发安全:无锁/加锁版本均不在 v0.1.0 范围。
- **不提供**二级索引的磁盘落盘 / B+ 树页式存储:纯内存。
- **不提供**索引的"部分索引 / 表达式索引 / 复合索引":投影是单字段到单键的函数。
- **不依赖** `aurasuisui/bimap` 或 `aurasuisui/indexmap`(同作者作品,代码独立)。
