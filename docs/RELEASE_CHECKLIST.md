# RELEASE_CHECKLIST.md — 发布门禁

> **每次 `moon publish` / bump `moon.mod` 版本之前,逐项跑到全绿。**
> 勾选结果记一行到 `CHANGELOG.md`。任何一项不绿 = 不发版。

## 最近一次执行:v0.2.0(2026-10-20)

> `0.1.0` 已于 2026-10-14 发布(`build_status: success`),本次是 **0.2.0** 的 MINOR 发布。下表按当前 HEAD 逐项重跑,
> 不沿用 M7 的记录 —— M7 那次 CI 装的是 `latest`,Tier 0 的 fmt / deny-warn 结论此后已失效。

| Tier | 项 | 结果 | 证据 |
|---|---|---|---|
| 0 | `moon fmt --check` | ✅ | exit=0 |
| 0 | `moon check` | ✅ | 0 error |
| 0 | `moon check --deny-warn --target all` | ✅ | **0 warnings 0 errors**,全后端 |
| 0 | `moon info && git diff --exit-code` | ✅ | exit=0;`pkg.generated.mbti` 仅含 `VERSION` 0.1.0→0.2.0 一行变化 |
| 0 | `moon test` | ✅ | **102/102**(基线 93;`--target js` 亦全绿) |
| 0 | `moon build` | ✅ | exit=0 |
| 0 | 版本单一真源 | ✅ | `moon.mod` 0.2.0 == `src/lib.mbt` 的 `VERSION` 0.2.0;本轮把该校验折进 CI 接口步骤 |
| 0 | `moon.mod` 元数据 | ✅ | `aurasuisui/multiindex` / 0.2.0 / repository / Apache-2.0 / description 一致 |
| 0 | 命名空间是本人 GitHub 账号 | ✅ | `aurasuisui/...`,与已发布的 `aurasuisui/bimap`、`aurasuisui/indexmap` 同命名空间 |
| 0 | CI 工具链 | ⚠️ | **无法固定**(上游只提供 `latest`,12 种写法全 403)→ 改为「漂移可检测」:每步打印 `moon version`,红线处日志可见确切版本 |
| 1 | 不变量 I1–I9 随机序列每步成立 | ✅ | `property_wbtest.mbt` 的 `check_invariants` 委托公开 `verify_invariants` |
| 1 | 模型对拍逐步一致 | ✅ | `src/model_test.mbt`(脚本流 + 随机流,每步比对全部可观测量) |
| 1 | 差分测试对参考实现一致 | ✅ | `src/differential_test.mbt` 回放 `tools/diffgen` 黄金序列(`multi_index_map` 0.15.1) |
| 1 | 回归钉子仍在 | ✅ | update 撞唯一键 → `Err(Conflict)` 零变更;`modify` 双冲突零变更;`insert_or_replace` 双撞键 `abort`(M11 新增) |
| 1 | 冲突后表与调用前一致 | ✅ | 上述回归 + `insert_many` 批内/批外冲突零变更;每步 `verify_invariants` |
| 2 | 每条公开 API 有测试 | ✅ | `table_test` 51 / `table_wbtest` 20 / `property_wbtest` 8 / `property_test` 4 / `json_test` 3 / `model_test` 2 / `bench_test` 1 / `differential_test` 1 ≈ 102 |
| 2 | 边界:空表/单元素/槽位复用/代际回绕/超长桶/重名注册 | ✅ | 各自有专测(`GEN_MAX` 白盒退役;单桶 1250) |
| 2 | 泛型:自定义键 / Int 边界 | ✅ | 元组键 `(String, Int)`、`(Int, Int, Int)`、Int 键;`with_capacity(0/-5)` |
| 2 | JSON 往返 | ✅ | `src/json_test.mbt`:往返保序 + 载入后重新注册索引答案一致 + 畸形输入报错 |
| 3 | 压力用例(10k+ 操作) | ✅ | `src/bench_test.mbt`:5 000 插入 + 2 500 删除 + 2 500 重插,每阶段 `verify_invariants` |
| 3 | 基准无回退 | ⚠️ | 有 v0.2.0 实测基线(`bench/README.md`);**无历史数据可比**与 M7 的差异,只能记录当前数字 |
| 4 | README API 表与 SPEC 一致 | ✅ | README 三表已覆盖 v0.2.0 新增的 `swap_remove` / `insert_or_replace` / `IndexKind` / `index_entries` |
| 4 | 至少一个可运行示例 | ✅ | `cmd/leaderboard`(独立模块) |
| 4 | `docs/README.md` 地图无孤儿 | ✅ | 本轮脚本逐条解析地图内的路径引用,孤儿 **0** |
| 4 | `CHANGELOG.md` 有本版 entry | ✅ | `## [0.2.0] - 2026-10-20`,按 M1–M12 分节,含 Notes / Deviations |
| 4 | 许可证与第三方来源齐备 | ✅ | `LICENSE`(Apache-2.0)、`NOTICE`、`third_party/LICENSES/multi_index_map-MIT.txt` |
| 发布 | `moon publish --dry-run` | ⚠️ | 服务端返回 `202 Accepted` + "Dry run completed successfully",但客户端 **exit=1**(把 202 当失败);**真发布返回 `200 OK`、exit=0**,因此不能用 dry-run 的退出码判断能否发布 |
| 发布 | 产物不含 PII / 开发态垃圾 | ✅ | 解包 **53 项**:PII 命中 **0**、`moon.work` 命中 **0**;仍含 `bench/ cmd/ docs/ tools/ proofs/ third_party/` 与 `AGENTS.md` / `CONTRIBUTING.md`(`moon.mod` 无排除字段,根目录只能整体打包) |
| 发布 | 发布到 mooncakes.io 并确认 `build_status: success` | ✅ | `moon publish` → **`Server status: 200 OK`**、exit=0;registry `latest_version = 0.2.0`、`build_status = success`、`versions = 0.2.0, 0.1.0` |
| 发布 | 打 tag `v0.2.0` 并推送 | ✅ | `git ls-remote --tags` → `ea2ea8f...refs/tags/v0.2.0` |

