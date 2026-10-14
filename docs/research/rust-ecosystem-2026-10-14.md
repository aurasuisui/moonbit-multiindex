# moonbit-multiindex 参考蓝本调研报告（Rust 生态）

> 调研时间：2026-10-14（Asia/Shanghai）
> 目标：为 MoonBit 多级索引记录表容器 ```moonbit-multiindex``` 选定参考/移植蓝本
> 数据来源：crates.io API、GitHub API、上游仓库源码与 Cargo.toml 原文、crate 官方 tarball 逐行阅读
> 凡未查到的字段一律标注「未查到」；star 与时间均为抓取时刻快照，未做推测填充。

---

## 0. 结论速览（TL;DR）

| 问题 | 结论 |
|---|---|
| 主蓝本选谁 | **```multi_index_map```（lun3x/multi_index_map，MIT）** —— Rust 生态里唯一同时支持 hashed/ordered × unique/non-unique 四类索引的记录表，结构与我们的容器几乎同构 |
| 稳定 ID 选谁 | **slotmap（Zlib）+ thunderdome（MIT OR Apache-2.0）**；**不要用 generational-arena（MPL-2.0 且已归档）** |
| 冲突语义选谁 | **bimap 的 `Overwritten<L,R>` 枚举**（覆盖了什么结构化返回） |
| 删除策略选谁 | **indexmap 的 `swap_remove` / `shift_remove` 显式二分**；记录表本身用 slab 式空槽 |
| 关键缺口（我们要补的） | multi_index_map **没有代际号**（裸 `usize` slab key，LIFO 复用 → ABA）、**没有范围查询 API**、**没有批量建索引**、**唯一冲突在 modify 路径会 panic 并留下脏索引** |
| 许可证风险 | 候选中唯一有传染性的是 **MPL-2.0（generational-arena、im）**；其余（MIT / Apache-2.0 / Zlib / BSL-1.0）都与 Apache-2.0 发布兼容，但必须保留上游版权声明与来源说明 |

---

## 1. 候选库总览表

