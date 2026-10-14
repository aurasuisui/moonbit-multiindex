# DEVPLAN.md — moonbit-multiindex 立项设计稿

> **状态**:立项设计稿(活文档,随实现修订)
> **定位**:回答"为什么这么设计"。API 签名以 [`SPEC.md`](SPEC.md) 为准。
> **采集/验证日期**:2026-10-14

---

## §1 定位:BiMap 的 N 索引泛化

| | 结构 | 索引数 | 键唯一性 | 记录身份 |
|---|---|---|---|---|
| `indexmap` | IndexMap | 1(主键) | 唯一 | 键本身 |
| `bimap` | BiMap | **2**(互为逆) | 两个方向都唯一 | 左键 |
| **本项目** | `Table[K, V]` | **N(可任意组合)** | 每索引独立(唯一/非唯一/有序) | **稳定 RowId**(槽位+代际) |

一句话:**BiMap 是"两个互为逆的唯一索引"的特例;本库把它泛化成 N 个彼此独立的索引。**

这不是"拆分项目":`bimap` 的两个索引必须互为逆函数(强耦合);本库的 N 个索引彼此无关,
且引入 bimap 完全没有的两个概念——**记录身份**(RowId)与**非唯一索引**。

### 与已有 MoonBit 生态的差异(过审关键)

- vs `Milky2018/slotmap`:slotmap 只有"稳定键 + 槽复用 + 副表(SecondaryMap)",**没有索引投影、
  没有唯一性约束、没有按键查找**。本库的记录身份机制与 slotmap 同源,但核心价值在索引。
- vs `kesmeey/IndexMap` / `wqbcs/moon_collections` / `Hhsqoo/moon-collections`(均为有序哈希表):
  它们是"键→值"的单索引容器,目标是**保留插入序**;本库是"记录→多索引",目标是**多路查找**。
- 检索证据(2026-10-13):`moon search "multi index"` / `"secondary index"` 在 mooncakes 上
  无相关结果;GitHub 搜 `moonbit+multi-index`、`moonbit+secondary+index` 均为 0 结果。

---

## §2 数据布局

```
Table[K, V]
├── rows    : Array[V?]              # 槽位存储;None = 空槽
├── gens    : Array[Int]             # 每槽代际号,槽复用时 +1
├── free    : Array[Int]             # 空闲槽栈(LIFO);**退役槽位不入栈**(I9)
├── order   : Array[Int]             # 插入序(活记录的槽位)
├── indexes : Map[String, Index[K, V]]  # 2×2 四象限索引注册表
├── mut len : Int                    # 活记录数
└── mut version : Int                # 变更计数器(fail-fast 迭代器)
```

**索引四象限**(与主蓝本 `hashed_unique` / `ordered_unique` / `hashed_non_unique` /
`ordered_non_unique` 一一对应):

| 唯一性 × 有序性 | 存储 |
|---|---|
| 唯一 + 哈希 | `Map[K, Int]` |
| 唯一 + 有序 | `SortedMap[K, Int]` |
| 非唯一 + 哈希 | `Map[K, SortedSet[Int]]` |
| 非唯一 + 有序 | `SortedMap[K, SortedSet[Int]]` |

```
RowId  { slot : Int, gen : Int }     # 只作为**外部句柄**
```

**关键点**:
1. 索引**不存值**,只存**槽位号**;值永远只住在 `rows` 里(单一真源)。
2. 索引条目**只存槽位号 `Int`,不存 `RowId`** —— 代际号只用于校验外部传入的句柄;
   桶内条目由汇聚点维护,按构造永远指向当前活记录。
3. **桶用有序集合而非数组**:初稿曾选 `Array[Int]`(保插入序、常量小),但大桶下 O(k) 线性删除
   不可接受;主蓝本 0.6.0 已因性能把 `Vec` 换成 `BTreeSet`。**代价:桶内顺序为槽位号升序**。

---

## §3 不变量(命根子,属性测试的靶子)

```
I1  order 中每个槽位都是活记录,且无重复
I2  活记录数 == len == order.length()
I3  每条索引的每个桶内,槽位无重复(桶为 SortedSet,结构上已保证;仍作交叉校验)
I4  桶内每个槽位 s 满足 (idx.project)(rows[s]) == 桶键        # 投影一致
I5  唯一索引的每个桶长度 ≤ 1                                   # 唯一性
I6  free 中无重复,且 free 与活记录集合不相交
I7  每个活记录恰好出现在每条索引的对应桶中(无遗漏、无悬挂)     # 完备性
I8  version 仅在真实变更时递增
I9  退役槽位永不回到 free(代际号达上限的槽位永久移出自由链表)
```

