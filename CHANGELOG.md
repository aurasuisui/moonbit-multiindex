# Changelog

All notable changes to `aurasuisui/multiindex` are documented here.
格式参考 [Keep a Changelog](https://keepachangelog.com/);版本号遵循 [SemVer](https://semver.org/)。

---

## [Unreleased]

### Added
- 立项:仓库骨架、文档体系(枢纽/SPEC/DEVPLAN/开发圣经/会话入口)、CI 五步门禁。
- `RowId`(槽位 + 代际号)与 `Conflict[K]`(唯一冲突上报,无冗余变体)。
- 设计稿 `docs/DEVPLAN.md`,含探针验证记录与三条高危路径。

#### M1 — 记录存储(2026-10-14)

- **`Table[K, V]` 骨架**:`rows`(槽位存储)/ `gens`(代际号)/ `free`(空闲栈)/
  `order`(插入序)/ `indexes`(索引注册表)+ `len` / `version`,字段全部私有。
- **无索引基础操作**:`insert` / `get` / `remove` / `len` / `is_empty` / `clear` /
  `iter`(插入序,比照 `version` 的 fail-fast)。
- **槽位分配与回收**:空闲栈 **LIFO** 复用;删除时 `gens[slot] += 1` 并归还槽位;
  陈旧 `RowId`(代际不匹配)的 `get` / `remove` 一律返回 `None`,且**不触碰槽位的新占用者**。
- **I9**:代际号达到上限(`GEN_MAX`)的槽位**永久退役**,不再回到 `free`(上限取值见下方 Notes)。
- `Rejected[K, V]`(冲突 + 记录原样归还),并补 `Show` for `Conflict[K]` / `Rejected[K, V]`。
- 测试(19 条):`table_test.mbt` 单元 7 条;`property_test.mbt` 随机序列 2 条;
  `property_wbtest.mbt` `check_invariants`(I1/I2/I6 + I9 形式)+ 随机序列每步校验 + 3 条
  "校验器非空转"元测试(共 4 条);`table_wbtest.mbt` 白盒 6 条(LIFO 复用 / 代际单调 / I9 退役 /
  陈旧句柄不误伤 / I8 version / `clear` 台账)。

### Notes / Deviations
- **`Conflict` 故意没有「无冲突」变体**:无冲突用 `Option::None` 表达。加变体会与
  `Option::None` 在 match 位置混淆,并迫使调用方匹配一个不可能出现的 `Err`。
  (探针实测踩中,见 `docs/SPEC.md` §9)\
- **结构体泛型不带 trait 约束**(MoonBit 语法限制):约束写在方法上,与 bimap 保持一致。
- **不变量 I5 的由来**:最初的校验只覆盖 I3/I4,探针实测发现"更新成已占用的唯一键"可让唯一桶
  出现两个持有人而校验仍通过;由此补上 **I5(唯一桶长度 ≤ 1)**,并确立"I5 与 I7 成对校验"的纪律。

#### M1 记录存储(2026-10-14)

- **代际号上限 `GEN_MAX = 1 << 62`**(私有常量,`src/table.mbt`)。理由:远超任何实际可达的
  复用次数;且 `GEN_MAX + 1` 仍落在 64 位有符号 `Int` 内,判定退役的比较本身不会溢出。
  `gens[slot] == GEN_MAX` 的活记录被删除时,该槽**退役**(不入 `free`),其代际号保持不变。
  **SPEC §2.1 未规定上限取值** —— 已在交付报告里提请审核会话裁定并写入 SPEC 待裁定项。
- **`clear()` 使旧句柄失效(ABA 安全)**:`clear` 不是"把数组清空",而是**批量退役**每个活槽
  (行清空、代际号 +1、槽位归还 `free`;代际耗尽的槽永久退役)。否则清空后重新插入会**复用
  同一个槽位与同一个代际号**,使 `clear` 之前的句柄静默命中新记录 —— 与本库的 ABA 防护主旨冲突。
  实现走专门的**批量汇聚点** `clear_impl`(O(n)),而不是循环 `remove_impl`(经由 `order` 压缩
  会退化成 O(n²));这是 `insert_impl` / `remove_impl` 之外的第四条路径,角色等同 bimap 的 `retain`。
  **SPEC §3.2 只写了"清空所有记录与索引",未规定句柄语义** —— 提请审核会话裁定。
- **`clear()` 与 I8**:清空**空表**不改变任何可观测状态,因此不递增 `version`(I8:"仅在真实变更时递增")。
- **测试文件布局**:MoonBit 把 `*_test.mbt` 编译成**外部包**(黑盒),`*_wbtest.mbt` 才在包内。
  因此 I1(「`order` 全是活槽且不重复」)与 I6(「`free` 无重复且与活槽不相交」)只能断言在
  `property_wbtest.mbt` 的 `check_invariants` 里;`property_test.mbt` 承担同一批属性的**可观测投影**
  (len/iter/get/陈旧句柄),两者都在随机序列**每一步之后**校验。这也与 `CONTRIBUTING.md` 测试约定
  ("不变量断言走公开 API,私有字段断言放 `*_wbtest.mbt`")一致。
- **M1 只声明不实现的 M2 形态**:按执行交接书 §四 选定方案 (b),把索引注册表字段与
  `Index` / `IndexMeta` 一次声明到位(不实现任何桶操作)。代价是 `moon check` 多出
  6 条 dead-code 警告(4 个未构造的 `Index` 变体 + `IndexMeta` 未构造 + 2 个未读字段);
  `moon check` 仍为 **0 error**,M2 落地后自然消失。

#### 与参考实现 `multi_index_map` 的取舍(`docs/SPEC.md` §0.3)

| 取舍点 | 参考实现 `multi_index_map` 0.15.1 | 本库 | 理由 |
|---|---|---|---|
| 句柄 | `usize` 槽下标 | `RowId{slot, gen}` | **ABA 防护**(原创) |
| 非唯一桶 | `BTreeSet<usize>` | **`SortedSet[Int]`(采纳同一路线)** | 初稿选 `Array[Int]` 以保插入序,但**大桶下 O(k) 线性删除不可接受**;参考实现 0.6.0 已因性能把 `Vec` 换成 `BTreeSet`。**代价:桶内顺序变为槽位号升序** |
| 冲突语义 | `try_insert`→`Err`(归还元素);`insert`→**panic** | **只有 `Result`,且归还记录**(`Rejected[K,V]`);绝不 panic | MoonBit 的 panic 等价 abort;记录按值传递,不归还则调用方**丢失数据** |
| `modify` 原子性 | 先删旧键再插新键,**失败则 panic 并留下脏索引**(缺陷) | **先全量预检,再一次性提交** | 修正上游缺陷 |
| 范围查询 | **无**(ordered 索引只暴露点查与全量遍历) | `range_by` / `range_inclusive_by` / `iter_asc_by` / `iter_desc_by` | 上游 API 层缺口,本库增量 |
| 代际号溢出 | **静默回绕**(slotmap / thunderdome / hecs / bevy 一致) | **溢出即退役槽位** | 陈旧句柄永不复活(不变量 I9) |
| 索引定义 | derive 宏(编译期) | 运行时闭包注册 | MoonBit 无等价宏机制 |
| 更新路径 | `update_by_*`(仅未索引字段)+ `modify_by_*` | 只有 `modify`,内部**逐索引键对比**只动变化的桶 | MoonBit 无法返回指向数组元素的 `&mut` 投影 |

**许可证**:主蓝本 `multi_index_map` 为 MIT(兼容本项目 Apache-2.0,已在 README 致谢保留归属);
`generational-arena` 为 MPL-2.0,**仅借鉴思路、未复制代码**。详见 `docs/SPEC.md` §0。

---

## [0.1.0] - 计划中(2026-10-31 前)

目标:通过十月黑客松验收,发布到 mooncakes.io。

- 核心:记录存储 + 稳定 ID + 唯一/非唯一/有序索引
- 查询:`get_by` / `iter_by` / `range_by`
- 写入:`insert` / `update` / `remove`(含冲突上报与不变量自检)
- 序列化:JSON 往返
- 工程:对拍测试、QuickCheck、基准、三平台 CI、README/示例/WASM demo
