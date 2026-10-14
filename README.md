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
t.register_unique("email", fn(u) { u.email })
t.register_non_unique("city", fn(u) { u.city })
t.register_sorted("age", fn(u) { u.age })

let id = t.insert(user)              // -> RowId
t.get_by("email", "a@b.c")           // -> 唯一命中
t.iter_by("city", "beijing")         // -> 多条
t.range_by("age", 18, 30)            // -> 范围
```

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

- 记录身份采用「槽位 + 代际号」方案,思路来自 Rust `slotmap` / `generational-arena` 一系。
- 多索引容器的 API 形态参考 Rust `multi_index_map`(详见 [`docs/DEVPLAN.md`](docs/DEVPLAN.md) §7 与 `CHANGELOG.md` 的 Notes/Deviations)。
- 文档体系与测试分层沿用同作者的 `moonbit-bimap`。
- Robin Hood 哈希引擎如需,将适配自 `aurasuisui/indexmap`(Apache-2.0),不引入依赖。

## License

Apache-2.0
