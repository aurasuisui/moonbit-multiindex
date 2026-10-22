# RELEASE_CHECKLIST.md — 发布门禁

> **每次 `moon publish` / bump `moon.mod` 版本之前,逐项跑到全绿。**
> 勾选结果记一行到 `CHANGELOG.md`。任何一项不绿 = 不发版。

## 最近一次已完成:v0.2.1(2026-10-21)

> PATCH 发布:无公开 API 变更,只含文档纪律修复与测试覆盖补齐。下表按当前 HEAD 逐项重跑。

| Tier | 项 | 结果 | 证据 |
|---|---|---|---|
| 0 | `moon fmt --check` | ✅ | exit=0 |
| 0 | `moon check` | ✅ | 0 error |
| 0 | `moon check --deny-warn --target all` | ✅ | 0 warnings 0 errors,全后端 |
| 0 | 接口快照折叠比对(见下方注①) | ✅ | exit=0;`pkg.generated.mbti` 无差异(0.2.1 当次为 `VERSION` 0.2.0→0.2.1 一行) |
| 0 | `moon test` | ✅ | **148/148** |
| 0 | `moon build` | ✅ | exit=0 |
| 0 | 版本单一真源 | ✅ | `moon.mod` 0.2.1 == `src/lib.mbt` 的 `VERSION` 0.2.1(该校验已折进 CI 接口步骤) |
| 0 | `moon.mod` 元数据 | ✅ | `aurasuisui/multiindex` / 0.2.1 / repository / Apache-2.0 |
| 0 | CI 工具链 | ⚠️ | 无法固定(上游只提供 `latest`)→「漂移可检测」:每步打印 `moon version` |
| 1 | 不变量 I1–I9 随机序列每步成立 | ✅ | `property_wbtest.mbt` 的 `check_invariants` 委托公开 `verify_invariants` |
| 1 | 模型对拍逐步一致 | ✅ | `src/model_test.mbt` |
| 1 | 差分测试对参考实现一致 | ✅ | `src/differential_test.mbt` 回放 `multi_index_map` 0.15.1 黄金序列 |
| 1 | 回归钉子仍在 | ✅ | update 撞唯一键零变更;`modify` 双冲突零变更;`insert_or_replace` 双撞键 `abort` |
| 2 | 每条公开 API 有测试 | ✅ | `table_test` 57 / `table_wbtest` 44 / `abort_guard_wbtest` 26 / `property_wbtest` 10 / `property_test` 4 / `json_test` 3 / `model_test` 2 / `differential_test` 1 / `bench_test` 1 = **148** |
| 2 | **行覆盖率** | ✅ | `moon coverage analyze` → **784/805**;`src/index.mbt` 230/230、`src/lib.mbt` 43/43 满覆盖;余 21 行逐条登记为不可达(见 `docs/SPEC.md` §7.1) |
| 2 | `abort` 守卫有断言 | ✅ | `abort_guard_wbtest.mbt` 的 `test "panic …"` 套件;负向对照:注释掉守卫 → 对应测试报 `panic is expected` |
| 2 | 边界:空表/单元素/槽位复用/代际回绕/超长桶/重名注册 | ✅ | 各自有专测(`GEN_MAX` 白盒退役;单桶 1250) |
| 2 | 泛型:自定义键 / Int 边界 | ✅ | 元组键 `(String, Int)`、`(Int, Int, Int)`;`with_capacity(0/-5)` |
| 2 | JSON 往返 | ✅ | `src/json_test.mbt` |
| 3 | 压力用例(10k+ 操作) | ✅ | `src/bench_test.mbt` |
| 3 | 基准无回退 | ⚠️ | 本版未改实现路径,无回退风险;数字沿用 `bench/README.md` |
| 4 | README API 表与 SPEC 一致 | ✅ | 三表未变(本版无 API 变更) |
| 4 | 至少一个可运行示例 | ✅ | `cmd/leaderboard`(独立模块;`moon.mod` 仍 pin `@0.2.0`,M5 升;生成 `moon.work` 时跑本地源码) |
| 4 | `docs/README.md` 地图无孤儿 | ✅ | 脚本逐条解析,孤儿 0;坏链 0 |
| 4 | `CHANGELOG.md` 有本版 entry | ✅ | `## [0.2.1] - 2026-10-21` |
| 4 | 许可证与第三方来源齐备 | ✅ | `LICENSE` / `NOTICE` / `third_party/LICENSES/multi_index_map-MIT.txt` |
| 发布 | 产物不含 PII / 开发态垃圾 | ✅ | `tag b391aa7`(v0.2.1 的 tag 目标)树逐路径核对:56 文件 − `.gitignore` / `.github` = **54 项**(与 0.2.1 发布记录一致);`moon.work`、`_build`、邮件地址命中 **0**。`--dry-run` 在 `202 Accepted` 时客户端 exit=1 属已知假警报,不能据此判断 |
| 发布 | `moon publish` 并确认 `build_status: success` | ✅ | 发布日志 `Server status: 200 OK`;registry 复核(2026-10-22):`latest_version = 0.2.1`、`build_status = success`、`versions = 0.2.1, 0.2.0, 0.1.0` |
| 发布 | 打 tag `v0.2.1` 并推送 | ✅ | `v0.2.1` = `5abe79e`(annotated tag)→ `b391aa7`「chore(release): sync v0.2.1 from dev」 |

