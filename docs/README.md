# docs/ — 文档枢纽(全量地图)

> **这是整个仓库文档的唯一入口与目录。** 每份文档都在这里登记了**角色**和**存活状态**。
> **新增或删除任何文档,必须同步更新本表**——这是防"零碎死文件"的第一道闸(配合
> `CONTRIBUTING.md` 的文档同步约定)。

## 单一真源(SSOT)纪律

每条事实**只住一个文件**,别处只链接、不复制。复制是文档漂移和死文件的根源。

| 这条信息 | 唯一的家 |
|---|---|
| 是什么 / 为什么 / 用法 / API 概览 / Gotchas | [`README.md`](../README.md) |
| 架构深挖 / 开发流程 / 测试约定 / **文档同步约定** | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |
| 每次改动与关键决策 | [`CHANGELOG.md`](../CHANGELOG.md) |
| API 契约(每个签名、不变量、错误语义) | [`SPEC.md`](SPEC.md) |
| **命名 / 代码组织 / 文档注释 / 测试风格 / CI / license 的官方约定** | [`STYLE.md`](STYLE.md) |
| 会话入口(命令 + 架构速览 + 阅读顺序) | [`AGENTS.md`](../AGENTS.md)(**唯一**入口,面向所有编码 agent) |

## 文档地图

### 活文档(长期维护)

| 文件 | 角色 | 何时读 |
|---|---|---|
| [`../README.md`](../README.md) | 产品门面:用途、与 bimap/indexmap 的区别、API 表、Gotchas、致谢 | 想了解项目 |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | 开发圣经:架构深挖、加功能清单、测试约定、**文档同步约定** | 要改代码 |
| [`../CHANGELOG.md`](../CHANGELOG.md) | 发布历史 + 每次决策的 Notes/Deviations | 想知道改过什么 |
| [`../AGENTS.md`](../AGENTS.md) | **唯一会话入口**:命令、架构速览、不变量、测试约定、阅读顺序 | 每个会话开头 |
| [`SPEC.md`](SPEC.md) | **API 唯一真源**:签名/返回类型/语义,行为拿不准时以此为准 | 动公开 API |
| [`DEVPLAN.md`](DEVPLAN.md) | 立项设计稿:数据布局、不变量、**四条高危路径**、探针验证记录 | 想理解为什么这么设计 |
| [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) | **发布门禁**:每次 bump 版本前必须逐项全绿的 Tier 0–4 | 准备发版 |
| [`STYLE.md`](STYLE.md) | **官方代码约定与风格**(实测自 `moonbitlang/core` 仓库 + 官方 CI):命名、代码组织、`extend` 策略、文档注释、测试、包布局、license;**含 §H 可执行清单与 §I 未核实表** | 写代码前;**加 CI 门禁前** |
| [`MOONBIT_REF.md`](MOONBIT_REF.md) | MoonBit 语法/惯用法速查 **实测版**:三级可信度标记(已实测 41 / 源码 23 / 文档 14 / 未核实 1),含 20 条错误码对照与「最容易踩的十条」 | 写 MoonBit 卡壳;**动 API 前先查** |
| [`SESSION_PLAYBOOK.md`](SESSION_PLAYBOOK.md) | **任务会话手册**:讨论方案→执行→卡住决策→看门狗→知识回写 | 开新任务会话 |
| [`plans/v0.1.0.md`](plans/v0.1.0.md) | v0.1.0 **范围与里程碑**(含出口条件)+ **进度看板**;**§一 说明为何不是移植** | 想知道做到哪了、下一步做什么 |
| [`plans/v0.2.0.md`](plans/v0.2.0.md) | v0.2.0 **范围与里程碑**:先清 §七 的发布基线阻断项(M7.5),再修掉基准实测出的两个性能弱点 + 补齐验收口径要求的 Issues/PR | 想知道 v0.2 做什么 |
| [`plans/execution-brief.md`](plans/execution-brief.md) | **执行/审核分工契约**:执行纪律、出口条件、审核验收清单;**§四 已同步到 v0.2.0 的 M7.5 → M8** | 执行会话开工前 / 审核会话验收时 |
| [`research/rust-ecosystem-2026-10-14.md`](research/rust-ecosystem-2026-10-14.md) | **Rust 生态调研报告**(逐行读 `generators.rs` 的源码级核对:许可证/API/实现/缺口) | 想核对"为什么这么设计"的依据时 |
| [`../NOTICE`](../NOTICE) | 第三方来源与许可证归属(移植/参考合规) | 发版前、被问来源时 |
| [`../tools/diffgen/README.md`](../tools/diffgen/README.md) | 差分夹具生成器(参考实现:Rust `multi_index_map` v0.15.1;开发工具,非包内容) | 重新生成差分夹具时 |
| [`../bench/README.md`](../bench/README.md) | 计时基准(官方 `@bench` 框架,native+release) | 跑/解读性能基准时 |
| `README.md`(本文件) | 文档枢纽/全量地图 | 不知道读哪份 |

### 一次性 / 归档(只读,不再维护)

| 文件 | 角色 |
|---|---|
| [`申报书.md`](申报书.md) | 2026 MoonBit 10 月黑客松项目申报书(验收 10/31) |

## 阅读顺序

**新会话快速上手**(约 5 分钟):
`AGENTS.md` → `README.md` → `CONTRIBUTING.md` → 动 API 才读 `docs/SPEC.md`。

**开任务会话**(测试 / 改进 / 新功能):
`AGENTS.md` → `docs/SESSION_PLAYBOOK.md` → 按任务读 `docs/SPEC.md` / `CONTRIBUTING.md`。

**准备发版**(bump `moon.mod` 版本):
`AGENTS.md` → `docs/RELEASE_CHECKLIST.md`(逐项全绿)→ 勾选结果记一行进 `CHANGELOG.md`。
