# RELEASE_CHECKLIST.md — 发布门禁

> **每次 `moon publish` / bump `moon.mod` 版本之前,逐项跑到全绿。**
> 勾选结果记一行到 `CHANGELOG.md`。任何一项不绿 = 不发版。

## 最近一次执行:M7(2026-10-14,执行会话)

> 逐项跑过并记录证据;最后三条(实际发布)是**不可逆的外部动作**,按派发要求**等用户确认,未执行**。

| Tier | 项 | 结果 | 证据 |
|---|---|---|---|
| 0 | `moon fmt --check` | ✅ | exit=0 |
| 0 | `moon check` | ✅ | 0 error |
| 0 | `moon check --deny-warn --target all`(M6 起新增) | ✅ | **0 warnings 0 errors**,四个后端 |
| 0 | `moon info && git diff --exit-code` | ✅ | exit=0(`src/pkg.generated.mbti` 已提交) |
| 0 | `moon test` | ✅ | **78/78**(`--target js` 亦 78/78) |
| 0 | `moon build` | ✅ | exit=0 |
| 0 | `moon.mod` 元数据 | ✅ | `aurasuisui/multiindex` / 0.1.0 / repository / Apache-2.0 / description 均与仓库一致 |
| 0 | 命名空间是本人 GitHub 账号 | ✅ | `aurasuisui/...`,与已发布的 `aurasuisui/bimap`、`aurasuisui/indexmap` 同命名空间 |
| 1 | 不变量在随机序列每步后成立 | ✅ | `property_wbtest.mbt` 的 `check_invariants` **委托**公开 `verify_invariants`(I1–I9 + 索引不变量),随机序列每步调用 |
| 1 | 模型对拍与朴素实现逐步一致 | ✅ | `src/model_test.mbt`(脚本流 + 随机流 12×50 步,每步比对全部可观测量) |
| 1 | 差分测试对参考实现一致 | ✅ | `src/differential_test.mbt` 回放 `tools/diffgen` 生成的黄金序列(`multi_index_map` 0.15.1) |
| 1 | 回归钉子仍在 | ✅ | update 撞唯一键 → `Err(Conflict)` 且**逐条**比对零变更;`modify` 双冲突零变更 |
| 1 | 冲突后表与调用前一致 | ✅ | 上述回归 + `insert_many` 的批内/批外冲突零变更;`verify_invariants` 每步复查 |
| 2 | 每条公开 API 有测试 | ✅ | `table_test` 37 / `table_wbtest` 20 / `json_test` 3 / `bench_test` 1,覆盖 mbti 列出的全部方法 |
| 2 | 边界:空表 / 单元素 / 槽位复用 / 代际回绕 / 超长桶 / 重名注册 | ✅ | 各自有专测(代际回绕:`GEN_MAX` 白盒退役;超长桶:`bench_test` 单桶 1250) |
| 2 | 泛型:自定义键 / Int 边界 | ✅ | 元组键 `(String, Int)`、`(Int, Int, Int)` 与 Int 键;`with_capacity(0/-5)` |
| 2 | JSON 往返(如有) | ✅ | `src/json_test.mbt`:往返保序 + 载入后重新注册索引答案一致 + 畸形输入报错 |
| 3 | 压力用例(10k+ 操作) | ✅ | `src/bench_test.mbt`:5 000 插入 + 2 500 删除 + 2 500 重插,每阶段 `verify_invariants` |
| 3 | 基准无回退 | ⚠️ | 有实测基线(`bench/README.md`,native+release);**无历史数据可对比**,“回退”只能与本次基线比 |
| 4 | README API 表与 SPEC 一致 | ✅ | README 新增 API 三表(构造/写入/查询/诊断),与 SPEC §3 逐项对齐 |
| 4 | 至少一个可运行示例(Cmd) | ✅ | `cmd/leaderboard`(独立模块,需先发布;**M6 已用临时 workspace 实跑通过**) |
| 4 | `docs/README.md` 地图无孤儿 | ✅ | 未新增/删除文档;M7 新增的 `src/json_test.mbt` 是测试文件,不入文档地图 |
| 4 | `CHANGELOG.md` 有本版 entry | ✅ | `[Unreleased]` 下 M1–M7 分节,含 Notes/Deviations |
| 4 | 许可证与第三方来源齐备 | ✅ | `LICENSE`(Apache-2.0)、`NOTICE`、`third_party/LICENSES/multi_index_map-MIT.txt` |
| 发布 | `moon publish --dry-run` | ✅ | M6/M7 各跑过一次:打包 + 解包后 `moon check` 通过 |
| 发布 | 产物不含开发态文件 | ❌ | 实测产物 zip **含** `moon.work` / `bench/` / `cmd/` / `docs/` / `AGENTS.md` 等;见 M7 报告的产物清单与建议 |
| 发布 | 发布到 mooncakes.io 并确认页面 | ⬜ | **等用户确认后执行**(不可逆动作,执行会话不自行发布) |
| 发布 | 打 tag 并推送 | ⬜ | 同上 |

---
## Tier 0 — 硬门禁(缺一不可)

- [ ] `moon fmt --check` 干净
- [ ] `moon check` 0 error
- [ ] `moon info && git diff --exit-code` 干净(`src/pkg.generated.mbti` 已提交)
- [ ] `moon test` 全绿
- [ ] `moon build` 通过
- [ ] `moon.mod` 的 `name` / `version` / `repository` / `license` / `description` 与实际一致
- [ ] `name` 的命名空间是**本人 GitHub 账号**(`aurasuisui/...`),否则 mooncakes 发布会失败

## Tier 1 — 正确性

- [ ] 不变量 `check_invariants`(I1–I8)在随机序列每步后成立
- [ ] 模型对拍(`model_test.mbt`)与朴素实现逐步一致
- [ ] 差分测试(`differential_test.mbt`)对参考实现的观测序列一致
- [ ] 回归测试钉子(特别是 update 冲突漏洞)仍在
- [ ] 冲突路径:**返回 `Err` 后表与调用前完全一致**

## Tier 2 — 覆盖面

- [ ] 每条公开 API 至少有单元测试
- [ ] 边界:空表、单元素、槽位复用、代际号回绕、超长桶、重复注册索引名
- [ ] 泛型:自定义 struct 键、Int 边界键
- [ ] JSON 往返(如有):往返恒等 + 冲突/畸形输入报错

## Tier 3 — 性能与压力

- [ ] `bench_test.mbt` 压力用例通过(10k+ 操作)
- [ ] 基准无回退(`bench/main.mbt`,native + release)

## Tier 4 — 文档与发布面

- [ ] `README.md` 的 API 表与 `docs/SPEC.md` 一致
- [ ] 至少一个可直接运行的示例(`cmd/`)
- [ ] `docs/README.md` 地图无孤儿条目
- [ ] `CHANGELOG.md` 有本次版本的 entry(含 Notes / Deviations)
- [ ] 许可证与第三方来源说明齐备(见 `docs/DEVPLAN.md` §7)

## 发布前必检

- [ ] `moon publish --dry-run`(如支持)无意外
- [ ] 发布后到 mooncakes.io 确认页面可访问、README 正常渲染
- [ ] 打 tag 并推送
