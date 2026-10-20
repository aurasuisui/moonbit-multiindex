# SPEC.md — moonbit-multiindex API 规格(唯一真源)

> **本文件是 API 的唯一真源**:签名、返回类型、语义有疑问时,以此为准。
> 行为不确定且本文件未写清时,以参考实现真实行为为准,并在 `CHANGELOG.md` 记录裁定。
> 设计动机见 [`DEVPLAN.md`](DEVPLAN.md);文档地图见 [`README.md`](README.md)。

---

## §0 参考实现(Rust 生态)—— 已核实(2026-10-14)

> ⚠️ **本库不是 `multi_index_map` 的移植(port)**。两侧共享同一个架构**想法**(记录表 + 每索引一张查找表),
> 但 MoonBit 没有过程宏、没有 `Borrow<Q>`、无法返回元素内的 `&mut`,且上游 `modify` 的冲突路径本身有缺陷
> —— **没有一行代码可以照搬**。本节只登记**设计思想的来源**;逐维度的"可参考思想 vs 必须自研实现"对照表见
> [`plans/v0.1.0.md` §一](plans/v0.1.0.md)。申报口径为**原创**;来源与许可证按合规要求在 [`NOTICE`](../NOTICE) 登记。

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
| 非唯一桶结构 | `BTreeSet<usize>` | **`SortedSet[Int]`(采纳同一路线)** | 初稿选 `Array[Int]`(保插入序、常量小),但**大桶下 O(k) 线性删除不可接受**;主蓝本 0.6.0 已因性能把 `Vec` 换成 `BTreeSet`(§0.4-4)。**代价:桶内顺序变为槽位号升序,不再保留插入序** |
| 冲突语义 | `try_insert`→`Err`(归还元素);`insert`→**panic** | **只有 `Result` 版本,且归还记录**(`Rejected[K,V]`);绝不 panic | MoonBit 的 panic 等价 abort、不可恢复;记录按值传递,不归还则调用方**丢失数据**(§0.4-3/5) |
| `modify` 原子性 | 半更新后 panic → **留下脏索引**(缺陷) | **先全量校验,再一次性提交** | §0.4-1 与 §5 规则 2 |
| 索引定义方式 | derive 宏(编译期) | 运行时闭包注册 | MoonBit 无等价宏机制 |
| 句柄 | `usize`(槽下标) | `RowId{slot, gen}` | ABA 防护 |
| 代际号溢出 | 静默回绕(slotmap / thunderdome / hecs / bevy 一致) | **溢出即退役槽位** | 陈旧句柄永不复活(§0.4-8) |
| 范围查询 | **无**(ordered 索引只暴露点查与全量遍历) | `range_by` / `range_inclusive_by` | 主蓝本 API 层缺口(§0.4-2) |

---

### §0.4 源码级核对补强(第二轮调研,逐行读 `generators.rs`/`lib.rs`)

完整报告存档见 [`research/rust-ecosystem-2026-10-14.md`](research/rust-ecosystem-2026-10-14.md)。以下条目**直接改变了本库的设计**:

1. **主蓝本的 `modify_by_*` 在中途 panic 会留下脏索引**。源码顺序是「先 remove 旧 key → 再 insert 新 key →
   若插入返回 `Some` 则 panic」,即 panic 时索引已处于半更新状态。
   → **本库据此把"先校验后提交"写死为强制规则**(§5 规则 1/2),并把该场景做成回归测试钉子。
2. **主蓝本缺少范围查询 API**。`ordered_*` 索引底层是 `BTreeMap`,但只生成 `get_by_*`(点查)与
   `iter_by_*`(全量按序遍历),**没有 range** —— 存储层做到了,API 层没做。→ **这是本库的明确增量**(§3.3)。
3. **冲突时应当把记录原样归还调用方**。主蓝本 `try_insert` 返回 `Err(UniquenessError(elem))`,
   元素不丢;本库若只返回 `Conflict[K]`,`insert(v)` 消费掉 `v` 后调用方将**失去这条记录**
   (MoonBit 是按值传递)。→ 新增 `Rejected[K, V]`(§2.2),冲突信息与记录一并归还。
4. **主蓝本的非唯一索引在 0.6.0 从 `Vec` 换成了 `BTreeSet`**,release note 原文:
   *"use BTreeSet to store equivalent elements in a non-unique index to improve insert/remove/modify performance"*。
   → **推翻本库初稿的 `Array[Int]` 桶**,改用**有序集合**(见 §0.3 修订与 §3 索引表示)。
5. **`insert` 与 `try_insert` 语义分裂**:`insert` 冲突直接 panic,`try_insert` 返回 `Err`。
   → 本库**只提供 Result 版本,不提供 panic 版本**(MoonBit 的 panic 等价于 abort,不可恢复)。
6. **`FromIterator` 遇重复键是"第一个胜出"**(与 `HashMap`/`BTreeMap` 的"后者胜"相反)。
   → 本库批量插入需在 SPEC 明确语义并测试钉死(§3.2 `insert_many`)。
7. **主蓝本的插入用 `slab::vacant_entry()` 预留槽位而不占用**,从而做到"唯一性检查失败时表完全未变"。
   这是实现 §5 规则 2 的**具体机制**,本库照此办理(先探测空槽/预留,再逐索引校验,最后落库)。
8. **代际号溢出:所有 Rust 参考实现都选择静默回绕**(slotmap 2³¹、thunderdome u32::MAX→1、
   hecs/bevy `wrapping_add`;bevy 文档明写 "generations can (and do) wrap or alias")。
   → 本库采取**溢出即退役槽位**(不再放回 free list),使陈旧句柄永不复活(§3.4、I9)。
9. **许可证边界**:候选集中唯一有传染性的是 **MPL-2.0**(`generational-arena`,且**仓库已归档**;
   `im` 亦为 MPL-2.0+ 且归档)——**只借鉴思路、不复制代码**。`slotmap` 是 **Zlib**(宽松);
   `thunderdome` 的 GitHub 页面显示 Apache-2.0 但 **Cargo.toml 是 `MIT OR Apache-2.0`**(以 Cargo.toml 为准);
   `bimap` 的 `Apache-2.0/MIT` 是**非标准 SPDX 写法**,实为双许可。

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
- `slot` / `gen` 字段**只读公开**(外部可读、不可构造),便于调用方诊断;构造只能由 `Table` 产生。
- 不保证 `RowId` 可跨进程/跨版本持久化(见 §11)。

#### §2.1.1 代际号上限 `GEN_MAX`(I9 的退役阈值)

```moonbit
const GEN_MAX : Int = 1073741824   // 2^30
```

> ⚠️ **前提:MoonBit 的 `Int` 是 32 位有符号整数**(`@int.max_value == 2147483647`),
> 在 **native 与 js 两个 target 上实测一致**。**不要**把它当 64 位推理。
>
> 这条前提是踩坑换来的:`const GEN_MAX : Int = 1 << 62` 会被**移位取模**成 `1 << 30`
> (即 `62 mod 32 = 30`),编译不报错、运行不警告,但语义已完全不同。
> 因此本库**只用显式字面量**,并选择 `2^30` —— 保证 `GEN_MAX + 1` 仍在 32 位 `Int` 内不溢出,
> 且远超实际可达的槽位复用次数。

**退役语义(I9)**:删除时若 `gens[slot] < GEN_MAX` 则 `gens[slot] += 1` 并把槽位放回 `free`;
若 `gens[slot] == GEN_MAX` 则该槽**永久退役**(代际号不变、不入 `free`、永不再分配),
使任何陈旧 `RowId` 都不可能复活。

### §2.2 `Conflict[K]` — 唯一性冲突上报