> **注① 接口快照的比较方式(2026-10-22 起)**:`moon info` 的拼写随工具链漂移 ——
> `0.1.20261012` 印 `Int`,`0.1.20261016` 起印 canonical `Int32`(同一种类型,纯拼写)。
> 因此本项与 `.github/workflows/ci.yml` 用**同一套折叠比对**,而不是裸 `git diff --exit-code`:
>
> ```bash
> moon info
> sed -E 's/\bInt32\b/Int/g' src/pkg.generated.mbti > /tmp/mbti.new
> git show HEAD:src/pkg.generated.mbti | sed -E 's/\bInt32\b/Int/g' > /tmp/mbti.old
> git checkout -- src/pkg.generated.mbti
> diff -u /tmp/mbti.old /tmp/mbti.new     # 必须 exit 0
> ```
>
> 折叠只吃掉拼写:**新增/删除/改名公开项、真实参数类型变化仍会被抓到**。
> 仓库内提交的是 canonical `Int32`(见 `CHANGELOG.md` 0.2.2 段),所以折叠前后一致;
> 若在旧工具链(印 `Int`)上跑,折叠同样把两侧拉到同一拼写。

## v0.2.2(进行中)

> **表头约定 —— 包内副本是发布前快照**:`moon publish` 打包的是**当时 HEAD 的快照**,因此**包里那份**
> 的 `publish` / `tag` 两行按定义只能是 📌(它们只能在包生成之后才发生)。**仓库 HEAD** 在 publish
> 完成后回填 `publish` + `产物` 两行为 ✅(带 registry 证据),`tag` 行在仓库 HEAD 也保持 📌:tag 打在
> **回填后的那个 commit** 上,它的 sha 记进**下一版**的「历史执行记录」—— 不回填,也不为 tag 再造一个提交
> (理由与完整流程见 [`plans/v0.2.2.md`](plans/v0.2.2.md) §2.4 第 11 条)。
> 行由 **M5**(版本与发布准备)与 **M6**(发布与 tag)填写;发布前一律保持 ⏳,不要提前打勾。