> **I5 是探针实测抓出来的漏洞**:最初版本的 `verify` 只查了 I3/I4,`update` 又漏了冲突检查,
> 结果一次"更新成已存在的唯一键"就让唯一桶出现两个持有人,而 `verify` 仍返回 true。
> **I5 与 I7 必须成对校验**:I7 防"漏",I5 防"多"。

---

## §4 变更汇聚点(chokepoint 纪律)

类比 bimap 的"三个 chokepoint",本库**所有**变更必须走这三条路径,其余代码不得同时触碰
`rows` / `order` / `indexes` / `gens` / `free`:

| 路径 | 步骤 | 返回 |
|---|---|---|
| `insert_impl` | 冲突检查(**变更前**)→ 分配槽(复用或新槽)→ 写入行 → 每索引加桶 → `order.push` | `RowId` |
| `remove_impl` | 每索引删桶 → `rows[slot]=None` → `gens[slot]+=1` → `free.push` → `order` 压缩 | `V` |
| `update_impl` | **排除自身的冲突检查** → 每索引删旧桶 → 写入新行 → 每索引加新桶 | `Result[Unit, Conflict[K]]` |

### 三条高危路径(探针已验证)

1. **`update` 必须做"排除自身"的冲突检查**。探针实测:漏掉后把 bob 的 name 改成已存在的
   `"carol"`,update 返回 true 且不变量被破坏。排除自身是必需的——记录更新成"自己已有的键"
   不算冲突。
2. **冲突检查必须在任何变更之前完成**。同 bimap 的 `insert_no_overwrite`:`Err` 返回时
   表必须与调用前**逐字节等价**(探针实测:冲突后 `verify=true`、`len` 不变)。
3. **`update` 的删旧桶 / 加新桶之间不能有可观察的中间态**。若"旧键 == 新键"(记录只改了
   非索引字段),应走快路径:不做桶增删,或删后立即加回。
4. **`modify` 必须先完成全部唯一性预检,再一次性提交**(第二轮调研新增)。
   主蓝本 `modify_by_*` 的顺序是"先删旧键 → 再插新键 → 若插入返回 `Some` 则 panic"
   (`generators.rs:322-332`),**panic 时索引已半更新,容器脏掉**。
   本库固定顺序:**算新投影 → 逐唯一索引预检(排除自身) → 全部通过后统一落地**。

---

## §5 复杂度

| 操作 | 复杂度 | 说明 |
|---|---|---|
| `insert` | O(I + Σ 桶代价) | I = 索引数;加桶是 O(1) 均摊 |
| `get_by(index, key)` | O(1) 均摊 | 哈希索引直接查桶 |
| `range_by(index, lo, hi)` | O(log n + k) | 有序索引 SortedMap |
| `remove(id)` | O(I + Σ log 桶) | 每索引删桶;非唯一桶为有序集合,O(log k) |
| `modify(id, f)` | O(I) 预检 + Σ(变化索引的 log 桶) | **键未变的索引完全不动** |
| `iter()` | O(len) | 沿 `order` 遍历 |
| 空间 | O(len + Σ 索引条目) | 索引只存槽位号 |

---

## §6 探针验证记录(MoonBit 语言能力,2026-10-14)

设计前用一次性探针(`_probe/`,已删除)验证了全部关键机制,**结论均已实测**:

| 机制 | 结论 |
|---|---|
| **结构体泛型不能带 trait 约束** | `struct Index[K : Hash + Eq, V]` 是**语法错误**;约束只能写在方法上(`fn[K : Hash + Eq, V] Index::new(...)`)。与 bimap 的 `struct BiMap[L, R]` 一致 |
| 闭包投影作字段 | `project : (V) -> K` 可作结构体字段并被正常调用 `(idx.project)(v)` |
| 嵌套泛型容器 | `Map[String, Index[K, V]]`、`Map[K, Array[Int]]` 均可 |
| 有序索引 | `@sorted_map.SortedMap[K, Array[Int]]` 可作有序索引,支持范围查询 |
| Map 遍历 | `for name, idx in self.indexes` 可用;遍历时透过取出的副本修改内部 Map 生效 |
| 槽位复用 + 代际号 | 实测:`d.slot == a.slot` 且 `gens[0]` 由 0→1;用陈旧 `a` 删除返回 `None`(**ABA 防护生效**) |
| 自定义错误 | `suberror` + `Result` 正常;`derive(Eq, Hash, Debug, Show)` 在 `RowId` 上可用 |
| 命名坑 | 枚举变体名 **不要**叫 `None_`(与 `Option::None` 在 match 位置混淆);错误枚举**不要**加「无冲突」变体(与 `Option` 重复,且迫使调用方匹配 `Err(Clean)`) |

---

## §7 参考实现(Rust 生态)

**主蓝本**:[`multi_index_map`](https://github.com/lun3x/multi_index_map) v0.15.1,**MIT** 许可,
377,774 次下载,2026-01-18 更新。它同样是"记录 + N 个索引"容器:`slab::Slab` 后备存储 +
每个索引字段一张查找表(`HashMap` 或 `BTreeMap`),索引种类为 `hashed_unique` /
`hashed_non_unique` / `ordered_unique` / `ordered_non_unique`。

**完整的许可证核查、API 表面、本库的原创新增(代际 RowId / 运行时注册 / 插入序 / 公开自检)
与取舍对照表,见 [`SPEC.md` §0`](SPEC.md)。** 要点:

| 维度 | 主蓝本 | 本库 |
|---|---|---|
| 后备存储 | `Slab<T>`(槽 + 空洞) | `Array[V?]` + `free` + **`gens`** |
| 句柄 | `usize` 槽下标 | **`RowId{slot, gen}`(ABA 防护)** |
| 索引定义 | derive 宏(编译期) | 运行时闭包注册 |
| 非唯一桶 | `BTreeSet<usize>` | `Array[Int]`(插入序) |
| 冲突 | `try_insert` → `Err` | 一律 `Err`,零变更 |
| 自检 | 无 | 公开 `verify_invariants()` |

**许可证纪律**:主蓝本 MIT(兼容 Apache-2.0,须保留归属);辅助参考 `slotmap` 为 Zlib(宽松)、
`thunderdome`/`hecs` 为 MIT OR Apache-2.0;`generational-arena` 为 **MPL-2.0(弱 copyleft)**
——**只借鉴思路,不复制代码**。

---

## §8 测试体系设计(对齐 bimap 的分层)

| 层次 | 文件 | 职责 |
|---|---|---|
| 单元 | `table_test.mbt` | 注册/插入/查找/删除/更新的基本矩阵 |
| 不变量 | `property_test.mbt` | `check_invariants`(I1–I8),随机操作序列每步后校验 |
| 模型对拍 | `model_test.mbt` | 与 `Array[V]` 线性扫描朴素实现全操作序列差分 |
| 差分(Tier 1) | `differential_test.mbt` + `*_fixture_test.mbt` | 与 Rust 参考实现的观测序列对齐,夹具由 `tools/diffgen` 生成并入库 |
| 白盒 | `table_wbtest.mbt` | 直读私有字段:I6(free 一致性)、槽位逆映射、代际号单调性 |
| 回归 | `regression_wbtest.mbt` | 钉死探针发现的 update 冲突漏洞 |
| 压力 | `bench_test.mbt` | 10k+ 操作、槽位复用风暴、桶长极值 |
| 基准 | `bench/main.mbt` | 与线性扫描、与手工多表维护对比 |

**测试约定**(沿用 bimap):黑盒统一 `@aurasuisui/multiindex.` 前缀;循环内避免
`debug_inspect`;调用断言的辅助函数必须 `-> Unit raise`。

---

## §9 文档体系(对齐 bimap)

`docs/README.md`(枢纽,SSOT 表)→ `SPEC.md`(API 真源)→ `CONTRIBUTING.md`(开发圣经)→
`AGENTS.md`(唯一会话入口,面向所有编码 agent)→ `CHANGELOG.md`(决策史)→
`SESSION_PLAYBOOK.md`(任务会话手册)→ `RELEASE_CHECKLIST.md`(发布门禁)。
**纪律**:每条事实只住一个文件;新增/删除文档必须同步 `docs/README.md` 地图。