```moonbit
pub enum Conflict[K] {
  UniqueViolation(String, K, RowId)   // 该键已被一条**活记录**占用
  DuplicateInBatch(String, K, Int)    // 批次**内部**重复:更早那个成员在批次中的下标
} derive(Debug, Eq)
```

- `UniqueViolation(index_name, key, holder)`:唯一索引 `index_name` 已把 `key` 映射到**活记录** `holder`。
- `DuplicateInBatch(index_name, key, earlier)`:冲突来自**同一批次内部**的两个成员 —— `earlier` 是
  **更早那个成员在批次数组中的下标**。
  **为什么不复用 `UniqueViolation`**:那个分支的 `holder` 契约是"活记录",而批内冲突时**根本没有活记录**
  (整批被原子拒绝)。M5 曾用"该成员**将会获得**的预测句柄"填充 —— 但那是**让类型的文档契约变成假的**:
  一个从未存在过的句柄不该冒充 `holder`。用 `Int` 直接指向批次里的位置,**更准确也更可操作**。
  > 这与"不给 `Conflict` 加无意义的空变体"的初衷**不冲突** —— 那一条反对的是**冗余的 `None` 变体**,
  > 而这是一个**真实且语义不同**的失败类别。
- **故意没有「无冲突」变体**:无冲突用 `Option::None` 表达。
  加变体会 ① 与 `Option::None` 在 match 位置混淆;② 迫使调用方匹配一个不可能出现的 `Err`。
  > 两条均由探针实测(见 §9)。

### §2.3 `Rejected[K, V]` — 被拒绝的写入(冲突 + 记录归还)

```moonbit
pub struct Rejected[K, V] {
  conflict : Conflict[K]
  record   : V          // 记录原样归还,调用方不丢数据
}
```

- `insert` / `update` 失败时返回 `Err(Rejected{..})`。
- **为什么必须归还记录**:MoonBit 按值传递,`insert(v)` 消费掉 `v` 后若只返回 `Conflict[K]`,
  调用方就永久失去了这条记录(只能靠调用前自己 `clone`)。参考实现 `try_insert` 同样把元素包在
  `Err` 里还给调用者(§0.4-3)。
- `Rejected` 实现 `Debug` / `Show`,并在文档中给出"取出记录重试"的惯用写法。

### §2.4 `RegisterError` — 索引注册失败

```moonbit
pub enum RegisterError[K] {
  DuplicateName(String)           // 同名索引已存在
  UniqueViolation(String, K)      // (索引名, 冲突键)
} derive(Debug, Eq)
```

- **不静默覆盖、不部分注册**:失败时注册表与数据**完全不变**(§5 规则 2 的推广)。
- **多索引同时冲突时的报告顺序(裁定)**:当一条记录**同时**违反多条唯一索引时,
  返回**索引名升序的第一个**违反者 —— 与 `index_names()` 的排序一致,**保证确定性**。
  实现上**只在失败路径**收集全部违反者再取最小名(成功路径零额外成本,而失败是罕见路径)。
  > 若不定死,`indexes` 是哈希表,遍历序会让"同一次冲突这次报 A、下次报 B",既不可测也不可信赖。
