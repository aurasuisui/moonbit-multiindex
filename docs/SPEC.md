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
  UniqueViolation(String, K, RowId)
} derive(Debug, Eq)
```

- `UniqueViolation(index_name, key, holder)`:唯一索引 `index_name` 已把 `key` 映射到活记录 `holder`。
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

### §2.4 `Table[K, V]` — 记录表

```moonbit
pub struct Table[K, V] {
  // 私有字段见 DEVPLAN §2
}
```

**类型参数约束**:MoonBit 的结构体泛型**不能**带 trait 约束,因此 `K : Hash + Eq`(以及
有序索引需要的 `K : Compare`)**写在每个方法上**,按方法最小化。

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

---

## §3 API 规划(v0.1.0,实现时按本节锁定签名)

> 状态:规划中。实现落定后本节的签名即为契约,并由 `pkg.generated.mbti` 与测试共同钉死。

### §3.1 构造与索引注册

| 方法 | 说明 |
|---|---|
| `Table::new() -> Table[K, V]` | 空表 |
| `Table::with_capacity(cap : Int)` | 预留容量 |
| `register_unique(name, project) -> Unit` | **哈希唯一**索引(`Map[K, Int]`) |
| `register_unique_ordered(name, project)` (需 `K : Compare`) | **有序唯一**索引(`SortedMap[K, Int]`) |
| `register_non_unique(name, project) -> Unit` | **哈希非唯一**索引(`Map[K, SortedSet[Int]]`) |
| `register_non_unique_ordered(name, project)` (需 `K : Compare`) | **有序非唯一**索引(`SortedMap[K, SortedSet[Int]]`) |
| `has_index(name) -> Bool` / `index_names() -> Array[String]` | 索引枚举 |

**2×2 四象限**(与主蓝本的 `hashed_unique` / `ordered_unique` / `hashed_non_unique` /
`ordered_non_unique` 一一对应):两个正交维度 —— **唯一性**(unique / non-unique)与
**有序性**(hashed / ordered)。四类各有一个注册方法,不做"含糊的三合一"。

**注册语义(待锁定)**:重名注册应报错还是覆盖?**倾向**:返回 `Result[Unit, ...]`,
重名报错(与"冲突不静默覆盖"的整体风格一致)。

**对已有数据注册索引**:注册时表非空则必须回填扫描(`insert` 全部活记录),复杂度 O(len)。
须在 SPEC 中明确,并由测试钉死。

### §3.2 写入

| 方法 | 返回 | 说明 |
|---|---|---|
| `insert(v : V) -> Result[RowId, Rejected[K, V]]` | 新记录句柄 | 冲突时**表零变更**,记录原样归还 |
| `insert_many(vs : Array[V]) -> ...` | 批量 | 先全部落库,再**每索引一次性构建**(把 N×k 次索引插入降为 k 次批量构建);**遇重复键的胜出规则须在实现时明确并测试钉死**(主蓝本是"第一个胜出",§0.4-6) |
| `update(id : RowId, v : V) -> Result[Unit, Rejected[K, V]]` | 成功/冲突 | **排除自身**的冲突检查;陈旧 id → `Err` |
| `modify(id : RowId, f : (V) -> V) -> Result[Unit, Rejected[K, V]]` | 成功/冲突 | 用 `f` 变换记录后重索引;**逐索引对比新旧投影键,只动真正变化的桶**(见 §5 规则 4) |
| `remove(id : RowId) -> V?` | 被删记录 | 陈旧 id → `None` |
| `clear() -> Unit` | — | 清空所有记录与索引。**批量退役**:每个活槽的 `gen += 1` 后归还 `free`(代际耗尽的永久退役),因此 **`clear` 之前的句柄永不复活** —— 若直接清空数组,清空后插入会复用同一个 `(slot, gen)`,旧句柄就会静默命中新记录,违反 §7。清空**空表**不算真实变更,不递增 `version`(I8) |

### §3.3 查询

| 方法 | 返回 | 说明 |
|---|---|---|
| `get_by(name : String, key : K) -> RowId?` | 唯一索引命中 | 非唯一索引上的语义待定(倾向返回首个,`iter_by` 才是正解) |
| `iter_by(name : String, key : K)` | 该键下所有记录 | 非唯一索引;**返回顺序 = 槽位号升序**(桶为 `SortedSet[Int]`) |
| `range_by(name, lo, hi)` (需 `Compare`) | **双闭区间 `[lo, hi]`** 内的记录 | 有序索引;**本库增量**(主蓝本无 range API) |
| `range_half_open_by(name, lo, hi)` (需 `Compare`) | **半开区间 `[lo, hi)`** 内的记录 | 同上 |
| `iter_asc_by(name)` / `iter_desc_by(name)` (需 `Compare`) | 按索引键升/降序遍历全部记录 | 同上 |

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
I1  order 中每个槽位都是活记录,且无重复
I2  活记录数 == len == order.length()
I3  每条索引的每个桶内,槽位无重复(桶为 `SortedSet`,结构上已保证;仍作交叉校验)
I4  桶内每个槽位 s 满足 (idx.project)(rows[s]) == 桶键
I5  唯一索引的每个桶长度 <= 1
I6  free 中无重复,且 free 与活记录集合不相交
I7  每个活记录恰好出现在每条索引的对应桶中(无遗漏、无悬挂)
I8  version 仅在真实变更时递增
I9  退役槽位永不回到 free(代际号达上限的槽位被永久移除,见 §3.4)
```

**I5 与 I7 必须成对校验**:I7 防"漏",I5 防"多"。
> I5 是探针实测漏洞反推出来的:最初的校验只查 I3/I4,`update` 又漏了冲突检查,
> 结果一次"更新成已占用的唯一键"让唯一桶出现两个持有人,而校验仍返回 true。

---

## §5 变更汇聚点与三条高危路径

**汇聚点**:`insert_impl` / `remove_impl` / `modify_impl` / **`clear_impl`** 是**唯一**允许同时触碰
`rows` + `order` + `indexes` + `gens` + `free` 的地方。

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

### v0.2 候选(本期明确不做,记录以免遗忘)

- `insert_or_replace(rec) -> Overwritten`:覆盖式 upsert 并结构化返回被顶替的记录
  (学同作者 `bimap` 的 `Overwritten`;主蓝本也把它列在 Future work)。
- schema → MoonBit 源码生成器:把运行时闭包投影静态展开,获得等价 derive 的零开销
  (主蓝本靠过程宏,我们靠代码生成)。
- 密集整数键的 SparseSet 式加速(参照 bevy `ComponentSparseSet` 的 dense+sparse 双数组)。
- 批量重建索引 `rebuild_index(name)` / 延迟建索引。
