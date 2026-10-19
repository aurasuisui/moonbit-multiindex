# moonbit-multiindex

> 一张记录表,**N 个二级索引**。用稳定 ID 定位记录,按任意索引 O(1)/O(log n) 查找。

`aurasuisui/multiindex` 是 MoonBit 的**多级索引记录表**容器:`Table[K, V]` 存储记录 `V`,
并在其上维护任意多条命名索引。每条索引把记录投影成键 `K`,可以是:

- **唯一索引** —— 一个键对应至多一条记录(冲突在变更前上报,不静默覆盖);
- **非唯一索引** —— 一个键对应多条记录;
- **有序索引** —— 按键有序,支持范围查询。

记录用 **`RowId`(槽位 + 代际号)** 定位:槽位会被复用,但代际号保证陈旧 ID 永远不会
静默命中"另一个"记录(ABA 防护)。

## 它解决什么问题

> **BiMap 是「两个互为逆的唯一索引」的特例。本项目把它泛化成 N 个彼此独立的索引。**

| 结构 | 索引数 | 键唯一性 | 记录身份 |
|---|---|---|---|
| `indexmap` | 1(主键) | 唯一 | 键本身 |
| `bimap` | 2(互为逆) | 两个方向都唯一 | 左键 |
| **`multiindex`** | **N(任意组合)** | **每索引独立** | **稳定 `RowId`** |

典型场景:内存表按 email 唯一查、按城市非唯一查、按年龄范围查;ORM 结果集缓存;
ECS 式实体索引;配置项多路检索。

## 快速开始

> 可运行版本见 [`cmd/leaderboard`](cmd/leaderboard)(独立模块,import 已发布的包);
> 签名以 [`docs/SPEC.md`](docs/SPEC.md) 为准(唯一真源)。

```moonbit
let t : @multiindex.Table[Int, Player] = @multiindex.Table::new()
t.register_unique("id", fn(p) { p.id })                          // 哈希唯一
t.register_non_unique("team", fn(p) { p.team })                  // 哈希非唯一
t.register_non_unique_ordered("score", fn(p) { p.score })        // 有序非唯一

let id = t.insert(player)            // -> Result[RowId, Rejected[K, V]]
t.get_by("id", 7)                    // -> (RowId, Player)?
t.iter_by("team", 2)                 // -> Iter2[RowId, Player],槽位号升序
t.range_by("score", 100, 200)        // -> **双闭** [100, 200],按键升序
t.range_half_open_by("score", 100, 200)  // -> [100, 200)
t.iter_desc_by("score")              // -> 排行榜(键降序,同键内槽位仍升序)
t.update(id, player)                 // -> Result[Unit, UpdateRejected[K, V]]
t.modify(id, fn(p) { { ..p, score: p.score + 1 } })
t.verify_invariants()                // -> Result[Unit, String](首个违反点 + 定位信息)
```

**四象限索引**:唯一性(unique / non-unique)× 有序性(hashed / ordered),四个注册方法,不做含糊的三合一。

## API(与 [`docs/SPEC.md`](docs/SPEC.md) 同源)

**构造与注册**(索引的键类型都是同一个 `K`)

| 方法 | 说明 |
|---|---|
| `Table::new()` / `Table::with_capacity(cap)` | 空表;后者预留槽位 |
| `register_unique(name, project)` | 哈希唯一(`Map[K, Int]`) |
| `register_unique_ordered(name, project)` (需 `K : Compare`) | 有序唯一(`SortedMap[K, Int]`) |
| `register_non_unique(name, project)` | 哈希非唯一(`Map[K, SortedSet[Int]]`) |
| `register_non_unique_ordered(name, project)` (需 `K : Compare`) | 有序非唯一 |
| `has_index(name)` / `index_names()` | 注册表查询(名字升序) |

所有 `register_*` 返回 `Result[Unit, RegisterError[K]]`:重名 `Err(DuplicateName)`(**不覆盖**);
对**非空表**注册会**回填扫描**已有记录,回填唯一索引遇冲突则 `Err(UniqueViolation)` 且**完全不注册**。

**写入**(冲突一律在**任何变更之前**检查;失败时表零变更,记录原样归还)

