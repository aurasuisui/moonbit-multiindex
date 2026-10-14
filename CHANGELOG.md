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

| 取舍点 | 参考实现 | 本库 | 理由 |
|---|---|---|---|
| 句柄 | `usize` 槽下标 | `RowId{slot, gen}` | **ABA 防护**(原创) |
| 非唯一桶 | `BTreeSet<usize>` | `Array[Int]` | 桶通常很短、常量更小、保持插入序;去重由 I3 保证 |
| 冲突语义 | `try_insert`→`Err`;`insert`→覆盖 | **一律 `Err`,绝不静默覆盖** | 与同作者 `bimap` 的显式冲突上报风格一致 |
| 索引定义 | derive 宏(编译期) | 运行时闭包注册 | MoonBit 无等价宏机制 |

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