| Tier | 项 | 结果 | 证据 |
|---|---|---|---|
| 0 | `moon fmt --check` | ⏳ | 待填(M5) |
| 0 | `moon check` | ⏳ | 待填(M5) |
| 0 | `moon check --deny-warn --target all` | ⏳ | 待填(M5) |
| 0 | 接口快照折叠比对(见上方注①) | ⏳ | 待填(M5) |
| 0 | `moon test` | ⏳ | 待填(M5) |
| 0 | `moon build` | ⏳ | 待填(M5) |
| 0 | 版本单一真源 | ⏳ | 待填(M5:六处版本号一致) |
| 0 | `moon.mod` 元数据 | ⏳ | 待填(M5) |
| 0 | CI 工具链 | ⏳ | 待填(M5:无法固定,记 `moon version` 与漂移处置) |
| 1 | 不变量 I1–I9 随机序列每步成立 | ⏳ | 待填(M5) |
| 1 | 模型对拍逐步一致 | ⏳ | 待填(M5) |
| 1 | 差分测试对参考实现一致 | ⏳ | 待填(M5) |
| 1 | 回归钉子仍在 | ⏳ | 待填(M5) |
| 2 | 每条公开 API 有测试 | ⏳ | 待填(M5:附测试计数) |
| 2 | 行覆盖率 | ⏳ | 待填(M5) |
| 2 | `abort` 守卫有断言 | ⏳ | 待填(M5) |
| 2 | 边界:空表/单元素/槽位复用/代际回绕/超长桶/重名注册 | ⏳ | 待填(M5) |
| 2 | 泛型:自定义键 / Int 边界 | ⏳ | 待填(M5) |
| 2 | JSON 往返 | ⏳ | 待填(M5) |
| 3 | 压力用例(10k+ 操作) | ⏳ | 待填(M5) |
| 3 | 基准无回退 | ⏳ | 待填(M5) |
| 4 | README API 表与 SPEC 一致 | ⏳ | 待填(M5) |
| 4 | 至少一个可运行示例 | ⏳ | 待填(M5:带 `moon.work` 时跑本地源码) |
| 4 | `docs/README.md` 地图无孤儿 | ⏳ | 待填(M5) |
| 4 | `CHANGELOG.md` 有本版 entry | ⏳ | 待填(M5) |
| 4 | 许可证与第三方来源齐备 | ⏳ | 待填(M5) |
| 发布 | 产物不含 PII / 开发态垃圾 | ⏳ | 待填(M6 回填) |
| 发布 | `moon publish` 并确认 `build_status: success` | ⏳ | 待填(M6 回填,带 registry 证据) |
| 发布 | 打 tag `v0.2.2` 并推送 | 📌 | 按本表表头的包内快照约定;tag sha 记入下一版的历史执行记录 |

## 历史执行记录

### v0.2.0(2026-10-20)

`0.1.0` 于 2026-10-14 发布(`build_status: success`),`0.2.0` 是 MINOR 发布。当时记录:
- `moon test` **102/102**(基线 93)。
- `--dry-run` 服务端 `202 Accepted` + "Dry run completed successfully",客户端 **exit=1**(把 202 当失败);
  真发布返回 `200 OK`、exit=0 —— **不能用 dry-run 退出码判断能否发布**。
- 产物 **53 项**:PII 命中 0、`moon.work` 命中 0;仍含 `bench/ cmd/ docs/ tools/ proofs/ third_party/`、
  `AGENTS.md`、`CONTRIBUTING.md`(`moon.mod` 无排除字段)。
- 注册表:`latest_version = 0.2.0`、`build_status = success`、`versions = 0.2.0, 0.1.0`。
- tag `v0.2.0` → `ea2ea8f`。

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
- [ ] **测试覆盖率有据可查**:`moon coverage analyze -p aurasuisui/multiindex -- -f summary`
      必跑,并在下表记录数字;未覆盖行须逐类归因(「不可达 / 断言过 / 待补」),**不得只报百分比**
- [ ] **每条 `abort` 守卫要么被测到、要么给出不可达论证**(`test "panic …"` 前缀可断言 panic;
      详见 `docs/MOONBIT_REF.md` §7.1)

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