- **为什么泛型而不是把键转成字符串**:M2 实现时曾用 `UniqueViolation(String, String)`(键的 `Show` 形式),
  代价是**两个唯一注册方法被迫要求 `K : Show`** —— 使用者必须给键类型实现 `Show` 才能注册唯一索引,
  这是不必要的负担。契约定为 **`RegisterError[K]`**,与既有 `Conflict[K]` 形状一致,键原样携带,不需要任何额外约束。
  > 该改动列入 [§12 实现与契约的已知偏差](#§12-实现与契约的已知偏差待收敛)。

### §2.5 `UpdateRejected[K, V]` — 更新失败(句柄失效 / 唯一冲突)

```moonbit
pub enum UpdateRejected[K, V] {
  StaleHandle(RowId, V?)   // 句柄已失效
  Conflict(Conflict[K], V) // 唯一冲突
} derive(Debug, Eq)
```

- **为什么不复用 `Rejected[K, V]`**:陈旧句柄**不是唯一性冲突**,硬塞进 `Conflict[K]` 会污染那个类型;
  但 `update`/`modify` 又必须同时表达两种失败,所以单独立一个枚举。
- **`StaleHandle` 的 `V?` 为什么可选**:两条路径的信息量不同 ——
  - `update(id, v)`:调用方已把待写入记录交出来,失败时**必须归还**(否则数据丢失)→ `Some(v)`;
  - `modify(id, f)`:`f` 需要旧记录才能算出新记录,句柄失效时**根本算不出来** → `None`。
  这是两条路径的真实差异;不用 `Option` 就得为它们各立一个错误类型,反而更难用。
- **`Conflict` 分支的 `V` 总有值**:冲突判定发生在新记录已在手之后,一定归还。
- 与 `insert` 的 `Rejected[K, V]` 同一条原则:**绝不吞掉调用方的数据**。

### §2.6 `Table[K, V]` — 记录表

```moonbit
pub struct Table[K, V] {
  // 私有字段见 DEVPLAN §2
}
```

**类型参数约束**:MoonBit 的结构体泛型**不能**带 trait 约束,因此 `K : Hash + Eq`(以及
有序索引需要的 `K : Compare`)**写在每个方法上**,按方法最小化。

#### §2.5.1 约束并集:一处**已知且有理由的**取舍

注册表是**异构枚举**(`HashUnique` / `SortedUnique` / `HashMulti` / `SortedMulti`),
任何遍历它的操作都同时需要 `Hash + Eq` 与 `Compare`。因此:

| 方法 | 约束 |
|---|---|
| `insert` / `remove` / `get_by` / `iter_by` / `modify` | `K : Hash + Eq + Compare` |
| `new` / `len` / `is_empty` / `get` / `iter` / `clear` / `index_names` / `index_entries` | **零约束** |

**这意味着即使只注册哈希索引,键类型也必须实现 `Compare`。** 真正做到按方法最小化,需要把有序象限的
桶操作在注册时**擦除成闭包/trait object**,代价是白盒不变量检查无法再枚举桶(而 I3/I4/I5/I7 的
逐步校验正是本库最核心的质量保障)。

**裁定:接受约束并集,换取可验证性。** 实际键类型(`String` / `Int` / 可比较的记录键)几乎都天然满足
`Compare`,而"不变量能被逐步校验"的价值远高于省掉一个约束。
> 类型擦除方案列为 **v0.2 候选**(见 [§11](#v0.2-候选本期明确不做记录以免遗忘))。

**M11 补记**:`index_entries` 只做"取名字 → 查注册表 → 报种类",不触碰键与值,所以它落在**零约束**一行。
初稿按"遍历注册表就得上约束"的惯性写成 `K : Hash + Eq + Compare`,编译器立刻给出三条
`unused_trait_bound [0053]`;在 `--deny-warn` 下这就是 CI 红。**以编译器为准**:删掉未使用的约束 ——
方法签名对调用方只会**更宽**,不是破坏。

**字段可见性**:MoonBit 的 `pub struct` 字段**默认可读公开**(会出现在 `pkg.generated.mbti` 里),
要真正私有必须逐字段写 `priv`。本库选择**字段全部 `priv`**:

```moonbit
pub struct Table[K, V] {
  priv rows : Array[V?]
  priv gens : Array[Int]
  priv free : Array[Int]
  priv order : Array[Int]
  priv indexes : Map[String, Index[K, V]]
  priv mut len : Int
  priv mut version : Int
}
```

**理由**:内部布局(`rows/gens/free/order` 的具体形态)必须能在不破坏 semver 的前提下演进;
对外只保证行为契约。mbti 中呈现为 `pub struct Table[K, V] { // private fields }`。
**代价**:黑盒 `*_test.mbt` 无法直读字段,不变量断言必须放在包内的 `*_wbtest.mbt`(见 §8)。

### §2.7 `IndexKind`:索引象限的公开名字(M11,Issue #4)

```moonbit
pub(all) enum IndexKind {
  HashUnique
  SortedUnique
  HashMulti
  SortedMulti
} derive(Debug) // Show 手写,输出裸变体名
```

- **它是什么**:私有 `enum Index[K, V]`(§3.5)的四个象限在**公开层面**的影子,由 `index_entries()`
  与索引名一起交出(`Array[(String, IndexKind)]`)。
- **为什么不塞进 `IndexStats`**:那是**字段公开**的结构体(§3.4),外部已经在构造点上依赖这四个字段,
  加"名字/种类"就是 MAJOR 破坏。独立枚举 + 独立方法,把 `IndexStats` 留在 MINOR(见 [`plans/v0.2.0.md`](plans/v0.2.0.md) 的版本判定表)。
- **`derive(Show)` 已废弃**,故 `Show` 手写;`derive(Debug)` 保留,并按 `src/extends.mbt` 的三段式
  把 `Debug::to_repr` 与 `Show::{to_string, output}` 标成 `#deprecated` + `#doc(hidden)` ——
  否则 `--deny-warn` 报 `[0079]`。

---

## §3 API 规划(v0.1.0,实现时按本节锁定签名)

> 状态:规划中。实现落定后本节的签名即为契约,并由 `pkg.generated.mbti` 与测试共同钉死。

### §3.1 构造与索引注册

| 方法 | 说明 |
|---|---|
| `Table::new() -> Table[K, V]` | 空表 |
| `Table::with_capacity(cap : Int)` | 预留容量。**语义已裁定**:预填 `rows`/`gens` 到 `cap` 个空槽,并把这些槽**全部压入 `free`(由高到低)**;因此前 `cap` 次插入按 slot `0,1,2…` 分配且不增长数组。`cap <= 0` 等价于 `new()`。空槽都在 `free` 上,所以"死槽只能是 free 或退役"(`I9` 可观测形式)依然成立 |
| `register_unique(name, project) -> Result[Unit, RegisterError[K]]` | **哈希唯一**索引(`Map[K, Int]`) |
| `register_unique_ordered(name, project) -> Result[Unit, RegisterError[K]]` (需 `K : Compare`) | **有序唯一**索引(`SortedMap[K, Int]`) |
| `register_non_unique(name, project) -> Result[Unit, RegisterError[K]]` | **哈希非唯一**索引(`Map[K, SortedSet[Int]]`) |
| `register_non_unique_ordered(name, project) -> Result[Unit, RegisterError[K]]` (需 `K : Compare`) | **有序非唯一**索引(`SortedMap[K, SortedSet[Int]]`) |
| `has_index(name) -> Bool` / `index_names() -> Array[String]` / `index_entries() -> Array[(String, IndexKind)]` | 索引枚举;`index_names` 与 `index_entries` 都按 **MoonBit `String` 序**(长度优先的 shortlex)升序,已由测试钉死;`index_entries` 同时给出每个索引的象限(§2.7)—— `index_stats(name)` 必须先知道名字,而这是拿到名字的公开途径 |

**2×2 四象限**(与主蓝本的 `hashed_unique` / `ordered_unique` / `hashed_non_unique` /
`ordered_non_unique` 一一对应):两个正交维度 —— **唯一性**(unique / non-unique)与
**有序性**(hashed / ordered)。四类各有一个注册方法,不做"含糊的三合一"。

#### 注册语义(已裁定)

所有 `register_*` 返回 `Result[Unit, RegisterError]`:

| 情形 | 行为 |
|---|---|
| 索引名重复 | `Err(DuplicateName(name))`,**不覆盖** |
| 对**非空表**注册 | **回填扫描**全部活记录,O(len);注册后立即可查 |
| 回填**唯一**索引时发现已有记录键冲突 | `Err(UniqueViolation(name, key))`,且**完全不注册**(原子,无半成品索引) |
| `index_names()` | 按名称**升序**返回(确定性,便于测试) |

> 裁定理由:"冲突不静默覆盖"是本库的整体风格,注册路径不应例外;
> 半注册状态(索引存在但只回填了一半)是最难排查的一类 bug,必须堵死。

### §3.2 写入

| 方法 | 返回 | 说明 |
|---|---|---|
| `insert(v : V) -> Result[RowId, Rejected[K, V]]` | 新记录句柄 | 冲突时**表零变更**,记录原样归还 |
| `insert_many(vs : Array[V]) -> ...` | 批量 | 先全部落库,再**每索引一次性构建**(把 N×k 次索引插入降为 k 次批量构建);**遇重复键的胜出规则须在实现时明确并测试钉死**(主蓝本是"第一个胜出",§0.4-6) |
| `insert_or_replace(v : V) -> Result[(RowId, V?), Rejected[K, V]]` | 记录句柄 + 被顶替的旧值 | **覆盖式 upsert**:恰好一条记录在新值的某个**唯一**索引上撞键 → 原地替换并**保留它的 `RowId`**(外部句柄继续有效),返回 `Ok((该 RowId, Some(旧值)))`;无冲突 → 等价于 `insert`(`Ok((新 RowId, None))`);两条**不同**记录分别在不同唯一索引上撞键 → `abort`,表零变更(三条裁定见 §3.2.2) |
| `update(id : RowId, v : V) -> Result[Unit, UpdateRejected[K, V]]` | 成功/失败 | **排除自身**的冲突检查;陈旧 id → `Err(StaleHandle(id, Some(v)))` |
| `modify(id : RowId, f : (V) -> V) -> Result[Unit, UpdateRejected[K, V]]` | 成功/失败 | 用 `f` 变换记录后重索引;**逐索引对比新旧投影键,只动真正变化的桶**(见 §5 规则 4);陈旧 id → `Err(StaleHandle(id, None))` |
| `remove(id : RowId) -> V?` | 被删记录 | 陈旧 id → `None`;**保插入序**,删除 O(len) |
| `swap_remove(id : RowId) -> V?` | 被删记录 | 同 `remove`(同样恢复槽位/索引/`len`/`version`),但用**末位换位**维护 `order` → 删除 **O(1)**;**删除后迭代序不再等于插入序**;陈旧 id → `None`,表零变更 |
| `clear() -> Unit` | — | 清空所有记录与条目,**但保留索引注册**(只清桶,不删注册)—— 否则 `clear` 之后新插入的记录会静默不被索引。**批量退役**:每个活槽的 `gen += 1` 后归还 `free`(代际耗尽的永久退役),因此 **`clear` 之前的句柄永不复活** —— 若直接清空数组,清空后插入会复用同一个 `(slot, gen)`,旧句柄就会静默命中新记录,违反 §7。清空**空表**不算真实变更,不递增 `version`(I8) |

#### §3.2.1 `update` / `modify` 的两个语义裁定

**(a) 两者都**必定**递增 `version`(即使写入的记录与原来逐字段相同)。**
理由:本库**不要求 `V : Eq`**,因此无法判断"新记录是否等于旧的";在无法判断时,按"记录被替换 = 真实变更"处理是保守且可预测的一侧。
代价:一次"内容没变"的更新会让既有迭代器 fail-fast —— 但这正是 I8 想要的语义边界:**`version` 追的是"表被改动过",不是"内容不同"**。
> 若将来为了性能想跳过"无变化"的更新,前提是先引入 `V : Eq`(会污染所有 API 的约束),收益不足以抵消代价,故不做。

**(b) 为什么 `update` 与 `modify` 两个都保留**(回应官方"能组合就不加 API"的原则)。

官方 `CONTRIBUTING.md` 说:*"If the new API can be composed with existing APIs **without losing efficiency**, it is better to use the existing APIs."*
表面上 `update(id, v)` ≡ `modify(id, fn(_) { v })`,应当砍掉一个。**但这里组合会丢东西**:

- `modify(id, fn(_) { v })` 的闭包**捕获**了 `v`。一旦返回 `Err`,调用方**拿不回这条记录**;
- 而本库从 `insert` 起就立了"**绝不吞掉调用方的数据**"这条原则(`Rejected[K, V]` / `UpdateRejected[K, V]` 都为此存在)。

**裁定:保留两个方法。** 组合损失的不是效率,是**失败路径上的数据所有权** —— 这不在官方那句话的豁免范围内。
两个方法共用同一条预检与落地路径,增量成本接近零。

#### §3.2.2 `insert_or_replace` 的三条裁定(M11,Issue #3)

**(a) 替换保留原 `RowId`,不 retire、不新建。**
这正是它相对 `remove` + `insert` 的全部价值:`remove` 会让代际号 +1,调用方手里的句柄**全部作废**;
而"同一条逻辑记录换了个值"不是一个新记录。落地方式:**直接复用 `update` 的机制** —— 先由只读判定
`replace_target` 找出"谁会被顶替"(**只有唯一索引参与**,命中按槽位归组),再跑 `update` 用的
`find_conflict_excluding(value, 该槽位)`,最后交给 `update` 也在用的落地汇聚点 `modify_impl`。
**"自己撞自己"由这一对负责**:判定阶段把命中按槽位归组,提交阶段显式排除该槽位。因此这里
**没有第二套预检**,唯一索引的桶也只被 `modify_impl` 的 `retarget` 改一遍。

**(b) 两条不同记录分别撞键 → `abort`,不新增 `Conflict` 变体。**
`Conflict[K]` 只有 `UniqueViolation` / `DuplicateInBatch` 两个变体;给第三方加一个"多记录命中"会让
**所有既有 `match` 不再穷尽** —— 那是 MAJOR 破坏。而这条路径本身就是调用方的数据问题(一个值同时
冒充两条记录的唯一键),不是可以继续处理的业务失败。`abort` 消息必须**可定位**:写明是哪两个索引、
各自撞到哪条 `RowId`;两个索引按**名字升序**取,保证同一状态永远给出同一段文本(与 §7 的冲突上报
口径一致)。测试上:黑盒只能验证"它会 abort"(`panic` 前缀测试),**消息本身**由包内的
`src/table_wbtest.mbt` 直接断言只读判定函数。

**(c) 原子性按 `update` 的标准,失败路径表零变更。**
只读判定 → 排除自身的冲突预检 → 落地,三步之前表**完全没动**;`abort` 路径同样在落地之前。
**非唯一索引不参与"谁被顶替"** —— 一个桶可以有很多记录,它命名不了受害者;它只在落地时按新值重建。

> **为什么函数体里还留着一个"看起来永不触发"的 `Err` 分支**:只要判定函数是对的,`Replace` 分支的
> 预检必定返回 `None`。保留它不是冗余逻辑,而是**降级路径** —— 判定若出现回归,结果是 `update`
> 语义的 `Err(Conflict)`(表仍零变更),而不是把 I5 写坏。这一点由 `table_wbtest.mbt` 的
> "replace_target agrees with update's excluding-self pre-check" 钉住。

### §3.3 查询

| 方法 | 返回 | 说明 |
|---|---|---|
| `get_by(name : String, key : K) -> (RowId, V)?` | 命中记录的身份 + 值 | 非唯一索引上返回**桶内槽位号最小**的一条;该选择**确定但不跨操作稳定**,要全部命中请用 `iter_by` |
| `iter_by(name : String, key : K) -> Iter2[RowId, V]` | 该键下所有记录 | 唯一索引上产出 0 或 1 条(API 统一);**顺序 = 槽位号升序**(桶为 `SortedSet[Int]`) |
| `range_by(name, lo, hi)` (需 `Compare`) | **双闭区间 `[lo, hi]`** 内的记录 | 有序索引;**本库增量**(主蓝本无 range API) |
| `range_half_open_by(name, lo, hi)` (需 `Compare`) | **半开区间 `[lo, hi)`** 内的记录 | 同上 |
| `iter_asc_by(name)` / `iter_desc_by(name)` | 按索引键升/降序遍历全部记录 | 同上。**不需要 `K : Compare`** —— 实现只走 `SortedMap` 的迭代器;索引是否有序由 §7.1 的运行时检查负责 |
| `get(id : RowId) -> V?` | 按句柄取记录 | 陈旧 id → `None` |
| `contains(id : RowId) -> Bool` | — | |
| `len() -> Int` / `is_empty() -> Bool` | — | |
| `iter() -> Iter2[RowId, V]` | 插入序遍历 | fail-fast(比照 `version`) |

> **范围查询返回惰性迭代器**,不预先收集成数组(避免大区间一次性物化)。

#### §3.3.1 为什么 `range_by` 是双闭区间(语义裁定)

初稿把 `range_by` 定为 `[lo, hi)`、另设 `range_inclusive_by` 为 `[lo, hi]`。**实测推翻了这个设计**:
core 的 `SortedMap::range` / `SortedSet::range` 本身就是**双闭区间 `[lo, hi]`**
(在键 `1,2,3` 上 `range(1, 2)` 返回 **2** 条)。

裁定:**跟随平台语义**。
- `range_by` = `[lo, hi]`,**直接转发** `SortedMap::range`,零额外代价、零意外
  (MoonBit 用户读我们的文档时默认会按 core 语义理解);
- 半开区间另立**名字明确**的 `range_half_open_by`,实现为"闭区间结果过滤掉键 `== hi` 的条目";
- **删除** `range_inclusive_by` —— 与 `range_by` 语义完全重合,留着只会造成歧义。

> 教训:"两个名字相近的方法"如果底层只支持一种语义,不要制造语义重叠;
> 要么跟随平台,要么起一个不会误读的名字。

> **查询统一返回 `(RowId, V)` 二元组**,理由:一次调用同时给出**身份**与**值**,不丢信息、
> 不需要调用方决定"要不要再取一次",也避免为"只要值"和"只要身份"各开一套方法把 API 面积翻倍。
> **代价**:MoonBit 不能返回元素内部的引用,取 `V` 是一次拷贝(记录内的容器是共享引用,通常不贵);
> 若将来 profiling 证明热循环里这次拷贝有代价,再加 id-only 变体(v0.2 候选)。

### §3.4 诊断(拿分点,也是自测手段)

| 方法 | 说明 |
|---|---|
| `verify_invariants() -> Result[Unit, String]` | **公开**的白盒自检:校验 I1–I9 + 索引不变量。**首个违反者即返回**,消息里指明**违反了哪一条 + 出问题的槽位/键**(例如 `"I5: unique index \"email\" holds 2 slots under key \"a@b.c\""`) |
| `index_stats(name : String) -> IndexStats` | 诊断统计。`IndexStats { buckets, entries, longest_bucket, average_bucket }`(**空索引全 0,含 `0.0`,不除零**) |
| `index_entries() -> Array[(String, IndexKind)]` | 已注册索引的"名字 + 象限"清单,按名称升序(与 `index_names` 同序)。`index_stats(name)` 需要先知道名字,这是拿到名字的**公开**途径(Issue #4);`IndexKind` 见 §2.7 |

> `verify_invariants` 是**公开 API**而非仅测试辅助:调用方可在自己的断言里使用它。
> **约束**:公开入口是 `verify_invariants[K : Eq + Debug, V]` —— `Eq` 用于比较键,`Debug` 用于把键渲染进消息。
> 内部拆成零约束的 `verify_storage`(I1/I2/I6/I9)与需要键能力的 `verify_indexes`(I3/I4/I5/I7)。
>
> **消息格式**统一为 `"<不变量编号>: <定位信息>"`(如 `I4: bucket 999 of index "lo" holds slot 0, whose record projects to 1`);
> 注册表记账类问题无编号,前缀写作 `registry:`。
>
> **复杂度**:O(桶数 × len) —— 对**诊断 API** 足够;若将来要在热路径调用,可先建反向索引(目前不做,避免为诊断路径增加分配)。
>
> **返回 `Result` 而不是 `Bool` 的理由**:一个只会说"false"的校验器,对它的目标用户(需要定位一致性问题的调用方)
> 几乎没有价值 —— 而"公开自检"的全部意义就是**可诊断**。`Result` 的 `Err` 携带首个违反点的描述。
>
> **与测试侧校验器的关系**:`property_wbtest.mbt` 的 `check_invariants` 应**委托**给这个公开实现(避免两份实现漂移),
> 但**"非空转"元测试必须保留** —— 它们是对校验器本身的独立检验,委托之后反而更重要。
> 这与 bimap 的 `check_bijection`(仅测试内)不同 —— 多索引的一致性更难自查,值得公开。

### §3.5 索引表示(2×2 四象限)

| 唯一性 × 有序性 | 存储类型 | 说明 |
|---|---|---|
| 唯一 + 哈希 | `Map[K, Int]` | 键 → 槽位号 |
| 唯一 + 有序 | `SortedMap[K, Int]` | 支持范围查询 |
| 非唯一 + 哈希 | `Map[K, SortedSet[Int]]` | 桶为**有序集合** |
| 非唯一 + 有序 | `SortedMap[K, SortedSet[Int]]` | 支持范围查询 |

注册表形态(**待实现时用探针确认后再锁定**):

```moonbit
enum Index[K, V] {
  HashUnique(IndexMeta[K, V], Map[K, Int])
  SortedUnique(IndexMeta[K, V], SortedMap[K, Int])
  HashMulti(IndexMeta[K, V], Map[K, SortedSet[Int]])
  SortedMulti(IndexMeta[K, V], SortedMap[K, SortedSet[Int]])
}
```

> **索引条目只存槽位号 `Int`,不存 `RowId`**。代际号只用于校验**外部传入**的句柄;桶内条目由本库在
> 汇聚点内维护,按构造永远指向当前活记录,无需再存一份代际号(省内存,也避免"桶内代际"与
> `gens` 两份真源不一致)。这是与"存全量 `RowId`"相比的关键简化。

### §3.6 语义裁定:为什么没有 `update_unindexed`

主蓝本把更新拆成两条路径:`update_by_*`(闭包只拿到**未索引字段**,O(1),不碰索引)与
`modify_by_*`(闭包拿到整条记录,需重建索引)。这个拆分在 Rust 里是**类型级**的保证
(`get_mut_by_*` 只返回未索引字段的 `&mut`)。

**MoonBit 无法返回指向数组元素的 `&mut` 投影**,该拆分无法在类型层复现。本库的替代方案:

- 只提供 `modify(id, f : (V) -> V)`;
- 实现内**逐索引对比新旧投影键**:键未变的索引**完全不动**(不删桶、不加桶),即自动获得
  `update_unindexed` 的 O(1) 效果;
- 索引不变量由"新记录重新投影"保证,不存在"调用方拿到 `&mut` 后破坏不变量"的路径。

> 代价:即使只改一个未索引字段,也要构造一条新记录(`f` 是纯变换 `(V) -> V`)。
> 收益:API 只有一条更新路径,少一个能破坏不变量的入口。

---

## §4 核心不变量(属性测试的靶子)

```
I1  order 中每个槽位都是活记录,且无重复;且 positions 是它的逆(positions[order[i]] == i,死亡槽位为 -1,S8b 起双向校验)
I2  活记录数 == len == order.length()
I3  每条索引的每个桶内,槽位无重复(桶为 `SortedSet`,结构上已保证;仍作交叉校验)
I4  桶内每个槽位 s 满足 (idx.project)(rows[s]) == 桶键
I5  唯一索引的每个桶长度 <= 1
I6  free 中无重复,且 free 与活记录集合不相交
I7  每个活记录恰好出现在每条索引的对应桶中(无遗漏、无悬挂)
I8  version 仅在真实变更时递增(update/modify 一律视为真实变更,见 §3.2.1)
I9  退役槽位永不回到 free(代际号达上限的槽位被永久移除,见 §3.4)
```

**I5 与 I7 必须成对校验**:I7 防"漏",I5 防"多"。

#### §4.1 I3 / I5 是**结构性保证**,不是可破坏状态(M5 实测结论)

| 不变量 | 为什么构造不出违反 | 校验器的价值 |
|---|---|---|
| **I3**(桶内槽位无重复) | 非唯一桶是 `SortedSet[Int]`,`add` 幂等 —— 重复槽位**不可表达** | 防御:一旦有人把桶换成数组/多重集,立刻拦住 |
| **I5**(唯一桶 ≤ 1) | 唯一象限存 `Map[K, Int]` / `SortedMap[K, Int]`,`Index::buckets` 对唯一变体**必然**返回 `(key, [slot])`(长度 1) | 同上 |
| **I7 的"覆盖"半** | I3 + I4 都通过后,"每条活记录恰好出现一次"只剩**计数**这一个自由度 | 计数半可触发,覆盖半是防御 |

**裁定:M5 提出的"I5 与 I7 各一条可定位测试"这一要求基于错误前提** —— 它们无法被白盒手段破坏。
落地方式改为:

1. I3 / I5 **保留为防御性交叉校验**(它们防的是**未来的表示层变更**,不是当前代码的 bug);
2. 用一条**结构钉子**测试钉死"唯一象限每桶恒 1 槽",并**同时**断言非唯一象限**确实存在 2 槽桶**
   —— 防止这条断言因夹具巧合而空转;
3. 消息定位测试覆盖**可达**的 I4 / I6 / I7(计数半)。

> **原则:不为"可测性"付真实代价。** 让 I5 可被破坏的唯一办法是把唯一象限也换成集合类型,
> 代价是 `holder` 查询从 O(1) 退化为 O(log k)(或需额外辅助映射) —— **明确不做**。
> 一个**不可表达**的错误状态,不需要为了让测试能构造它而变得可表达。
> I5 是探针实测漏洞反推出来的:最初的校验只查 I3/I4,`update` 又漏了冲突检查,
> 结果一次"更新成已占用的唯一键"让唯一桶出现两个持有人,而校验仍返回 true。

---

## §5 变更汇聚点与三条高危路径

**汇聚点**:`insert_impl` / `remove_impl` / `modify_impl` / **`clear_impl`** 是**唯一**允许同时触碰
`rows` + `order` + `positions` + `indexes` + `gens` + `free` 的地方。

> **第四条是 M1 实施中补上的**:`clear` 必须同时触碰这四个结构,而循环调用 `remove_impl` 会因
> `order` 的 O(n) 压缩退化成 **O(n²)**。`clear_impl` 是 O(n) 批量退役路径,角色等同 bimap 的 `retain`。

1. **`update` 必须做"排除自身"的冲突检查** —— 记录更新成自身已有的唯一键不算冲突。
2. **冲突检查在任何变更之前完成** —— 返回 `Err` 时表必须与调用前等价。
3. **删旧桶与加新桶之间不得有可观察中间态** —— 键不变时走快路径。
4. **`modify` 必须先完成全部唯一性预检,再一次性提交索引变更** —— 主蓝本 `modify_by_*` 的顺序是
   "先删旧键 → 再插新键 → 失败则 panic",**panic 时索引已半更新、容器脏掉**(§0.4-1)。
   本库的顺序固定为:**算新投影 → 对每个唯一索引预检(排除自身)→ 全部通过后统一落地**。

---

## §6 复杂度

| 操作 | 复杂度 |
|---|---|
| `insert` | O(I + Σ桶代价),I = 索引数 |
| `get_by` | 均摊 O(1) |
| `range_by` | O(log n + k) |
| `remove` | **O(len + I + Σ log 桶)** —— 见下方警告,`len` 项来自 `order` 保序压缩 |
| `swap_remove` | **O(I + Σ log 桶)** —— `order` 只做一次末位交换 + 两次 `positions` 写,无 `len` 项 |
| `update` / `modify` | O(I + Σ log 桶);**键未变的索引不参与** |
| `insert_many` | O(n·I + n·Σ log 桶) |
| `iter` | O(len) |
| `verify_invariants` | O(桶数 × len) —— **诊断 API,不在热路径** |
| 空间 | O(len + Σ索引条目) |

> ⚠️ **`remove` 的 `O(len)` 是 M6 基准实测抓出来的,原表写 `O(I + Σ桶长)` 是错的。**
> 根因:`order`(**插入序**)是一棵普通数组,删除后需要**原地压缩** → O(len)。
> 实测 `remove` 比 `insert` 贵 **20–44×** 且随 n 增长。
>
> **这是有意的取舍,不是 bug**:把 `order` 换成"交换删除"(`swap_remove` 风格)可把删除降到 O(1),
> 代价是**牺牲插入序的稳定性**(被删元素的空位由末尾元素填补)。
> 这正是参考实现 `indexmap` 对外的 `shift_remove` / `swap_remove` 二分 —— v0.2 两条都提供:
> `remove` 等价于 `shift_remove`(**保插入序**,O(len)),`swap_remove` 用末位换位换来 **O(1)**
> 但**放弃插入序**。名字已写明差异,调用方按"要不要插入序"二选一(裁定见 §13 R3)。

---

## §7 错误语义

- **唯一冲突不覆盖**:`insert` / `update` 返回 `Err(UniqueViolation(...))`,且**返回前零变更**。
- **陈旧句柄**:`remove`/`get` 返回 `None`,`update` 返回 `Err`;**不 panic、不误伤新占用者**。
#### §7.1 三类"失败"必须分开对待(裁定)

| 类别 | 例子 | 语义 | 处理 |
|---|---|---|---|
| **可预期的运行时条件** | 唯一冲突、陈旧句柄、键查不到 | 正常业务结果 | 返回 `Err` / `None` / **空迭代器**;**绝不 panic** |
| **编程错误:名字写错** | 查询一个从未注册的索引名 | 调用方 bug | **`abort`** |
| **编程错误:问题问错了** | 在**哈希**索引上做 `range_by` / `iter_asc_by` / `iter_desc_by` | 该索引**根本没有序**,不存在"空结果"这一说 | **`abort`** |

**关键区分**:"空结果"只应表示"**查得到,但没有**"。若索引名不存在、或该索引是哈希索引(无全序),
返回空会把**调用方的 bug** 伪装成"没有数据",让人在生产环境里排查很久。故这两类一律 `abort`。

> **与"绝不 panic"原则的关系(不是矛盾)**:本库"绝不 panic"针对的是**可预期的运行时条件**
> (冲突、陈旧句柄、未命中)—— 那些绝不能靠进程崩溃来表达。**编程错误**是另一类:它在开发期就该暴露,
> 且没有合理的返回值可以表达("返回空"本身就是在撒谎)。官方 core 在同类情形下同样 `abort`
> (例如 `m[k]` 取缺失键会 panic 且 `try/catch` 抓不住 —— 见 [`MOONBIT_REF.md`](MOONBIT_REF.md))。

**边界要一并测到**:
- `lo > hi` → **空**(合法的"空区间",不是编程错误);
- `range_half_open_by(lo, hi)` 当 `lo == hi` → **空**;
- 空表 / 有序索引存在但无匹配 → **空**。

> **落地归属**:M2 的 `get_by` / `iter_by` 目前对未知索引名返回空(与上表冲突),已登记进 [§12](#§12-实现与契约的已知偏差待收敛),
> 由 **M4 统一收敛**(M4 本来就要动这组查询)。

---

## §8 Trait 实现规划

| Trait | 规划 |
|---|---|
| `Debug` / `Show` | `RowId`、`Conflict`、`Table`(手写 `Show`,不用 deprecated 的 `derive(Show)`) |
| `Default` | `Table::new()` |
| `Eq` | `Table` 为**记录集合**语义;索引是派生视图,**不参与相等性** |
| `Hash` | 与 `Eq` 一致(顺序无关正则形,比照 bimap 的 sort-fold) |
| `ToJson` / `FromJson` | JSON 往返。**语义已裁定**:① **索引不参与序列化**(投影是运行时闭包,无法序列化);② `from_json` 只恢复**记录**(`rows` + `gens` + `order`),返回的表**索引注册表为空**;③ 反序列化后由调用方用 `register_*` **回填重建索引** —— 这正好复用 §3.1 已有的"对非空表注册即回填"语义,**两处机制自然咬合,不新增概念**;④ 形如 `{"records": [...]}`,记录按插入序写出 |
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

### v0.2 候选(本期明确不做,记录以免遗忘)

- schema → MoonBit 源码生成器:把运行时闭包投影静态展开,获得等价 derive 的零开销
  (主蓝本靠过程宏,我们靠代码生成)。
- 密集整数键的 SparseSet 式加速(参照 bevy `ComponentSparseSet` 的 dense+sparse 双数组)。
  **M11 砍尾(2026-10-20)**:基准里哈希桶并不慢,这是**没有实测痛点**的推测性优化,按
  [`plans/v0.2.0.md`](plans/v0.2.0.md) §四「从尾部砍」;相应地**没有开 Issue** —— 它不是实测到的
  问题,开了就是凑数。
- 批量重建索引 `rebuild_index(name)` / 延迟建索引。
- **约束擦除**:把有序象限桶操作在注册时擦除成闭包/trait object,使 `insert`/`remove` 只需
  `K : Hash + Eq`。代价见 §2.5.1 —— 需要先解决"擦除后如何继续逐步校验 I3/I4/I5/I7"。
- ~~查询的 id-only 变体~~:M8 实测后**不做** —— 最终形状只有 1.70×,未达开工前写死的 2× 门槛(§13 R2)。

### 上游能力跟踪(不是我们的债,但影响我们的实现)

| 缺口 | 影响 | 消除条件 |
|---|---|---|
| core 的 `SortedMap` **没有反向迭代器** | `iter_desc_by` 必须**先物化键序**再倒着走(内存 O(#桶));`range_by` / `range_half_open_by` / `iter_asc_by` 都是惰性的,不受影响 | core 为 `SortedMap`(或 `Iter2`)提供 `rev` / 反向迭代器后即可改为惰性。已记入 `CHANGELOG.md` Notes |

#### `insert_many` 重复唯一键的裁定(M5 落地)

**整批原子失败**:`insert_many(vs) -> Result[Array[RowId], Rejected[K, V]]`。

- **先**对全部记录做唯一性预检(**含批量内部互相冲突**),**全部通过后**才逐条插入;
- 任一条冲突 → `Err(Rejected{..})`,**整批零变更**,并把**冲突的那条记录**原样归还;
- **不采用"第一个胜出"**(参考实现的行为)——那是一种**静默的胜出规则**,与本库"冲突不静默覆盖"的整体风格冲突;
- **调用方不会丢数据**:MoonBit 的 `Array` 是引用类型,传入的数组仍在调用方手里。

> ⚠️ **这是与参考实现的一处语义偏离**(它 `FromIterator` 是"第一个胜出")。因此这条**不可差分**,
> 已在 `tools/diffgen/README.md` 的"不可差分清单"里登记,由本库自己的测试钉死。

---

## §12 实现与契约的已知偏差(待收敛)

> **台账纪律**:SPEC 是**契约**,代码是**实现**。两者出现差距时,要么改代码、要么改契约,
> **不允许差距停留在口口相传里**。每条偏差登记在此,并在对应里程碑关闭。
> 审核会话负责维护本表;执行会话不得自行删除条目。

| # | 契约(§) | 当前实现 | 关闭于 | 状态 |
|---|---|---|---|---|
| 1 | §2.4 `RegisterError[K]`,`UniqueViolation(String, K)` | 已实现为泛型,键原样携带,**两个唯一注册方法不再要求 `K : Show`** | M3 | ✅ 已关闭(`7199afa`) |
| 2 | §3.1 `has_index(name) -> Bool` | 已实现 | M3 | ✅ 已关闭(`7199afa`) |
| 3 | §3.1 `Table::with_capacity(cap : Int)` | 已实现(语义见 §3.1) | M3 | ✅ 已关闭(`7199afa`) |
| 4 | §3.3 `contains(id : RowId) -> Bool` | 已实现 | M3 | ✅ 已关闭(`7199afa`) |

| 5 | §7.1 未知索引名 → `abort` | 已收敛:`get_by` / `iter_by` 及四个有序查询对**未知索引名**与**在哈希索引上做有序查询**一律 `abort`;判定抽成可测谓词(`has_index` 黑盒 / `Index::is_ordered` 白盒) | M4 | ✅ 已关闭(`d9590f6`) |

> **台账当前为空。**

> 下次出现契约与实现的差距时在此追加,不要另开一处记录。

> 偏差必须**逐条关闭或显式废弃**:若某条最终决定不做,把它移到 §11(明确不实现)并在此记一行
> "废弃(理由)",而不是静默删除。
---

## §13 v0.2 查询与删除的裁定(M8)

> 三条裁定都**先做实验再定**,原始数据见 [`bench/README.md`](../bench/README.md)。本节只压结论与理由。

### R1 慢在哪(2026-10-19,n = 20 000,同进程)

- `iter_by` 胖桶(≈1 250 条/桶)公开路径 4.29 s / 2 500 万次记录访问;直接遍历 `SortedSet` 桶 + `rows[slot]` 1.40 s → **2.96×**。`range_by` 宽区间(5 000 条)3.32 ms vs 0.96–1.06 ms → **3.2–3.5×**。
- 所以"每条记录一次 `(RowId, V)` 拷贝"确有代价,但**不是主因**:整表 `iter()` 与直接走 `order` 相差 **30×**,差距主要来自 ① 每次查询整桶 `to_array()` + `Iter2` 元组/闭包 ② `next() -> RowId?` 的 `Option[RowId]` 每元素装箱(≈33 ns)。
- 裁定:差距 ≥2×,**继续**做 id-only 视图;但 API 形状必须避开每元素装箱 —— 实测 `Iter[RowId]` 仅 1.55×、`next() -> RowId?` 游标 1.65×,**都达不到 ≥2× 的出口门槛**,故不采用游标形状(见 R2)。

### R2 id-only 视图:**不做**(被数据否决,2026-10-19)

- 候选:a) 查询族 6 个方法全加 id 版;b) 只加最热的两条路径(回调式 `each_id_by` / `each_id_range_by`,+2 方法 +0 类型);c) 引入 id 视图/游标类型。取 **不做**:公开面零变化。
- **可复现倍数 1.70×**(最终形状:绕开 `Iter2` 元组、直接走桶迭代器 + 回调,20 000 次 × 1 250 条/桶)。R1 记录的 2.9–3.1× **未能在最终形状上复现,以 1.70× 为准**。门槛 2× 是测量**之前**定下的,不因结果接近而改。
- **根因不是 `Iter2` 元组,而是 core `Iter` 协议逐元素装箱(≈30 ns/元素)**:它抵消了省下的桶拷贝——去掉整桶 `to_array()` 反而 **0.87–0.96×**(多一层闭包),宽区间唯一桶 1.23×。回调形仍要走 `Iter[Int32]`,1.70× 已接近这条路的上限。
- 成本账:即便达标,也要**永久**多 2 个公开方法、2 份文档、2 组测试、2 条语义约定(回调不能 `break`、回调期间改表要 `abort`)。为未达门槛的收益付这份账,不划算。
- **复活条件**(两者都不成立前不再重提):① core 提供**不装箱**的遍历协议;② 本库把非唯一桶换成**数组表示**——但那会让删除从 O(log k) 退化到 O(k),已被 R3 否决。
- 已落地(不属于 R2):`Table::get_by` 改由 `Index::first_slot` 直取桶内最小槽,**不再物化整桶**;胖桶 21×,bench `get_by-unique` 1.34×。

### R3 删除:`swap_remove` + `positions`,保留保序 `remove`

- 方案 a) 新增 `swap_remove`:只重排 `order`(末位换到空位),**不搬 `rows`**,存活 `RowId` 全部保持有效。
- 方案 b) `prev`/`next` 两个 Int 数组维护插入序:现有 `remove` 也能 O(1),但 ① 所有迭代变指针追逐(热路径变慢) ② 失去"`order` 是数组、不可能有环"的免费保证,`verify_storage` 要加防环 ③ 每存活槽多 8 B。否决。
- 选 a):`swap_remove` 配 `positions : Array[Int32]`(slot → `order` 下标),删除 = 末位换位 + 弹尾,真 O(1);没有 `positions` 时删完还得 O(n) 找位,那就不算优化。
- 代价:`positions` 每槽 +4 B,`insert` / `remove` 各多一次写;`swap_remove` 后迭代序**不再等于**插入序(名字已写明),需要插入序时仍用 `remove`。
- **`positions` 常驻,不做惰性构建**(S8b 决定):长度 = `rows.length()`,死亡槽位填 `-1` 作哨兵,由四个汇聚点维护。惰性构建会引入"有时存在有时不存在"的状态、每次 `insert` 一次分支判断,复杂度换不来收益;常驻的代价(每槽 +4 B、`insert` 多一次数组写)相对已有的每索引桶写入是噪声。

> **更正(2026-10-19)**:S8b 当时判断「常驻的代价相对已有的每索引桶写入是噪声」——**这条判断是错的**,
> S8c 实测推翻了它:保序 `remove` 因为要在搬动每个元素时多写一次 `positions[moved]`,在 n = 20 000 时
> 从 34.8 µs/op 升到 54.5 µs/op(**+57%**;k = 2/4/8 为 +40% / +26% / +31%,slot-reuse storm +41%)。
> 机制可算:中间删除搬 ≈10 000 项 × 每次多一次数组写 ≈2 ns ≈20 µs,正好等于差值。**`insert` 侧确实持平**
>(−2%~+7%,噪声区间)—— 错在只量了 `insert` 就下了「代价是噪声」的结论。
>
> **仍然选择常驻,但理由换成了数据而非断言**:
> ① 保序 `remove` 本身就是 O(n),而 O(1) 的替代(`swap_remove`)已经提供;
> ② 惰性构建要给核心存储引入「有时存在、有时不存在」的第二个状态,四个维护点、校验器、迭代器全部要分支,
>    在 10/31 之前引入第二状态的风险高于收益;
> ③ 代价只由**需要插入序**的调用方支付。
>
> **复活条件(留给 v0.3)**:若出现「只做保序删除、且对常数敏感」的场景,按惰性构建实现 —— 首次调用
> `swap_remove` 时 O(n) 建表,此后 `order_remove` 用**循环外提升的分支**(两个循环变体,而非循环内逐次判断)。
> 届时必须用 `bench/` 复测「纯 `remove` 用户是否真的回到 34.8 µs/op」,不得只凭本段论证。
- **实现状态(S8c,2026-10-19)**:`Table::swap_remove` 已落地;保序 `remove` 语义与签名不变。实测(n = 20 000,k = 1)`remove` 54.5 µs/op → `swap_remove` **1.49 µs/op(36.7×)**;三档 n = 1 000 / 10 000 / 100 000 为 1.7× / 27.9× / 303×,`swap_remove` 在 0.82–0.90 µs 持平。

> **出口条件的口径(重要)**:M8 写的是「`swap_remove` ≥ 5×」,而**倍数依赖 n** —— n = 1 000 时只有 1.73×
>(绝对值还不到 1 µs,两家共同的固定开销摊薄后比值本就失真),n = 10 000 起为 25× 以上,n = 100 000 达 314×
>(独立复跑:1.68 / 19.13 / 267.6 µs 对 0.970 / 0.759 / 0.852 µs)。所以正确的表述是
> **「`remove` 随 n 线性增长、`swap_remove` 持平 ⇒ 比值随 n 增大」,而非「固定倍数 ≥ 5×」**。
> 基准表已按 n 分档呈现,不报单一「最好看的数字」。`positions` 的代价也已实测:`insert` 持平(0.95 → 0.98 µs/op),`remove` 因搬动时同步写 `positions` 从 34.8 升至 54.5 µs/op(+57%)——只由需要插入序的调用方支付。数据见 `bench/README.md`。

## 14. 文档门禁:warning 0074 `missing_doc`(M10)

- **开关**:告警 **74 / mnemonic `missing_doc`**("Missing documentation for public definition"),在 moon 0.1.20261012 默认 **off**。
  默认 warn list 里就是 `-74`,所以裸 `moon check` 从不报它。开启写法是 `--warn-list "+74"`(或 `--warn-list "+missing_doc"`)。
- **落地方式**:写进包的 `src/moon.pkg` 顶层 `warnings = "+74"`,而不是 CI 命令行 —— 这样本地 `moon check`、CI、
  以及下游任何使用者拿到的都是同一个门槛,不存在"CI 开了本地没开"的漂移。CI 的 `moon check --deny-warn --target all`
  因此自动覆盖它(步骤未改命令,只加了注释)。
- **与默认集合并,不覆盖**:包的 `warnings` 与编译器默认列表叠加(实测 `0001` 与 `0074` 同时触发)。
  `options("warn-list": ...)` 是**弃用**写法(`[0027] deprecated_syntax`),不要用。
- **只管公开面**:实测 `priv struct` / `priv fn` 缺文档**不报** 74,只有 `pub` 定义报。正好符合 SPEC 的意图。
- **当前状态**:开启后四后端 `moon check --deny-warn --target all` = **0 warnings 0 errors**,即公开 API 本来就 100%
  有 `///` 文档,M10 没有补任何一条注释;门的价值是**防回归**(以后新增 `pub` 项漏文档会在 CI 直接红)。

## 15. 形式化验证(M10-B)

### 15.1 结论先行

- `moon prove` 在本机**仍不可用**,但原因已从「没装求解器」收窄到「why3 与 z3 的调用/解析层」:
  求解器能被发现,WhyML 能正确生成,**每一个**目标都返回 `Failure (no prover available)`
  (attempts 记录为 `Z3: Failure (high failure)`)——**包括 `ident'vc : eq x x = True` 这种恒真目标**。
  因此这不是「目标太难」,是链路断了。
- 作为替代,[`proofs/`](../proofs/) 目录改用**直接写 SMT-LIB 交给 z3** 做形式化校验,已通过两条:
  `swap_remove` 后 `positions` 仍是 `order` 的逆;`clear()` 批量退役后陈旧 `RowId` 不复活。
  `powershell -NoProfile -File proofs/run.ps1` 可复跑,输出 `all proofs checked`。

### 15.2 moon prove 的进场方式(已实测)

- **开关**:`moon.pkg` 里写 `proof_enabled = true`。写成 `proof = true` 会报
  `Unexpected key 'proof' found in moon.pkg.`;写成 `options("proof": true)` 会被接受但只是把选项
  透传给 moonc,**不是**开关(照旧静默跳过该包)。
- **求解器**:`Z3PATH` 指向 exe 与「把 z3 放到 PATH」两种方式都能被发现(带不带 `.exe` 后缀均可)。
- **Why3 不需要用户安装**:二进制随工具链分发(`~/.moon/lib/why3` 有 `why3.cmxa` / `why3server.exe`,
  `~/.moon/share/why3` 有 `drivers/` 与 `provers-detection-data.conf`);`moonc-prove.exe` 自带 `-emit-only`。
- **z3 的获取**:不需要 GitHub(API 返回 403)。`python -m pip download z3-solver==4.12.6.0 --no-deps`
  得到 wheel,`tar -xf` 解开后 `z3.exe` 位于 `<pkg>-*.data/data/bin/z3.exe`。

### 15.3 已排除的变量

| 变量 | 试过的取值 | 结果 |
|---|---|---|
| z3 版本 | 5.3.1 / 4.13.4 / 4.12.6(4.12.x 是内置检测数据 `provers-detection-data.conf` 支持的最高版本) | 均 `high failure` |
| 发现方式 | `Z3PATH` 指到 exe / 指到无后缀路径 / 仅靠 PATH | 均 `high failure`(生成的 `why3.conf` 一律登记为 `[partial_prover]`) |
| 目标难度 | 官方文档二分查找示例(37 个目标)/ 最小恒等函数(1 个目标 `eq x x = True`) | 均 `high failure` |
| z3 自身 | 命令行直接跑;按检测数据里的原始参数(`-smt2 -t:5 sat.random_seed=42 … -st`)经 `why3cpulimit.exe` 调用 | 均正确返回 `unsat` |

补一条可复现的细节:`moon prove` 每次都会**重写** `_build/verif/why3.conf`(手工改 `magic` 值会被覆盖),
所以「改配置绕过」不成立。

### 15.4 替代方案与它的边界

`proofs/` 下的证明验证的是**设计所依赖的逻辑关系**,不是 MoonBit 源码:代码是否忠实实现模型,
仍由单元测试 / 属性测试 / 对拍测试负责。这层边界写在 [`proofs/README.md`](../proofs/README.md) 里。

### 15.5 没有做的事

- 没有对任何一条不变量声称「语言侧不支持」——故障在 why3↔z3,不在 MoonBit 的证明语法。
- 没有弱化任何不变量断言来换测试通过。
- 没有把 SMT 证明写成「已验证代码」;`proofs/` 不进 CI(它需要 z3,而 CI 镜像里没有)。

### 15.6 下一轮若接着做

1. 找一个 why3 能正常驱动的 z3(或换 alt-ergo / cvc5 的完整 CLI),再跑 `eq x x` 这个最小目标;
   它一通,才谈得上把 `proofs/*.smt2` 迁移成 `.mbtp` 里的 predicate。
2. 语言侧大概率还要给循环补 `missing_invariant`(告警 38)/ `missing_reasoning`(39) 注解——
   两者默认 off,说明语言支持但需要显式写,不是「`moon prove` 一跑就过」。