## 版本策略(semver) —— 每次推送前必读

MoonBit 的包管理遵循**语义化版本**:每个模块必须以 `MAJOR.MINOR.PATCH` 声明版本,
且**每次推送必须递增**:

| 改动性质 | 递增 |
|---|---|
| 不兼容的 API 更改 | **MAJOR** |
| 向后兼容地**新增功能** | **MINOR** |
| 向后兼容的**错误修复** | **PATCH** |

预发布与构建元数据标签可作为 `MAJOR.MINOR.PATCH` 的扩展(例如 `0.2.0-rc.1`)。

> **moon 使用最小版本选择(MVS)**:依赖图取满足约束的**最小**版本。
> 本模块**没有任何第三方依赖**(只用 `moonbitlang/core`),因此 MVS 在本侧没有可解析项 ——
> 但**我们的版本号会被下游的 MVS 使用**:一个版本一旦被消费就不可撤回,
> 因此不兼容改动只有在 **MAJOR** 递增时才被允许。

### 本项目的落地纪律

1. **发布前先判定这次改动的性质**,再决定递增哪一位 —— 不要"习惯性 +0.0.1"。
2. **同一个版本号不能发布两次**;已发布的版本不可修改,只能发新版本。
3. **向后兼容的判据(本项目口径)**:
   - **算兼容**:新增公开方法或类型、**放宽**类型约束、提升性能、修 bug、改文档与测试;
   - **不算兼容**:删除或重命名公开 API、改变既有方法的语义或返回类型、**收紧**类型约束、
     改变序列化线格式、改变既有的错误语义(例如把 `Ok` 变成 `abort`)。
4. **关于 `0.x`**:标准 semver 对 `0.y.z` 有"初始开发期,公开 API 不视为稳定"的豁免,
   但官方这段口径**没有**为 0.x 开例外。本项目**按官方口径从严**:不兼容改动一律递增 **MAJOR**。
   若将来确实要动用 0.x 豁免,**必须在 CHANGELOG 写明理由**,不能默默破例。
5. `moon.mod` 的 `version`、CHANGELOG 的版本段、以及即将推送的版本**三者必须一致**。

---

## Tier 0 — 硬门禁(缺一不可)

- [ ] CI 的工具链版本在日志中可见(上游只提供 `latest`,**无法固定**;改为「漂移可检测」:每步打印 `moon version`,升级单独 commit 且全绿)
- [ ] `moon fmt --check` 干净
- [ ] `moon check` 0 error
- [ ] `moon info && git diff --exit-code` 干净(`src/pkg.generated.mbti` 已提交)
- [ ] `moon test` 全绿
- [ ] `moon build` 通过
- [ ] `moon.mod` 的 `name` / `version` / `repository` / `license` / `description` 与实际一致
- [ ] `name` 的命名空间是**本人 GitHub 账号**(`aurasuisui/...`),否则 mooncakes 发布会失败

## Tier 1 — 正确性

- [ ] 不变量 `check_invariants`(I1–I9)在随机序列每步后成立
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
- [ ] 产物清单逐条核对:无个人信息、无开发态文件(`_build` / `moon.work` / `bench` / `cmd`),清单留档
- [ ] 发布后到 mooncakes.io 确认页面可访问、README 正常渲染
- [ ] 打 tag 并推送
