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

> v0.1.0 开发中,API 以 [`docs/SPEC.md`](docs/SPEC.md) 为准(唯一真源)。

```moonbit
// 计划中的形态(以 SPEC.md 为准)
let t : @aurasuisui/multiindex.Table[String, User] = @aurasuisui/multiindex.Table::new()
t.register_unique("email", fn(u) { u.email })              // 哈希唯一
t.register_non_unique("city", fn(u) { u.city })            // 哈希非唯一
t.register_unique_ordered("age", fn(u) { u.age })          // 有序唯一
t.register_non_unique_ordered("score", fn(u) { u.score })  // 有序非唯一

let id = t.insert(user)              // -> Result[RowId, Rejected]
t.get_by("email", "a@b.c")           // -> 唯一命中
t.iter_by("city", "beijing")         // -> 多条(槽位号升序)
t.range_by("age", 18, 30)            // -> [18, 30) 范围内的记录
t.modify(id, fn(u) { { ..u, age: u.age + 1 } })
```

**四象限索引**:唯一性(unique / non-unique)× 有序性(hashed / ordered),四个注册方法,不做含糊的三合一。

## 与生态中已有项目的关系

- **不重复** `Milky2018/slotmap`:slotmap 提供稳定键与槽复用(**无索引投影、无唯一性、无按键查找**);
  本库的记录身份机制与它同源,核心价值在多索引。
- **不重复** `kesmeey/IndexMap` / `wqbcs/moon_collections` / `Hhsqoo/moon-collections`:
  它们是有序哈希表(单索引、保留插入序);本库是多路查找结构。
- **不依赖** `aurasuisui/bimap` 或 `aurasuisui/indexmap`:同作者作品,思路延续,代码独立。

## 文档

- 文档枢纽/全量地图:[`docs/README.md`](docs/README.md)
- API 唯一真源:[`docs/SPEC.md`](docs/SPEC.md)
- 立项设计稿(为什么这么设计):[`docs/DEVPLAN.md`](docs/DEVPLAN.md)
- 开发圣经:[`CONTRIBUTING.md`](CONTRIBUTING.md)

## Gotchas

(随实现补充)

- 唯一索引冲突**不覆盖**:`insert` / `update` 返回 `Err(UniqueViolation(...))`,且**返回前不做任何变更**。
- 有序索引与非唯一索引的键类型相同;若同一字段既要唯一又要有序,请注册两条索引(各自维护,互不干扰)。

## 致谢与来源

**主要参考**:[Rust `multi_index_map`](https://github.com/lun3x/multi_index_map) v0.15.1(**MIT** 许可)
——同样"记录 + N 索引"的容器,后备存储用 `slab::Slab` + 每索引一张查找表(`HashMap`/`BTreeMap`)。
本库的索引分类(唯一 / 非唯一 / 有序)与"冲突不改变容器"的语义与之一致。
完整的许可证核查与 API 对照见 [`docs/SPEC.md`](docs/SPEC.md) §0。

**本库的原创新增**(这些在主蓝本中不存在):

1. **代际 `RowId`(ABA 防护)** —— 主蓝本的 `Slab` 槽位复用不带代际号,陈旧下标会静默命中复用该槽的**新**元素。
2. **范围查询** —— 主蓝本的 ordered 索引只暴露点查与全量遍历,**没有 range**;本库提供 `range_by` / `range_inclusive_by` / `iter_asc_by` / `iter_desc_by`。
3. **绝不 panic、且冲突时归还记录** —— 主蓝本 `insert` 冲突直接 panic,`modify_by_*` 冲突时更是**先删旧键再 panic,留下脏索引**;本库只有 `Result`,且 `Rejected[K,V]` 把记录原样还给调用方。
4. **代际号溢出即退役槽位** —— 所有 Rust 参考实现都选择静默回绕(bevy 文档明写 "generations can (and do) wrap or alias");本库让陈旧句柄永不复活。
5. **运行时注册索引**(闭包投影)—— 主蓝本依赖 derive 宏;MoonBit 无等价机制,故采用运行时注册,代价是索引名运行时校验,收益是可动态增删/枚举索引。
6. **插入序语义** —— 主蓝本按槽位序遍历;本库额外维护 `order`。
7. **公开 `verify_invariants()`** —— 主蓝本没有一致性自检 API。

**其他参考**:`slotmap`(Zlib)/ `thunderdome`(MIT OR Apache-2.0)/ `hecs`(MIT OR Apache-2.0)
提供"槽位 + 代际号"稳定键方案的先例;`generational-arena`(**MPL-2.0**)仅借鉴思路、不复制代码。

**文档与测试体系**:沿用同作者的 [`moonbit-bimap`](https://github.com/aurasuisui/moonbit-bimap)
(文档枢纽/SSOT 纪律、SPEC 唯一真源、分层测试、差分夹具生成器)。

**哈希引擎**:如需自研哈希表,将适配自 `aurasuisui/indexmap`(Apache-2.0),**不引入依赖**。

## License

Apache-2.0