| 方法 | 说明 |
|---|---|
| `insert(v)` | `Result[RowId, Rejected[K, V]]` |
| `insert_many(vs)` | `Result[Array[RowId], Rejected[K, V]]`;**整批原子**,含**批内互相冲突** |
| `update(id, v)` / `modify(id, f)` | `Result[Unit, UpdateRejected[K, V]]`;排除自身的唯一性预检 |
| `remove(id)` / `swap_remove(id)` / `clear()` | 删除单条(旧句柄失效):`remove` **保插入序**、O(len);`swap_remove` 末位换位、**O(1)** 但打乱插入序 / 清空记录与索引条目(**保留注册**) |

**什么时候用哪个**:下一个 `iter()` 必须是插入序 → `remove`;只关心"删掉、还要快"(队列式消费、批量清理)
→ `swap_remove`。两者对索引、`len`、`version`、槽位复用的作用完全相同,被移动的只是插入序里的**槽位**,
所有存活 `RowId` 继续有效。

**查询**

| 方法 | 说明 |
|---|---|
| `get(id)` / `contains(id)` | 按句柄取记录;陈旧句柄 `None` / `false` |
| `len()` / `is_empty()` | 记录数 |
| `iter()` | 插入序,`Iter2[RowId, V]` |
| `get_by(name, key)` | `(RowId, V)?`;非唯一索引返回**槽位号最小**者 |
| `iter_by(name, key)` | 该键的全部记录,槽位号升序 |
| `range_by(name, lo, hi)` / `range_half_open_by(name, lo, hi)` | **双闭** / 半开区间,仅有序索引 |
| `iter_asc_by(name)` / `iter_desc_by(name)` | 按键升 / 降序,仅有序索引 |

**诊断与序列化**

| 方法 | 说明 |
|---|---|
| `verify_invariants()` | `Result[Unit, String]`:首个违反点,消息含不变量编号与槽位/键 |
| `index_stats(name)` | `IndexStats { buckets, entries, longest_bucket, average_bucket }` |
| `to_json()` / `Table::from_json(json)` | `{"records": [...]}`,**按插入序**;索引不参与序列化 |

## 与生态中已有项目的关系

- **不重复** `Milky2018/slotmap`:slotmap 提供稳定键与槽复用(**无索引投影、无唯一性、无按键查找**);
  本库的记录身份机制与它同源,核心价值在多索引。
- **不重复** `kesmeey/IndexMap` / `wqbcs/moon_collections` / `Hhsqoo/moon-collections`:
  它们是有序哈希表(单索引、保留插入序);本库是多路查找结构。
- **不依赖** `aurasuisui/bimap` 或 `aurasuisui/indexmap`:同作者作品,思路延续,代码独立。

> **分支**:`main` 是里程碑视图(每个阶段一个提交),`dev` 保留完整的逐节点开发历史。

## 文档

- 文档枢纽/全量地图:[`docs/README.md`](docs/README.md)
- API 唯一真源:[`docs/SPEC.md`](docs/SPEC.md)
- 立项设计稿(为什么这么设计):[`docs/DEVPLAN.md`](docs/DEVPLAN.md)
- 开发圣经:[`CONTRIBUTING.md`](CONTRIBUTING.md)

## Gotchas(实测得来,不是设想)

- **`range_by` 是双闭区间** `[lo, hi]`(跟随 core 的 `SortedMap::range`);要半开请用
  `range_half_open_by`。`lo > hi` 是**合法的空区间**,返回空迭代器而不是报错。
- **`index_names()` 的"升序"是 MoonBit 的 `String` 序(shortlex:先比长度)**:
  `["aa", "b"]` 会排成 `["b", "aa"]`。多索引同时冲突时,报出的也是**名称升序的第一个**
  (与注册顺序无关)。
- **两类"失败"必须分开看**(SPEC §7.1):可预期的运行时条件(唯一冲突 / 陈旧句柄 / 键查不到)
  返回 `Err` / `None` / 空迭代器,**绝不 panic**;而**未知索引名**、**在哈希索引上做有序查询**
  是调用方 bug,一律 `abort` —— "空结果"只应表示"查得到,但没有"。
