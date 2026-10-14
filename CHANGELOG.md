# Changelog

All notable changes to `aurasuisui/multiindex` are documented here.
格式参考 [Keep a Changelog](https://keepachangelog.com/);版本号遵循 [SemVer](https://semver.org/)。

---

## [Unreleased]

### Added
- 立项:仓库骨架、文档体系(枢纽/SPEC/DEVPLAN/开发圣经/会话入口)、CI 五步门禁。
- `RowId`(槽位 + 代际号)与 `Conflict[K]`(唯一冲突上报,无冗余变体)。
- 设计稿 `docs/DEVPLAN.md`,含探针验证记录与三条高危路径。

### Notes / Deviations
- **`Conflict` 故意没有「无冲突」变体**:无冲突用 `Option::None` 表达。加变体会与
  `Option::None` 在 match 位置混淆,并迫使调用方匹配一个不可能出现的 `Err`。
  (探针实测踩中,见 `docs/SPEC.md` §9)\
- **结构体泛型不带 trait 约束**(MoonBit 语法限制):约束写在方法上,与 bimap 保持一致。
- **不变量 I5 的由来**:最初的校验只覆盖 I3/I4,探针实测发现"更新成已占用的唯一键"可让唯一桶
  出现两个持有人而校验仍通过;由此补上 **I5(唯一桶长度 ≤ 1)**,并确立"I5 与 I7 成对校验"的纪律。

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