| 库 | 仓库 | crates.io | 最新版本 | 最近更新 | Stars | 许可证（精确） | 相关度 |
|---|---|---|---|---|---|---|---|
| **multi_index_map** | [lun3x/multi_index_map](https://github.com/lun3x/multi_index_map) | [crates.io](https://crates.io/crates/multi_index_map) | **0.15.1** | 2026-01-18（repo push 2026-10-07） | **142** | **MIT** | ★★★★★ 主蓝本 |
| indexmap | [indexmap-rs/indexmap](https://github.com/indexmap-rs/indexmap) | [crates.io](https://crates.io/crates/indexmap) | **2.14.2** | 2026-09-05 | **2449** | **Apache-2.0 OR MIT** | ★★★ 风格/删除策略基准 |
| bimap | [billyrieger/bimap-rs](https://github.com/billyrieger/bimap-rs) | [crates.io](https://crates.io/crates/bimap) | **0.6.3** | 2023-03-19（repo push 2023-10-14） | **148** | **Apache-2.0/MIT**（双许可，非标准 SPDX 写法） | ★★★ 冲突语义基准 |
| slotmap | [orlp/slotmap](https://github.com/orlp/slotmap) | [crates.io](https://crates.io/crates/slotmap) | **1.1.1** | 2025-12-06 | **1363** | **Zlib** | ★★★★★ ID 方案 |
| thunderdome | [LPGhatguy/thunderdome](https://github.com/LPGhatguy/thunderdome) | [crates.io](https://crates.io/crates/thunderdome) | **0.6.1** | 2023-06-25（repo push 2026-09-15） | **234** | **MIT OR Apache-2.0** | ★★★★ ID 方案 |
| generational-arena | [fitzgen/generational-arena](https://github.com/fitzgen/generational-arena) | [crates.io](https://crates.io/crates/generational-arena) | **0.2.9** | 2023-05-22 | **690** | **MPL-2.0**（⚠️ 已归档） | ★★ 反面参考 |
| slab | [tokio-rs/slab](https://github.com/tokio-rs/slab) | [crates.io](https://crates.io/crates/slab) | **0.4.12** | 2026-01-31 | **948** | **MIT** | ★★★★ 记录表存储 |
| hecs | [Ralith/hecs](https://github.com/Ralith/hecs) | [crates.io](https://crates.io/crates/hecs) | **0.11.2** | 2026-10-04 | **1381** | **MIT OR Apache-2.0** | ★★★ ECS 存储/句柄分层 |
| bevy_ecs | [bevyengine/bevy](https://github.com/bevyengine/bevy) | [crates.io](https://crates.io/crates/bevy_ecs) | **0.20.0** | 2026-10-08 | **48975**（主仓） | **MIT OR Apache-2.0** | ★★★ 代际号文档化/SparseSet |
| stable-vec | [LukasKalbertodt/stable-vec](https://github.com/LukasKalbertodt/stable-vec) | [crates.io](https://crates.io/crates/stable-vec) | **0.4.3** | 2026-08-23 | **28** | **MIT/Apache-2.0**（deprecated SPDX 写法） | ★★ 稳定索引+位图空洞 |
| typed-index-collections | [zheland/typed-index-collections](https://github.com/zheland/typed-index-collections) | [crates.io](https://crates.io/crates/typed-index-collections) | **3.5.0**（最新发布 4.0.0-alpha.2） | 2026-09-28 | **79** | **MIT OR Apache-2.0** | ★★ 仅「类型安全下标」，非多级索引 |
| multimap | [havarnov/multimap](https://github.com/havarnov/multimap) | [crates.io](https://crates.io/crates/multimap) | **0.10.1** | 2025-05-11 | **79** | **MIT OR Apache-2.0** | ★★ 非唯一索引反面教材 |
| specs | [amethyst/specs](https://github.com/amethyst/specs) | [crates.io](https://crates.io/crates/specs) | **0.20.0** | 2023-09-25（停更） | **2615** | **MIT OR Apache-2.0** | ★★ 位图（bitset）免索引路线 |
| legion | [amethyst/legion](https://github.com/amethyst/legion) | [crates.io](https://crates.io/crates/legion) | **0.4.0** | 2021-02-25（停更） | **1721** | **MIT** | ★★ Group 预排序索引 |
| ckb_multi_index_map | [wyjin/multi_index_map](https://github.com/wyjin/multi_index_map) | [crates.io](https://crates.io/crates/ckb_multi_index_map) | **0.0.3** | 2023-07-07 | 未查到 | **MIT** | ★★ fork 先例 |
| bplus-index | [dahomey-technologies/bplus-index](https://github.com/dahomey-technologies/bplus-index) | [crates.io](https://crates.io/crates/bplus-index) | **0.2.0** | 2026-04-13 | **0** | **MIT OR Apache-2.0** | ★ 有序/范围索引（极不成熟） |
| index-db | [jamesgober/index-db](https://github.com/jamesgober/index-db) | [crates.io](https://crates.io/crates/index-db) | **1.0.0** | 2026-06-17 | **3** | **Apache-2.0 OR MIT** | ★ 范围扫描备选 |
| rpds | [orium/rpds](https://github.com/orium/rpds) | [crates.io](https://crates.io/crates/rpds) | **1.2.1** | 2026-05-15 | **1776** | **MIT** | ★ 持久化结构（可选） |
| im | [bodil/im-rs](https://github.com/bodil/im-rs) | [crates.io](https://crates.io/crates/im) | **15.1.0** | 2022-04-29（⚠️ 仓库已归档） | **1584** | **MPL-2.0+** | ★ 不推荐 |
| sorted-vec | [..](https://crates.io/crates/sorted-vec) | [crates.io](https://crates.io/crates/sorted-vec) | **0.8.11** | 未查到 | 未查到 | **Apache-2.0** | ★ 最轻量有序索引积木 |
| multi-index-container | [..](https://crates.io/crates/multi-index-container) | [crates.io](https://crates.io/crates/multi-index-container) | **0.1.1** | 未查到 | 未查到 | **MIT** | ★ 同类宏方案，几乎无人使用（下载 49） |
| Boost.MultiIndex（C++，概念源头） | [boost.org](https://www.boost.org/doc/libs/1_79_0/libs/multi_index/doc/index.html) | — | 1.79+ | — | — | **BSL-1.0** | ★★★ 概念分类来源 |

> 注：`secondary-map` / `secondary_map` 在 crates.io **不存在（404）**；同名概念只有 `cranelift_entity::SecondaryMap`。`multiindex` 0.2.0 是有限索引集组合数学，与本需求无关。

---

## 2. 详细分析

### 2.1 multi_index_map（主蓝本）

**元数据**
- 仓库 https://github.com/lun3x/multi_index_map ｜ crates.io https://crates.io/crates/multi_index_map ｜ docs.rs https://docs.rs/multi_index_map
- 版本 **0.15.1**（2026-01-18 发布）；**master 分支 Cargo.toml 已写 0.16.0（未发版）**；首次发布 2022-07-08；累计下载 377,774（derive 子 crate 359,287）
- Stars **142**；许可证 **MIT**（LICENSE 原文 “MIT License / Copyright (c) 2022 Louis Wyborn”，两个 crate 的 Cargo.toml 均为 `license = "MIT"`）
- 依赖：`slab = "0.4.12"`（记录表）+ 过程宏子 crate `multi_index_map_derive`（syn / quote / manyhow / convert_case）
- 下游 fork：`ckb_multi_index_map`（wyjin，MIT，0.0.3，2023-07-07，用于 Nervos CKB）

**API 表面**（`#[derive(MultiIndexMap)]` 对元素结构体生成 `MultiIndex<Name>Map`）

```rust
#[derive(MultiIndexMap, Debug)]
#[multi_index_derive(Debug)]                 // 可选：给生成的 map 也 derive
#[multi_index_hash(ahash::RandomState)]      // 可选：自定义 hasher（0.14.0+）
struct Order {
    #[multi_index(hashed_unique)]     order_id: u32,
    #[multi_index(ordered_unique)]    timestamp: u64,
    #[multi_index(hashed_non_unique)] trader_name: String,
    filled: bool,                            // 未索引字段
    volume: u64,
}
```

生成的方法（签名见 README；实现见 `multi_index_map_derive/src/generators.rs`）：

```rust
fn try_insert(&mut self, elem: Order) -> Result<&Order, UniquenessError<Order>>;  // generators.rs:1142
fn insert(&mut self, elem: Order) -> &Order;                                     // 冲突则 panic，:1154
fn with_capacity(n) / capacity() / reserve(additional) / shrink_to_fit() / len() / is_empty() / clear();

fn get_by_order_id<Q>(&self, key: &Q) -> Option<&Order>;          // 唯一索引
fn get_by_trader_name<Q>(&self, key: &Q) -> Vec<&Order>;          // 非唯一索引
fn get_mut_by_order_id<Q>(&mut self, key: &Q) -> Option<(&mut bool, &mut u64)>;   // 只给未索引字段（:445-）
fn update_by_order_id<Q>(&mut self, key: &Q, f: impl FnOnce(&mut bool, &mut u64)) -> Option<&Order>;
fn modify_by_order_id<Q>(&mut self, key: &Q, f: impl FnOnce(&mut Order)) -> Option<&Order>;  // 可改索引字段，需重建索引
fn remove_by_order_id<Q>(&mut self, key: &Q) -> Option<Order>;    // 唯一
fn remove_by_trader_name<Q>(&mut self, key: &Q) -> Vec<Order>;    // 非唯一

fn iter(&self) -> slab::Iter<Order>;          // 直接遍历底层存储，Item = (usize, &Order)
fn iter_mut(&mut self);                       // SAFETY: 只能改未索引字段
fn iter_by_timestamp(&self);                  // 按某索引的顺序遍历
impl IntoIterator for &MultiIndexOrderMap;   impl FromIterator<Order> for MultiIndexOrderMap;
```

查询 key 接受 `&Q where FieldType: Borrow<Q>`，所以 `String` 索引可用 `&str` 查、`Vec<T>` 可用 `&[T]` 查。

**实现设计（源码级）**

底层存储 = `slab::Slab<T>`（连续内存 + 空洞）；每个被索引字段一张查找表（generators.rs:78-103）：

| 索引类型 | 查找表类型 |
|---|---|
| `hashed_unique` | `HashMap<K, usize, S>` |
| `ordered_unique` | `BTreeMap<K, usize>` |
| `hashed_non_unique` | `HashMap<K, BTreeSet<usize>, S>` |
| `ordered_non_unique` | `BTreeMap<K, BTreeSet<usize>>` |

- **插入**：`let store_entry = self._store.vacant_entry(); let idx = store_entry.key();` —— 先**预留**槽位但不占用 → 逐字段做唯一性占用检查（可提前 `return Err(...)`，此时表完全未变）→ 各索引写入 idx → 最后 `store_entry.insert(elem)`（generators.rs:1142-1152）。复杂度 O(k)，k = 索引数。
- **删除**：`remove_by_<field>` 先从该索引取出 slab key → `self._store.remove(idx)` → 再从**其余所有索引**逐一删除（generators.rs:528-565）。`slab::remove` 是 O(1) 且**保留空洞、不搬移其他元素**（源码注释：“The key is then released and may be associated with future stored values.”），所以 slab key 在元素存活期间稳定，其他索引无需修正。
- **非唯一索引删除**：`BTreeSet::remove(&idx)` 为 **O(log n)**；集合空掉则整个 key 从 map 移除（generators.rs:256-268）——这就是「怎么避免 Vec 的 O(n) 移除」的标准答案。
- **修改（modify_by_）**：先对每个索引字段 `clone()` 出旧值 → 应用闭包 → 逐字段比较，变化则「从旧 key 摘除、向新 key 插入」（generators.rs:276-351）。复杂度 O(k log n)。
- **迭代**：`iter_by_*` 按索引序遍历查找表再回表；非唯一索引需要扁平化 BTreeSet。

**唯一冲突语义（重点）**
- `try_insert` → `Err(UniquenessError(elem))`，**把元素原样还给调用者，容器完全不变**（`UniquenessError<T>` 只实现 Display/Debug，未实现 std::error::Error，见 multi_index_map/src/lib.rs:3-19）。
- `insert` → 直接 `panic!("Unable to insert element")`。
- `modify_by_*` 改出重复键 → panic。⚠️ **源码顺序是「先 remove 旧 key → 再 insert 新 key → 若插入返回 Some 则 panic」**（generators.rs:322-332），即 panic 时**索引已处于半更新状态**，容器可能留下不一致。这是我们的实现必须修正的缺陷。
- `FromIterator` 遇重复：**第一个胜出**（源码注释明确，与 HashMap/BTreeMap 的「后者胜」相反，generators.rs:1189-1193）。

**它解决了什么 / 已知限制（多来自 RELEASES.md 修复史）**
- ✅ 解决了「一个结构体要按多个字段查询」，且是 Rust 生态中唯一同时提供四象限索引的库。
- ⚠️ **没有代际号**：slab key 是裸 `usize`，槽位 LIFO 复用 → 陈旧 key 会静默指向新元素（ABA）。这是我们与它的最大差距。
- ⚠️ **没有范围查询 API**：ordered 索引底层是 BTreeMap，但只暴露 `get_by_*` / `iter_by_*`，**没有 range**。
- ⚠️ 历史 bug：0.4.0 修「多个非唯一索引时，从一个索引删除会导致元素在其他非唯一索引里不可访问」；0.15.1 修「非唯一索引遍历 slab 空洞」。**教训：任何「用迭代序号当 slab key」的写法在有空洞时都是错的**（generators.rs:30-57 专门记录了这个坑）。
- ⚠️ 0.4.1 之前唯一冲突会覆盖索引并留下「孤儿元素」；0.8.0 之前要求整个元素 Clone；0.15.0 之前 `get_mut_by_` 返回 `&mut T`（可破坏索引不变量）。
- ⚠️ 无并发（全部 `&mut self`）、无批量建索引；derive 代码体量大（generators.rs 48,922 字节）。

**可迁移 vs 必须重新设计**

| 可迁移（结构/语义层） | 必须重新设计 |
|---|---|
| 记录表 + N 张查找表的分层结构 | **derive 宏** → MoonBit 无过程宏（见 §6 Q1） |
| 四象限索引类型与正交分解 | **代际号**：改用 (slot, generation) 句柄 |
| 非唯一索引 = key → 有序集合(id) | **Borrow<Q> 泛型查询**：MoonBit 无等价物 |
| 删除流程（定位 id → 删表 → 清所有索引） | **panic → Result 的错误语义** |
| try_insert 返回带元素的错误、表不变 | **modify 的原子性**：改为「先校验后提交」 |
| `get_mut` 只暴露未索引字段的 API 切分 | **范围查询**：ordered 索引应补 range（上游缺失） |
| 按索引序遍历的迭代器族 | **批量建索引**（上游缺失，性能增量） |

---

### 2.2 indexmap（风格与删除策略基准）

- [indexmap-rs/indexmap](https://github.com/indexmap-rs/indexmap) ｜ 版本 **2.14.2**（edition 2024，rust-version 1.85）｜ 更新 2026-09-05 ｜ Stars **2449** ｜ 累计下载 1,683,732,225
- 许可证 **Apache-2.0 OR MIT**（Cargo.toml 原文 `license = "Apache-2.0 OR MIT"`）
- 定位：**有序**哈希表（`IndexMap<K,V>` / `IndexSet<T>`），插入序 == 迭代序 == 可用下标访问
- 唯一键冲突语义（src/map.rs 的 `insert` 文档原文）：*“If an equivalent key already exists in the map: **the key remains and retains in its place in the order**, its corresponding value is updated with value, and the older value is returned inside `Some(_)`.”* —— 不报错、不移动位置、旧值以 Option 返回。
- **对我们最有价值的一点**：`swap_remove` / `shift_remove` 的显式二分——一个 O(1) 但打乱顺序、一个 O(n) 但保序，把代价显式交给调用者。**我们的槽位复用策略应照此显式命名，而不是默默选一种。**
- 本次未逐行核对源码（MoonBit 侧已有对应实现，作为 API 风格基准即可）。

---

### 2.3 bimap（唯一冲突/覆盖语义基准）

- [billyrieger/bimap-rs](https://github.com/billyrieger/bimap-rs) ｜ 版本 **0.6.3**（edition 2018）｜ crates.io 更新 2023-03-19，repo 最后 push 2023-10-14 ｜ Stars **148** ｜ 累计下载 50,795,044
- 许可证 **`Apache-2.0/MIT`**（Cargo.toml 原文如此；README 说明为 Apache-2.0 与 MIT 双许可，任选其一）。crates.io 的 license 字段同样是 `Apache-2.0/MIT`。GitHub API 只识别出 Apache-2.0，**以 Cargo.toml/README 的双许可为准**。
- 类型：`BiHashMap<L, R, LS, RS>`、`BiBTreeMap<L, R>`，`BiMap` 是别名；可关 std（no_std 下只保留 BiBTreeMap）
- 内部（src/hash.rs）：**两张表 `left2right` + `right2left`，两侧共享 Rc 引用**（src/mem.rs: `pub struct Ref<T>(pub Rc<T>)`）。⚠️ 因此 `BiHashMap` **不是 Send/Sync**——结构性限制。
- 关键 API：
  - `pub fn insert(&mut self, left: L, right: R) -> Overwritten<L, R>`
  - `pub fn insert_no_overwrite(&mut self, left: L, right: R) -> Result<(), (L, R)>`
  - `pub fn remove_by_left<Q>(&mut self, left: &Q) -> Option<(L, R)>` / `remove_by_right` 对称
  - `get_by_left / get_by_right / contains_left / contains_right`
- `Overwritten<L,R>` 枚举（源码原文）：`Neither` / `Left(L,R)` / `Right(L,R)` / `Pair(L,R)` / `Both((L,R),(L,R))` —— **把「被覆盖了什么」完整结构化返回**，不丢弃也不报错。这是 upsert 场景最值得照抄的语义设计。
- 注意 `FromIterator` / `Extend` 内部走 `insert`，**会静默覆盖**（README 文档化）。
- 我们已有的 MoonBit `BiMap` = 本容器「2 个唯一索引」的特例，应能用同一套内核表达以保持语义一致。

---

### 2.4 稳定 ID：slotmap / thunderdome / generational-arena / slab

**「槽位 + 代际号」是主流做法吗？——是。** Rust 三大代际容器（slotmap 1363★ / generational-arena 690★ / thunderdome 234★）以及 bevy_ecs、hecs 的 `Entity` **全部**采用它。

| 库 | 句柄布局 | 代际类型 / 有效空间 | 溢出行为 | 许可证 |
|---|---|---|---|---|
| **slotmap 1.1.1** | `KeyData{idx:u32, version:NonZeroU32}`，`as_ffi()` 打包 u64，8 B | 版本恒为奇数（`version \| 1`），**有效空间 2³¹** | **静默回绕**；文档明文承认：“After 2³¹ deletions and insertions to the same underlying slot the version wraps around and such a spurious reference could potentially occur.” | **Zlib** |
| **thunderdome 0.6.1** | `Index{slot:u32, generation:NonZeroU32}`，8 B（`Option<Index>` 也 8 B） | 2³²-1 | `checked_add(1).unwrap_or(1)` → **u32::MAX 回绕到 1**，有单测 `wrap_on_overflow` 固化 | **MIT OR Apache-2.0** |
| **generational-arena 0.2.9** | `Index{index:usize, generation:u64}`，**16 B**（Option 24 B） | **全局** u64 计数器 | 裸 `+=`，实际不可达；但 generation 全局共享，**不能假设与槽位一一对应** | **MPL-2.0**；⚠️ 2023-11-08 已归档 |
| **slab 0.4.12** | 裸 `usize` | **无代际号** | LIFO 复用 → ABA | MIT |
| bevy_ecs 0.20 | `Entity{index:NonMaxU32, generation:u32}`，`to_bits()` 打包 u64 | u32（`DIFF_MAX = 1<<31`） | **文档明文承认会 wrap/alias**，提供 `cmp_approx` | MIT OR Apache-2.0 |
| hecs 0.11.2 | `Entity{id:u32, generation:NonZeroU32}` | NonZeroU32（0 保留） | `free()` 用 `wrapping_add(1)`，为 0 时回落为 1 | MIT OR Apache-2.0 |

**主流怎么处理溢出？——全部选择「静默回绕」**，没有任何库采用 panic / 永不复用 / u64 兜底（唯一用 u64 的 generational-arena 只是把溢出推远，句柄涨到 16 B）。只有 slotmap 与 thunderdome 把这个边界**文档化/测试化**了。→ 见 §5 建议 3：**我们做「溢出即退役槽位」，是相对所有参考实现的正确性增量。**

其他工程细节：
- **slotmap** 最值得学：空槽用 `union SlotUnion{value, next_free}` 复用内存；用版本号奇偶位同时表达占用/空闲（`occupied() { version % 2 > 0 }`）；下标 0 是哨兵；`SecondaryMap<K,V>` 提供「按同一 key 集合挂载稀疏附加数据」——**这正是二级索引的形态**。
- **thunderdome** 的空槽也保留 generation，且**在 insert 复用槽位时才递增代际**（remove 不递增）；但 `insert_at` 官方承认可「复活旧 Index」。
- **generational-arena 不要用**：已归档 + MPL-2.0 + 句柄 16 B。
- **stable-vec 0.4.3**（28★，MIT/Apache-2.0）：**不自动复用 key** → 无 ABA 但也无代际号；「稳定索引 + 位图标记空洞」比代际号省空间，代价是无法检测陈旧句柄。

---

### 2.5 ECS 的记录表组织（hecs / bevy_ecs / specs / legion）

**hecs 0.11.2**（MIT OR Apache-2.0，1381★）——源码核对：
- `World { entities: Entities, archetypes: ArchetypeSet, insert_edges, remove_edges, ... }`：**句柄表与数据表分离**。
- `Entities { meta: Vec<EntityMeta{ generation, location: Location{archetype: u32, index: u32} }>, pending, free_cursor, len }` —— Entity → (archetype, 行号) 一次跳转；`pending` 是「freelist | reserved」两段 + `free_cursor` 原子游标的无锁分配设计。
- `Archetype { type_ids: Box<[TypeId]>, index: OrderedTypeIdMap<usize>, entities: Box<[u32]>, data: Box<[Data]> }`：**列式（SoA）**，每组件一列。
- 查询**不建索引**：首次扫 archetype 列表做 `Fetch::prepare` 过滤，结果按「查询签名的 TypeId」缓存进 `world.query_cache()`（`RwLock<HashMap<TypeId, Arc<dyn Any>>>`），并用 `archetypes_generation` 打戳失效。
- 组件增删 = **archetype 迁移**：只需合并有序类型集（双路并行）→ 查 `insert_edges` 缓存（热路径一次数组下标）→ 逐列 `ptr::copy_nonoverlapping` 搬移「源 ∩ 目标」的列，被删组件 drop。**代价 ∝ 共有组件字节数，而非实体总数**。
- 源 archetype 侧统一 `swap_remove`：O(1) 删除，但**行号不稳定**（需回写被挪动实体的 location）。

**bevy_ecs 0.20.0**（MIT OR Apache-2.0，48,975★）——源码核对：
- 模块文档原文：`Tables`「columnar contiguous blocks of memory, optimized for fast iteration」；`SparseSets`「sparse HashMap-like mappings from entities to components, optimized for random lookup and regular insertion/removal」。
- `Storages { sparse_sets, tables, non_sends }`；组件注册时选 `StorageType::Table`（默认）或 `SparseSet`。
- `ComponentSparseSet { dense: Column, sparse: SparseArray<EntityIndex, TableRow> }` —— **稀疏数组就是最直接的「二级索引」形态**（Entity → 行号），O(1) 查改，删除走 dense 交换 + sparse 回写。
- `Archetype` 与 `Table` **不是一回事**：多个 archetype 可共享同一 table（仅 sparse-set 组件不同）；archetype/table **永不回收**（官方文档明确：“Empty archetypes are not removed, and persist until the world is dropped”）。
- `Entity` 是 `#[repr(C)]` 的 index(NonMaxU32) + generation(u32)，字段顺序被注释固定以保证等价于 u64。

**specs 0.20.0（停更）**：不用 archetype 分组，而是**每个组件一份 `hibitset::BitSet`**，Join = 位图按位与（`BitSetAnd/Or/Xor/Not`）。适合「组件频繁单独增删」，但多组件查询要位图与 + 稀疏取值，局部性差。

**legion 0.4.0（停更，MIT）**：`SearchIndex`（扁平 archetype→布局列表 + LayoutFilter 顺序过滤）+ `Group`（把常一起查询的组件声明成组，**预先把匹配的 archetype 排好序**，让多组件查询退化成连续内存遍历）。Group 是**显式声明**的，不是自动推断。

**对我们的取舍启示**
1. ECS 用 **archetype 分桶**替代「每字段索引」，是为了支持任意组件组合、避免索引爆炸；我们的场景是**固定 schema + 用户指定字段索引**，所以 **per-index 查找表**（multi_index_map 路线）更合适：基数可控、代价可预测。
2. 但 ECS 的**分层必须学**：`稳定句柄表（Entity + generation）` 与 `物理存储（archetype/table 行号，可搬运、可交换删除）` 分离——这正是我们「稳定 ID + 可复用槽位」应当采用的分层。
3. `SparseSet`（dense + sparse 双数组）是实现「唯一索引 → 紧凑数组」的低成本方案：dense 存记录、sparse 存 key → dense 下标；比 HashMap 快且可迭代，代价是 key 必须是密集整数。
4. **边缓存（迁移表）是性价比最高的一招**：hecs 用 `HashMap<(u32, TypeId), InsertTarget>` + 纯 xor hasher，bevy 用 `SparseArray<BundleId, _>` 数组下标寻址。MoonBit 侧同理：把「索引维护的目标状态」缓存成数组下标寻址的表。

---

### 2.6 其他相关库（简述）

- **typed-index-collections 3.5.0 / 4.0.0-alpha.2**（zheland，79★，**MIT OR Apache-2.0**）：提供 `TiSlice<K,V>` / `TiVec<K,V>`，是 `[V]` / `Vec<V>` 的**类型化索引包装**（`K: From<usize> + Into<usize>`），目的是**编译期防止用错下标**。README 自陈 “the crate provides **type-safe indexing rather than associative containers**”。**它不是多级索引容器、也没有代际号**；我们只借鉴「用强类型 ID 防止索引串用」这一条。
- **multimap 0.10.1**（79★，MIT OR Apache-2.0）：源码 `pub struct MultiMap<K,V,S> { inner: HashMap<K, Vec<V>, S> }`。**只提供按 key 整体删除**（`remove(&k) -> Option<Vec<V>>`），**没有「按值删除单个元素」的 API**——恰好绕开了 Vec O(n) 移除的难题。这是反面教材：**一旦允许按 (key, id) 删除，Vec 就不可用**。
- **bplus-index 0.2.0**（**0★**，2026-04 新建）与 **index-db 1.0.0**（3★）：Arena 后备 B+Tree / 分页 B+tree 索引原语，原生支持非唯一键与 range（`lookup_range` / 正反向扫描）。**不建议作为移植蓝本**，可作为「范围查询 API 怎么设计」的灵感。
- **specs / legion** 见 §2.5。- **rpds 1.2.1**（MIT，1776★）：持久化结构（含 RedBlackTreeMap 的有序 + range）；与当前需求关系不大。
- **im 15.1.0**：**MPL-2.0+ 且仓库已归档**，直接排除。
- **Boost.MultiIndex**（C++，**BSL-1.0**）：multi_index_map 的灵感来源；`ordered_index` / `hashed_index` 的概念分类与「一个元素被多个索引共享、每个索引有自己的节点」的模型值得读文档，实现方式不可直接搬。

---

### 2.7 补充实证（ECS 迁移代价 / 有序索引能力矩阵）

**bevy_ecs 的存储三层（源码原文）**
```
pub struct Storages { pub sparse_sets: SparseSets, pub tables: Tables, pub non_sends: NonSends }
pub struct SparseSet<I, V> { dense: Vec<V>, indices: Vec<I>, sparse: SparseArray<I, NonMaxUsize> }
pub struct Table { columns: ImmutableSparseSet<ComponentId, Column>, entities: Vec<Entity> }
struct Edges { insert_bundle: SparseArray<BundleId, ArchetypeAfterBundleInsert>,
              remove_bundle: SparseArray<BundleId, Option<ArchetypeId>>, take_bundle: ... }
```
- archetype 与 table **不是一回事**：多个 archetype 可共享同一 table（仅 sparse-set 组件不同）；archetype/table **永不回收**。
- `EntityLocation` 同时带 `archetype_row` 与 `table_row`（同一 table 被多个 archetype 共享时两者不同）。

**archetype 迁移代价（hecs / bevy 一致，源码级）**：单次结构变更 O(1)（与实体总数无关）；常数 ∝ 「源 ∩ 目标」共有组件的总字节数（`ptr::copy_nonoverlapping` / `move_row`），**不是全量拷贝**；冷路径 = 有序类型集双路合并 + 一次 HashMap，热路径 = **一次边缓存数组下标寻址**；源侧统一 `swap_remove`（O(1)，但行号不稳定，需回写被挪动实体的 location）；结构变更需 `&mut`，应批量做；**高频翻转的标记位应放进 sparse-set 存储以完全避免迁移**。

**specs 0.20.0**（2023-09 后停更，MIT OR Apache-2.0，2615★）：**每个组件一份 `hibitset::BitSet`**，Join = 位图按位与（`BitSetAnd / BitSetOr / BitSetXor / BitSetNot`）；组件单独增删便宜（只翻一位），多组件查询局部性差。

**legion 0.4.0**（2021 停更，MIT，1721★）：`SearchIndex`（archetype→布局列表 + LayoutFilter 顺序过滤）+ `Group`（**显式声明**常一起查询的组件，预先把匹配 archetype 排好序）。Group 是显式声明的而非自动推断——佐证了「索引可以显式声明，运行时只做排序与缓存」这一路线。

**有序索引能力矩阵（补充）**

| crate | 版本 | 许可证 | 有序/范围能力 | 备注 |
|---|---|---|---|---|
| bplus-index | 0.2.0 | MIT OR Apache-2.0 | ✅ `lookup_range` / `range`，原生非唯一键（(K,V) 分隔符） | Arena 后备 B+Tree，叶子 64 项 ArrayVec + 双向叶链，zero-unsafe；**0★**，仅 235 下载 |
| index-db | 1.0.0 | Apache-2.0 OR MIT | ✅ 点查 + 正/反向范围扫描 | 面向分页存储的 B+tree 索引原语；**3★** |
| interavl | 0.6.0 | Apache-2.0 | 可重叠区间的刺穿/重叠查询 | **区间树，不是键索引** |
| sorted-vec | 0.8.11 | Apache-2.0 | 二分 + 范围，允许重复 | 最轻量的有序索引积木 |
| kevy-index | 7.0.0 | Apache-2.0 OR MIT | 声明式二级索引（unique / range kind）+ cursor 分页 | 属于 kevy 项目，独立性低 |
| multi-index-container | 0.1.1 | MIT | 未查到 | 过程宏多索引容器；下载 49，几乎无采用，README 抓取 404 |
| secondary-map | — | — | — | **crates.io 404，不存在**；同名概念只有 `cranelift_entity::SecondaryMap` |

---

## 3. 推荐参考组合

| 角色 | 选定 | 理由 |
|---|---|---|
| **主蓝本** | **multi_index_map 0.15.1（MIT）** | 唯一覆盖四象限索引的 Rust 库；与目标同构（记录表 + N 索引 + 稳定位置 key）；MIT 允许改写；仍在维护 |
| **ID 方案** | **slotmap 1.1.1（Zlib）为主 + thunderdome 0.6.1（MIT OR Apache-2.0）为辅** | slotmap 的联合体 + 奇偶标记最省内存；thunderdome 的「insert 时递增 + 独立 generation 字段 + 回绕单测」更清晰、有效代际空间翻倍（2³² vs 2³¹） |
| **冲突语义** | **bimap 0.6.3（Apache-2.0/MIT）** | `Overwritten<L,R>` 结构化返回被覆盖内容；`insert_no_overwrite -> Result<(),(L,R)>` 对应我们的 try_insert |
| **删除/槽位策略** | **indexmap 2.14.2（Apache-2.0 OR MIT）** | swap/shift remove 的显式代价二分；团队已有 MoonBit 版，风格一致 |
| **记录表存储** | **slab 0.4.12（MIT）** | O(1) 增删 + key 稳定 + 连续内存，multi_index_map 的实际选择 |
| **存储分层/句柄表** | **hecs 0.11.2（MIT OR Apache-2.0）** | 「稳定 Entity + generation」与「非稳定物理位置」分离；EntityMeta 表可直接类比 |
| **密集 key 的索引加速** | **bevy_ecs 的 ComponentSparseSet**（MIT OR Apache-2.0） | dense + sparse 双数组 = 唯一索引的低成本实现 |
| **有序/范围索引** | multi_index_map 的 BTreeMap 思路 + **自己补 range API**（上游缺失） | 上游没有可抄的 range API，这是我们的增量 |
| **明确排除** | generational-arena（MPL-2.0 + 归档）、im（MPL-2.0+ 归档）、typed-arena（无删除无 ID）、bplus-index/index-db（star 太少）、multimap（无单值删除）、specs/legion（停更，仅作思想参考） | 见 §4 与 §2 各节限制 |

---

## 4. 许可证合规提示（我们要以 Apache-2.0 发布）

### 4.1 候选许可证清单与兼容性

| 许可证 | 出现在 | 与「Apache-2.0 项目移植」的兼容性 |
|---|---|---|
| **MIT** | multi_index_map、slab、rpds、typed-arena、ckb_multi_index_map、legion、multi-index-container | ✅ 兼容。保留版权声明与许可证全文即可 |
| **Apache-2.0 OR MIT** | indexmap、hecs、bevy_ecs、thunderdome、typed-index-collections、multimap、specs、bplus-index、index-db | ✅ 兼容（双许可任选其一；建议选 Apache-2.0，与我们的发布许可一致） |
| **Zlib** | **slotmap** | ✅ 兼容（宽松、非 copyleft）。要求：保留版权声明；**不得把修改版冒充为原版软件**；分发时保留许可证文本 |
| **BSL-1.0** | Boost.MultiIndex | ✅ 兼容（只需保留版权声明） |
| **MPL-2.0 / MPL-2.0+** | **generational-arena**、im | ⚠️ **文件级 copyleft（传染）**。若把 MPL 代码放进源文件并修改，该文件必须以 MPL-2.0 分发 → 与「整个项目 Apache-2.0」冲突。**结论：不要移植 MPL 代码**，只看设计思想 |
| **MIT/Apache-2.0**（deprecated SPDX 写法） | stable-vec | ✅ 含义是「MIT 或 Apache-2.0」 |
| GPL / LGPL / AGPL | 候选集中**未出现** | ⛔ 不兼容 |

### 4.2 「移植」在法律上是衍生作品——必须做的 6 件事

1. **写明来源**（也是竞赛硬性要求）：新建 `NOTICE` 或 `PORTS.md`，逐条列出 `项目名 + 仓库链接 + 许可证 + 参考范围（文件/模块/commit）`。示例：

```
This project is inspired by and partially ported from:
- multi_index_map (https://github.com/lun3x/multi_index_map), MIT License,
  Copyright (c) 2022 Louis Wyborn.
  Referenced: multi_index_map/src/lib.rs, multi_index_map_derive/src/generators.rs
  (commit <hash>, 2026-10-07).
  Ported concepts: lookup-table-per-index design, insert/remove/modify index-maintenance flow.
  Re-implemented in MoonBit; no code copied verbatim.
- slotmap (https://github.com/orlp/slotmap), Zlib License ... (concept only)
```

2. **保留上游版权声明全文**（MIT / Zlib / BSL-1.0 都强制要求），把上游 LICENSE 文本放进 `third_party/` 或 `NOTICE`。
3. **记录参考的 commit hash**：上游 master 与已发布版本可能不同（multi_index_map master 已是 0.16.0，crates.io 是 0.15.1）。以你实际阅读的 commit 为准。
4. **不要逐行翻译**：MIT/Zlib 允许衍生，但「逐行翻译 + 复制注释」会显著提高被认定为复制品的风险，也违背竞赛「原创/移植需说明」的精神。用 MoonBit 惯用法重写（例如把 Rust 的 `Borrow<Q>` 泛型查询改成显式 key 类型）。
5. **不要复制代码注释与文档**：注释与文档同样受版权保护。
6. **想完全规避风险**：只参考**设计思想与 API 形态**（思想、算法、数据结构不受版权保护），实现全部自写，并在 NOTICE 中致谢来源。这是「原创」路线，最安全。

### 4.3 特别提醒
- **不要**从 generational-arena（MPL-2.0）或 im（MPL-2.0+）复制任何代码，哪怕几行。
- **thunderdome 的 GitHub 页面显示 Apache-2.0，但 Cargo.toml 是 `MIT OR Apache-2.0`** —— 以 Cargo.toml 为准，引用时写双许可。
- **bimap 的 `license = "Apache-2.0/MIT"` 是非标准 SPDX 写法**，实为双许可（README 明确 “dual-licensed under the Apache License and the MIT License”）。
- 我们自己发布 Apache-2.0 时，建议 `LICENSE`(Apache-2.0) + `NOTICE` + `third_party/LICENSES/`。

---

## 5. 给 MoonBit 的设计建议（10 条）

**1. 索引注册 API：核心库走「运行时注册 + 闭包投影」，另提供代码生成器作为优化路径。**
```moonbit
let t : Table[Order] = Table::new()
t.add_unique_index("order_id", fn(o) { o.order_id })          // 哈希唯一
t.add_unique_index_sorted("timestamp", fn(o) { o.timestamp }) // 有序唯一
t.add_multi_index("trader", fn(o) { o.trader_name })          // 哈希非唯一
```
理由：MoonBit 没有过程宏，运行时闭包投影是唯一能保持「任意字段 + 任意组合」表达力的方案；代价是每索引一次间接调用（可测量）。**同时给一个 schema → MoonBit 源码的生成器**，在性能敏感场景把索引展平成静态字段，获得与 Rust derive 等价的零运行时开销。手写 N 个变体会组合爆炸，只在极端场景使用。

**2. ID 方案：`(slot: UInt, generation: UInt)` 打包成一个 UInt64**（高 32 位 generation、低 32 位 slot，与 bevy/hecs/slotmap 一致），generation 从 1 开始、0 保留给「空句柄」，保证 `Option[Id]` 仍是 8 字节。

**3. 代际号溢出：退役槽位，而不是回绕。** 参考实现全部静默回绕（slotmap 2³¹、thunderdome 2³²-1→1）；我们在 generation 达到上限时**把该槽位永久移出自由链表**（不再复用），使陈旧句柄永不复活。这是相对所有 Rust 参考实现的正确性增量，实现成本极低（一个分支 + 不 push 回 free list）。务必在文档写明有效代际空间。

**4. 记录表存储：`Array[Option[Record]]` + 自由链表（slab 风格），不要 swap_remove。** 记录表物理位置必须稳定，否则所有二级索引都要跟着改。**迭代必须跳过空洞**——multi_index_map 在这里踩过两次坑（0.4.0、0.15.1），教训是：**永远不要用「迭代到的第 n 个元素」当槽位号**，只能用显式保存的槽位号。

**5. 非唯一索引存储：`Map[K, SortedSet[Id]]`，绝不用 `Map[K, Array[Id]]`。** 单元素删除需要 O(log n)（BTreeSet 路线，multi_index_map 0.6.0 之后的做法）；用数组按值删除就是 O(n)，而 multimap 之所以敢用 Vec，是因为它根本不提供单值删除。**优化档**：key 为小整数时可用「dense 桶 + 延迟压缩（tombstone + 定期 compact）」降低常数（类比 bevy SparseSet）。

**6. 唯一冲突语义：提供两套，绝不 panic。**
- `try_insert(rec) -> Result[Id, (Record, ConflictInfo)]`：失败时把记录原样还给调用者、容器零改动（学 multi_index_map 的 `vacant_entry` 预检技巧）。
- `insert_or_replace(rec) -> Overwritten[...]`：覆盖并返回被覆盖的记录（学 bimap 的 Overwritten）。
MoonBit 里 panic 等价于 abort（不可恢复），把冲突做成可恢复错误是必须的。

**7. 更新记录要区分两条路径，并保证原子性。**
- `update_unindexed(id, f)`：f 只能拿到**未索引字段**（multi_index_map 0.15.0 之后的 API 切分），O(1)，不碰索引。
- `modify(id, f)`：f 拿到整条记录；实现必须是「**先 clone 出各索引旧投影值 → 应用闭包 → 重算新投影值 → 全部校验通过后再落地索引变更**」。**上游的 modify 在中途 panic 会留下脏索引，必须修正**：先做唯一性预检（新键是否已被别的 id 占用），冲突则回滚或返回错误，而不是半更新。

**8. 有序索引必须暴露范围查询（上游缺口，我们的增量）**：`range(lo, hi)` / `range_inclusive` / `iter_asc` / `iter_desc`。有序结构选型：用**平衡 BST / 跳表**（增删 O(log n) 且支持范围）；不要用「有序数组 + 二分」——查询 O(log n) 但删除 O(n)。范围查询应返回惰性迭代器而非先收集成数组。

**9. 删除与迭代的安全约定。** 提供 `remove(id)` 与 `remove_by_<index>(key)`；流程固定为「定位 id → 从记录表移除 → 从其余所有索引摘除」，并**先做全部前置检查再修改**。由于 MoonBit 没有借用检查器，给容器加 `mod_count`（修改计数），迭代器每次 next 校验并在被修改时 fail-fast（类似 Java 的 ConcurrentModificationException），而不是产生未定义行为。

**10. 批量与性能：插入/删除是 O(k)（k = 索引数），必须提供批量路径。**
- `insert_many(records)`：先全部写入记录表，再**每个索引一次性构建**（把 N×k 次索引插入降为 k 次批量构建）；
- `build_indexes()` / `rebuild_index(name)`：支持延迟建索引。
文档中给出 k 与吞吐的取舍表；可配置「只维护被查询的索引」。

**11（附加）. BiMap 兼容性**：把已有 BiMap 表达为「2 个唯一索引、无未索引字段」的特例，共用同一套内核，保证两个 API 语义一致。

---

## 6. 四个特别问题的直接回答

### Q1：multi_index_map 是过程宏驱动的，MoonBit 没有 derive，怎么办？

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **(a) 运行时注册 + 闭包投影**（推荐做核心） | `add_unique_index(name, fn(rec) -> K)`，内部保存 `Map[K, Id]`；查询/删除/更新都走注册表 | 无宏依赖；支持任意字段组合与动态 schema；一个泛型内核搞定所有形态；与 BiMap 共用 | 每索引每记录一次闭包调用；key 类型异构，需类型擦除机制；编译期发现不了字段名写错 |
| **(b) 手写 N 个变体** | 为每种索引组合手写容器类型 | 零开销、类型最精确 | 组合爆炸（4 类索引 × 字段组合），不可维护 |
| **(c) 代码生成器**（推荐做优化/示例） | 外部脚本读 schema（DSL/JSON）→ 生成 MoonBit 源码 | 等价 derive 的静态展开；零运行时开销；生成物可读可审计 | 需要额外构建步骤；IDE/调试体验差；schema 变更要重跑 |

**建议组合**：(a) 作为公共内核（通用、可测试），(c) 作为可选性能加速层（附示例生成器），(b) 只在极端场景使用。**不要试图在 MoonBit 里模拟宏**——把复杂度放在「运行时注册表 + 类型擦除」上是唯一现实可行的路。

### Q2：槽位 + 代际号是主流吗？溢出怎么处理？

是主流（slotmap / thunderdome / generational-arena / bevy_ecs / hecs 全是）。**溢出的主流处理方式是「什么都不做、静默回绕」**：slotmap 用 `wrapping_add`，文档承认 2³¹ 次后可能复活旧 key；thunderdome 用 `checked_add(1).unwrap_or(1)`，u32::MAX 回绕到 1 并写单测固化；bevy 文档直白写 “generations can (and do) wrap or alias” 并提供 `cmp_approx`；hecs 在 `free()` 里 `wrapping_add(1)`。**没有任何库选择 panic、永不复用槽位或用 u64 兜底**（唯一用 u64 的 generational-arena 只是把溢出推远，句柄涨到 16 字节）。→ 见建议 3：我们做「溢出即退役槽位」，是正确性增量。

### Q3：非唯一索引在主流实现里是 Map[K, Vec[Id]] 还是 SmallVec 还是别的？删除怎么避免 O(n)？

- **multi_index_map：`Map[K, BTreeSet<usize>]`**（哈希/有序两种外层 map）。**0.6.0 才换成 BTreeSet**，release note 原文：“use BTreeSet to store equivalent elements in a non-unique index to improve insert/remove/modify performance”。删除某个 id 是 `BTreeSet::remove` = **O(log n)**；集合空掉就把整个 key 删掉。
- **multimap：`HashMap<K, Vec<V>>`**，但它**不提供按值删除单个元素的 API**，所以不存在 O(n) 问题——这是「回避」而非「解决」。
- **ECS 侧的等价物是 SparseSet**（dense + sparse 双数组）：id ↔ 数组下标互查，删除用「末尾元素搬到空洞 + 更新 sparse」的交换删除，**O(1)**，但要求 id 是密集小整数且**元素下标位置不稳定**。
- **结论**：索引存的是「自身 ID」时，`Map[K, SortedSet[Id]]` 最稳妥（O(log n) 删除 + 天然有序 + 可范围遍历）；若同一 key 下 id 集合很小（< 8），可用 SmallVec + 线性删除（常数更小）；若 id 是连续密集整数，SparseSet 式双数组可做到 O(1) 删除。**唯一要避免的是「大 Vec + 线性删除」。**

### Q4：有没有库同时支持唯一 + 非唯一 + 有序（可范围查询）三类索引？

- **有，但只有 multi_index_map 一个**：`hashed_unique / ordered_unique / hashed_non_unique / ordered_non_unique` 正好覆盖三类需求。
- **但它没有暴露范围查询 API**：ordered 索引只生成 `get_by_*`（点查）与 `iter_by_*`（全量按序遍历），**没有 range**。也就是说上游只做到了存储层，没做到 API 层。
- 生态里其余方案都是**拼装**：唯一索引 = `HashMap/BTreeMap<K, RowId>`；非唯一索引 = `Map<K, SmallVec<RowId>>` 或 `Map<K, BTreeSet<RowId>>`；有序/范围 = `BTreeMap<(K, RowId), ()>`（**复合键是「非唯一 + 有序 + 支持 range」的标准技巧**）或直接上 B+Tree（bplus-index）。
- **组合方案（我们的设计）**：
  1. 唯一索引（哈希）→ `HashMap[K, Id]`（或复用团队已有实现）；
  2. 唯一索引（有序）→ `SortedMap[K, Id]` + 范围查询；
  3. 非唯一索引 → `Map[K, SortedSet[Id]]`；
  4. 有序索引补 `range(lo, hi)` / `iter_asc` / `iter_desc`（上游缺失的差异化能力）；
  5. 记录表 → `Array[Option[Record]]` + 自由链表 + (slot, generation) 句柄；
  6. 统一抽象：`Index` 接口 = `{ insert(id, key), remove(id, key), update(id, old_key, new_key) }`，由 4 个具体实现提供 —— 这就是 Q1 的 (a) 方案在类型层的落点。

---

## 7. 可核实链接清单

**主蓝本**
- https://github.com/lun3x/multi_index_map ｜ https://crates.io/crates/multi_index_map ｜ https://docs.rs/multi_index_map
- 源码：https://raw.githubusercontent.com/lun3x/multi_index_map/master/multi_index_map_derive/src/generators.rs ｜ 同目录 ../src/index_attributes.rs ｜ ../../multi_index_map/src/lib.rs ｜ ../../RELEASES.md ｜ ../../LICENSE
- 参考测试：multi_index_map/tests/{hashed_unique, non_unique_holes, update, mixed_non_unique}.rs

**其他库**
- https://github.com/indexmap-rs/indexmap ｜ https://crates.io/crates/indexmap ｜ https://raw.githubusercontent.com/indexmap-rs/indexmap/main/Cargo.toml
- https://github.com/billyrieger/bimap-rs ｜ https://crates.io/crates/bimap ｜ https://raw.githubusercontent.com/billyrieger/bimap-rs/master/src/hash.rs
- https://github.com/orlp/slotmap ｜ https://crates.io/crates/slotmap ｜ https://static.crates.io/crates/slotmap/slotmap-1.1.1.crate
- https://github.com/LPGhatguy/thunderdome ｜ https://crates.io/crates/thunderdome ｜ https://static.crates.io/crates/thunderdome/thunderdome-0.6.1.crate
- https://github.com/fitzgen/generational-arena ｜ https://crates.io/crates/generational-arena ｜ https://static.crates.io/crates/generational-arena/generational-arena-0.2.9.crate
- https://github.com/tokio-rs/slab ｜ https://crates.io/crates/slab ｜ https://static.crates.io/crates/slab/slab-0.4.12.crate
- https://github.com/LukasKalbertodt/stable-vec ｜ https://crates.io/crates/stable-vec
- https://github.com/Ralith/hecs ｜ https://crates.io/crates/hecs ｜ https://raw.githubusercontent.com/Ralith/hecs/master/src/{entities,archetype,world,query}.rs
- https://github.com/bevyengine/bevy ｜ https://crates.io/crates/bevy_ecs ｜ https://raw.githubusercontent.com/bevyengine/bevy/main/crates/bevy_ecs/src/{entity/mod.rs, storage/mod.rs, storage/sparse_set.rs, storage/table/mod.rs, archetype.rs, bundle/insert.rs}
- https://github.com/amethyst/specs ｜ https://crates.io/crates/specs ｜ https://static.crates.io/crates/specs/specs-0.20.0.crate
- https://github.com/amethyst/legion ｜ https://crates.io/crates/legion ｜ https://static.crates.io/crates/legion/legion-0.4.0.crate
- https://github.com/havarnov/multimap ｜ https://crates.io/crates/multimap ｜ https://raw.githubusercontent.com/havarnov/multimap/master/src/lib.rs
- https://github.com/zheland/typed-index-collections ｜ https://crates.io/crates/typed-index-collections
- https://github.com/wyjin/multi_index_map ｜ https://crates.io/crates/ckb_multi_index_map
- https://github.com/dahomey-technologies/bplus-index ｜ https://crates.io/crates/bplus-index
- https://github.com/jamesgober/index-db ｜ https://crates.io/crates/index-db
- https://github.com/orium/rpds ｜ https://crates.io/crates/rpds ｜ https://github.com/bodil/im-rs ｜ https://crates.io/crates/im
- Boost.MultiIndex：https://www.boost.org/doc/libs/1_79_0/libs/multi_index/doc/index.html

**元数据抓取入口（可复现）**
- `https://crates.io/api/v1/crates/<name>`（含 license / max_stable_version / updated_at / repository）
- `https://api.github.com/repos/<owner>/<repo>`（含 stargazers_count / license.spdx_id / pushed_at / archived）
- 注意：GitHub REST 有未认证限流（本次部分请求返回 HTTP 403，相关 star 字段改用 shields.io 兜底）

**未能核实 / 受限期**
- bimap 原 contain-rs 仓库（https://github.com/contain-rs/bimap）返回 404 —— 现已迁移到 billyrieger/bimap-rs
- multi_index_map 的 GitHub Issues 列表（API 403 限流）未能抓取；「已知问题」结论来自 RELEASES.md 的修复史
- sorted-vec / multi-index-container 的 star、更新时间未查到（GitHub API 限流）
- 所有 star、updated_at、pushed_at 均为 2026-10-14 抓取快照