- **查询按值返回记录**:每次产出一条记录都会拷贝一次 `V`。`iter_by` 在**大桶**上因此不比线性扫描
  快(两者都要走完所有匹配项,索引还多付拷贝);索引真正的优势在**点查**与**选择性查询**
  (见 [`bench/README.md`](bench/README.md) 的实测表与交叉点)。
- **`remove` 是 O(len + I + Σ log 桶)**:`order` 数组按插入序原地压缩,所以删除随表长线性增长
  (实测比 `insert` 贵 20–44×)。要 O(1) 删除就得放弃插入序稳定性,那是另一个取舍(见 SPEC §6)。
- **JSON 不携带索引**:`from_json` 返回的表**注册表为空**,载入后需自己 `register_*` 回填
  (§3.1 的"对非空表注册即回填"会顺势把索引建好,不需要第二个机制)。
- **冲突不会让调用方丢数据**:`insert` / `insert_many` / `update` / `modify` 失败时,记录随 `Err` 原样归还。
- **`clear()` 保留索引注册**:清空的是记录与索引条目,不是"架构";清空后插入仍会被索引。

## 致谢与来源

**主要参考**:[Rust `multi_index_map`](https://github.com/lun3x/multi_index_map) v0.15.1(**MIT** 许可)
——同样"记录 + N 索引"的容器,后备存储用 `slab::Slab` + 每索引一张查找表(`HashMap`/`BTreeMap`)。
本库的索引分类(唯一 / 非唯一 / 有序)与"冲突不改变容器"的语义与之一致。
完整的许可证核查与 API 对照见 [`docs/SPEC.md`](docs/SPEC.md) §0。

**本库的原创新增**(这些在主蓝本中不存在):

1. **代际 `RowId`(ABA 防护)** —— 主蓝本的 `Slab` 槽位复用不带代际号,陈旧下标会静默命中复用该槽的**新**元素。
2. **范围查询** —— 主蓝本的 ordered 索引只暴露点查与全量遍历,**没有 range**;本库提供 `range_by`(双闭)/ `range_half_open_by`(半开)/ `iter_asc_by` / `iter_desc_by`,且范围查询保持**惰性**(一次只物化一个桶)。
3. **绝不 panic、且冲突时归还记录** —— 主蓝本 `insert` 冲突直接 panic,`modify_by_*` 冲突时更是**先删旧键再 panic,留下脏索引**;本库只有 `Result`,且 `Rejected[K,V]` 把记录原样还给调用方。
4. **代际号溢出即退役槽位** —— 所有 Rust 参考实现都选择静默回绕(bevy 文档明写 "generations can (and do) wrap or alias");本库让陈旧句柄永不复活。
5. **运行时注册索引**(闭包投影)—— 主蓝本依赖 derive 宏;MoonBit 无等价机制,故采用运行时注册,代价是索引名运行时校验,收益是可动态增删/枚举索引。
6. **插入序语义** —— 主蓝本按槽位序遍历;本库额外维护 `order`。
7. **公开 `verify_invariants()`** —— 主蓝本没有一致性自检 API;本库返回 `Result[Unit, String]`,',
'   首个违反点带上"哪条不变量 + 哪个槽位/键",而不是只说 false。',
'8. **整批原子 `insert_many`** —— 主蓝本 `FromIterator` 是 first-wins(静默的胜出规则);本库',
'   预检**批内互相冲突**,任一条冲突则**整批零变更**,并用 `DuplicateInBatch` 指明是批次里哪个成员。',
'9. **诊断与序列化** —— `index_stats`(桶数/最长桶/平均桶长)与 JSON 往返(`{"records": [...]}`)',
'   在主蓝本中都没有。

**其他参考**:`slotmap`(Zlib)/ `thunderdome`(MIT OR Apache-2.0)/ `hecs`(MIT OR Apache-2.0)
提供"槽位 + 代际号"稳定键方案的先例;`generational-arena`(**MPL-2.0**)仅借鉴思路、不复制代码。

**文档与测试体系**:沿用同作者的 [`moonbit-bimap`](https://github.com/aurasuisui/moonbit-bimap)
(文档枢纽/SSOT 纪律、SPEC 唯一真源、分层测试、差分夹具生成器)。

**哈希引擎**:如需自研哈希表,将适配自 `aurasuisui/indexmap`(Apache-2.0),**不引入依赖**。

## License

Apache-2.0
