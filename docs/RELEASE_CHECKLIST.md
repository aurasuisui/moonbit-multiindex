# RELEASE_CHECKLIST.md — 发布门禁

> **每次 `moon publish` / bump `moon.mod` 版本之前,逐项跑到全绿。**
> 勾选结果记一行到 `CHANGELOG.md`。任何一项不绿 = 不发版。

## v0.2.1(2026-10-21,历史)

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

## v0.2.2(2026-10-22 发布,历史)

> **表头约定 —— 包内副本是发布前快照**:`moon publish` 打包的是**当时 HEAD 的快照**,因此**包里那份**
> 的 `publish` / `tag` 两行按定义只能是 📌(它们只能在包生成之后才发生)。**仓库 HEAD** 在 publish
> 完成后回填 `publish` + `产物` 两行为 ✅(带 registry 证据),`tag` 行在仓库 HEAD 也保持 📌:tag 打在
> **回填后的那个 commit** 上,它的 sha 记进**下一版**的「历史执行记录」—— 不回填,也不为 tag 再造一个提交
> (理由与完整流程见 [`plans/v0.2.2.md`](plans/v0.2.2.md) §2.4 第 11 条)。
> 行由 **M5**(版本与发布准备)与 **M6**(发布与 tag)填写;发布前一律保持 ⏳,不要提前打勾。

| Tier | 项 | 结果 | 证据 |
|---|---|---|---|
| 0 | `moon fmt --check` | ✅ | 2026-10-22 本机 `moon 0.1.20261020`:`moon fmt --check` → `Finished. moon: no work to do`,exit 0 |
| 0 | `moon check` | ✅ | `moon check` → exit 0(`Finished. moon: no work to do`) |
| 0 | `moon check --deny-warn --target all` | ✅ | exit 0,`moon: ran 12 tasks, now up to date`(wasm / wasm-gc / js / native 全查) |
| 0 | 接口快照折叠比对(见上方注①) | ✅ | **内容判据**:`moon info` 后 `git diff --quiet -- src` **exit 0**。注意 `git status` 会误报 —— 本机 `core.autocrlf=true`,`moon info` 重写该文件后 `git status` 报 ` M src/pkg.generated.mbti`,但 `git hash-object` 与 `git rev-parse HEAD:src/pkg.generated.mbti` **同为 `f51b733f…`**、`git diff` 为空,`git add --refresh` 也不消失(2026-10-22 复现);**别用 `git status` 判接口快照漂移**。101 行经 `\bInt32\b → Int` 折叠后与 HEAD 逐行一致(`Compare-Object` 无差异) |
| 0 | `moon test` | ✅ | `Total tests: 148, passed: 148, failed: 0.`,exit 0 |
| 0 | `moon build` | ✅ | exit 0(`moon: ran 1 task, now up to date`) |
| 0 | 版本单一真源 | ✅ | 六处均 `0.2.2`:`moon.mod:3`、`src/lib.mbt:23`、`src/pkg.generated.mbti:10`(`moon info` 生成)、`cmd/leaderboard/moon.mod:2`、`bench/moon.mod:2`、`README.md:39`;CI 的 version single-source 步(`ci.yml:77-85`)比对 `moon.mod` 与 `src/lib.mbt` |
| 0 | `moon.mod` 元数据 | ✅ | `name` / `version` / `readme` / `repository` / `license = "Apache-2.0"` / 5 个 `keywords` / `description` / `source = "src"` 齐备(`moon.mod:1-21`) |
| 0 | CI 工具链 | ✅(不可固定) | 本机 `moon 0.1.20261020 (2284bd2 2026-10-20)`;`cli.moonbitlang.com` 只服务 latest,钉版本会 403,故 CI 装 latest、每步打印 `moon version`,漂移靠 `moon fmt --check` 与接口步「检测而非预防」(`AGENTS.md` Commands 注) |
| 1 | 不变量 I1–I9 随机序列每步成立 | ✅ | `moon test -f "*qc:*"` 7/7;驱动 `src/property_wbtest.mbt:96`(随机 insert/remove 每步)、`:147`(I3/I4/I5/I7)、`:372`(update/modify);7 条 `the invariant guard is not vacuous` 元测试(`:214`–`:313`)证明守卫非空转 |
| 1 | 模型对拍逐步一致 | ✅ | `moon test -f "*model differential*"` 2/2:`src/model_test.mbt:385`(脚本流)、`:436`(随机流),每步对 `Array[V]` 线性扫描 oracle |
| 1 | 差分测试对参考实现一致 | ✅ | `moon test -f "*golden stream*"` 1/1:`src/differential_test.mbt:103` 回放 `src/differential_fixture_test.mbt` 的黄金序列(对 Rust `multi_index_map` 0.15.1) |
| 1 | 回归钉子仍在 | ✅ | `moon test -f "*regression*"` 1/1:`src/table_test.mbt:597`(update 撞已占用 unique key 时表不变) |
| 2 | 每条公开 API 有测试 | ✅ | 32 个 `pub fn Type::method` 全部在 `*test.mbt` 中被调用(脚本比对,missing=0);全量 148 条测试 |
| 2 | 行覆盖率 | ✅ 784/805(97.4%) | `moon test --enable-coverage` → 148/148;`$env:MOON_COVE_REPORT_ENABLED='0'; moon coverage analyze -p aurasuisui/multiindex -- -f summary` → `src/table.mbt: 241/243`、`src/table_api.mbt: 258/277`、`Total: 784/805`,与 0.2.1 持平 ⇒ 无回退。缺口均为 `abort`/`Err` 分支(`-f caret` 21 行,如 `src/table.mbt:409`、`src/table_api.mbt:567-573` 的 I5 文本)。注:新 reporter 报 `conflicting trace metadata ...$index`,故用 legacy reporter |
| 2 | `abort` 守卫有断言 | ✅ | `moon test -f "*panic*"` 20/20;`src/abort_guard_wbtest.mbt` 26 条 = 19 条 `test "panic …"` + 7 条 companion(`:701`/`:714`/`:720`/`:729`),每条 panic 夹具都被复跑 |
| 2 | 边界:空表/单元素/槽位复用/代际回绕/超长桶/重名注册 | ✅ | `table_test.mbt:118`(空表)、`:1288`(删掉最后一条)、`:167`(回收槽拒绝旧 handle)、`table_wbtest.mbt:102`(I9 代际耗尽即退休)、`bench_test.mbt:10`(长桶 `n/4 → n/8`)、`table_test.mbt:252`/`:382`/`:403`(重名注册被拒且不改状态) |
| 2 | 泛型:自定义键 / Int 边界 | ✅ | `table_test.mbt:199`(未注册索引时键类型无约束,用元组键)、`:913`(失败分类固定 abort 判据);`table_wbtest.mbt:102` 覆盖代际上限路径 |
| 2 | JSON 往返 | ✅ | `json_test.mbt` 3 条:round-trip 保插入序(`:9`)、重注册后答案一致(`:40`)、畸形输入报错不静默(`:91`) |
| 3 | 压力用例(10k+ 操作) | ✅ | `bench_test.mbt:10`:共 10 000 次操作(5 000 insert + 2 500 remove + 2 500 复用 insert,全程 `verify_invariants`) |
| 3 | 基准无回退 | ✅(未改实现路径) | `git diff v0.2.1..HEAD -- src` 中 `src/*.mbt` 只有 `src/lib.mbt:23` 的 VERSION 一行(`pkg.generated.mbti` 的其余差异是 M2 的 `Int → Int32` 拼写重生成,无语义);沿用 `bench/README.md:154-171` 的实测:`get_by` 0.24 vs 59.3 µs、窄 range 6.4 vs 84.1 µs、`insert` k=1/8 = 0.98/11.6 µs、`remove` 54.5/69.4 µs |
| 4 | README API 表与 SPEC 一致 | ✅ | 32 个公开方法名全部出现在 README;SPEC §11:697 以 `ToJson`/`FromJson` trait 登记 JSON 入口,README:174 写方法名 `to_json()`/`Table::from_json` —— trait↔method 表述差,已列报告 |
| 4 | 至少一个可运行示例 | ✅ | 生成 `moon.work`(`members = [".", "bench", "cmd/leaderboard"]`)后 `cd cmd/leaderboard && moon run .` → exit 0、34 行、首行 `== aurasuisui/multiindex VERSION: 0.2.2 (local workspace module) ==`、含 `verify_invariants: Ok`。发布前**无** `moon.work` 会因 `@0.2.2` 尚未上架而解析失败(实测 `no version satisfies requirement 0.2.2`),发布后即回落到注册表版本;CI 的 example-smoke 覆盖 workspace 路径 |
| 4 | `docs/README.md` 地图无孤儿 | ✅ | 20 个 md 文件全部在 `docs/README.md` 有对应行(脚本比对,unlisted=0);全仓相对链接 100 条、真实坏链 0(M4 检查) |
| 4 | `CHANGELOG.md` 有本版 entry | ✅ | `f478c17` 写入 `## [0.2.2] - 2026-10-22`:含 D1–D11 修复、CI 八项、六处版本升版与 mbti 重生成,末行 `<!-- 发布结果由 M6 回填 -->` |
| 4 | 许可证与第三方来源齐备 | ✅ | `LICENSE`(Apache-2.0 正文)、`third_party/LICENSES/multi_index_map-MIT.txt`、README「致谢与来源」:224、CHANGELOG 的 Notes/Deviations 归属 |
| 发布 | 产物不含 PII / 开发态垃圾 | ✅ | `moon package` 独立复跑:`_build/publish/aurasuisui-multiindex-0.2.2.zip` **55 项**(0.2.1 为 54 项,唯一新增 `docs/plans/v0.2.2.md`);PII 扫描 0 真命中;`moon.work` / `_build/` / `.exe` 命中 0;六处版本全为 `0.2.2` |
| 发布 | `moon publish` 并确认 `build_status: success` | ✅ | 2026-10-22 `moon publish` → `Server status: 200 OK`,exit 0(单次发布,未重试);registry 复核(`https://mooncakes.io/api/v0/manifest/aurasuisui/multiindex`):`latest_version = 0.2.2`、`build_status: success`、`yanked: false`、`versions = 0.2.2, 0.2.1, 0.2.0, 0.1.0` |
| 发布 | 打 tag `v0.2.2` 并推送 | 📌 | 按本表表头的包内快照约定;tag sha 记入下一版的历史执行记录 |

### M5 的 dry-run 与解包核对(2026-10-22)

| 项 | 实测 |
|---|---|
| 命令 | `moon publish --dry-run`(本机 `moon 0.1.20261020`) |
| 服务端 | `Server status: 202 Accepted` … `The dry-run was made for package aurasuisui/multiindex version 0.2.2.` |
| 客户端 | `Error: moon publish failed`,exit = **-1** —— **已知假警报**:202 表示 dry-run 已被接受,不是失败;不据此判断能否发布,也未反复重试 |
| 打包内容 | 独立复跑 `moon package` → `_build/publish/aurasuisui-multiindex-0.2.2.zip`,**55 项**(0.2.1 为 54 项) |
| 差异 | 只多 `docs/plans/v0.2.2.md`(0.2.1 时该文件还不存在),无删除;`docs/申报书.md` 看似差异是 git C-quote 转义的假象 |
| PII / 垃圾 | 手机号 + 邮箱扫描 **0 真命中**(2 条正则命中是 `docs/STYLE.md` 的 `2^64-1` 与 `coshf` 常量);`moon.work` / `_build/` / `.exe` 命中 **0** |
| 包内版本 | 六处版本全为 `0.2.2` |

> 这张表只证明「包能打、内容干净」,**不是**发布证据 —— `publish` / `产物` / `tag` 三行仍由 M6 填写。

## 最近一次已完成:v0.3.0(2026-11-09 发布)

> **表头约定 —— 包内副本是发布前快照**:`moon publish` 打包的是**当时 HEAD 的快照**,因此**包里那份**
> 的 `publish` / `tag` 两行按定义只能是 📌(它们只能在包生成之后才发生)。**仓库 HEAD** 在 publish
> 完成后回填 `publish` + `产物` 两行为 ✅(带 registry 证据),`tag` 行在仓库 HEAD 也保持 📌:tag 打在
> **回填后的那个 commit** 上,它的 sha 记进**下一版**的「历史执行记录」—— 不回填,也不为 tag 再造一个提交
> (沿用 v0.2.2 的表头约定)。
> 行由 **M5**(版本与发布准备)填写;`publish` / `tag` 等 **M6**。

| Tier | 项 | 结果 | 证据 |
|---|---|---|---|
| 0 | `moon fmt --check` | ✅ | 2026-11-08 本机 `moon 0.1.20261104`:`moon fmt --check` → exit 0 |
| 0 | `moon check` | ✅ | `moon check` → exit 0 |
| 0 | `moon check --deny-warn --target all` | ✅ | exit 0(`moon: ran 12 tasks, now up to date`,wasm / wasm-gc / js / native 全查) |
| 0 | 接口快照(见上方注①的口径) | ✅ | `moon info` 后 mbti diff **只有 VERSION 一行**(0.2.2 → 0.3.0);提交后 `git diff --quiet -- src` = 0 |
| 0 | `moon test` | ✅ | `Total tests: 175, passed: 175, failed: 0.`,exit 0 |
| 0 | `moon build` | ✅ | exit 0 |
| 0 | 版本单一真源 | ✅ | 六处均 `0.3.0`:`moon.mod:3`、`src/lib.mbt:23`、`src/pkg.generated.mbti:10`、`cmd/leaderboard/moon.mod:2`、`bench/moon.mod:2`、`README.md:39` |
| 0 | `moon.mod` 元数据 | ✅ | `name` / `version = "0.3.0"` / `repository` / `license = "Apache-2.0"` / 5 个 `keywords` / `source = "src"` |
| 0 | CI 工具链 | ✅(不可固定) | 本机 `moon 0.1.20261104 (940aa18 2026-11-04)`;CI 装 latest、每步打印 `moon version`,漂移靠 fmt 与接口步「检测而非预防」 |
| 1 | 不变量 I1–I9 随机序列每步成立 | ✅ | `moon test -f "*qc:*"` **7/7**;`property_wbtest.mbt` 的 `check_invariants` 委托公开 `verify_invariants` |
| 1 | 模型对拍逐步一致 | ✅ | `moon test -f "*model differential*"` **2/2**(`src/model_test.mbt`) |
| 1 | 差分测试对参考实现一致 | ✅ | `moon test -f "*golden stream*"` **1/1**(`src/differential_test.mbt` 回放 `multi_index_map` 0.15.1 黄金序列) |
| 1 | 回归钉子仍在 | ✅ | `moon test -f "*regression*"` **1/1**;update 撞唯一键零变更、`modify` 双冲突(不就地改共享容器)零变更、`insert_or_replace` 双撞键 abort |
| 2 | 每条公开 API 有测试 | ✅ | `src/pkg.generated.mbti` 的 **33** 个 `pub fn Table::*` 全部出现在 README(missing=0);全量 **175** 条测试 |
| 2 | 行覆盖率 | ✅ **850/868(97.93%)** | `moon test --enable-coverage` → 175/175;`$env:MOON_COVE_REPORT_ENABLED='0'; moon coverage analyze -p aurasuisui/multiindex -- -f summary` → `src/table.mbt: 257/260`、`src/table_api.mbt: 269/284`、`Total: 850/868`;`src/index.mbt` 269/269 满覆盖 |
| 2 | `abort` 守卫有断言 | ✅ | `src/abort_guard_wbtest.mbt` **27 条 = 17 条 `test "panic …"` + 10 条伴生**;`moon test -f "*panic*"` **18/18**(含 table_test 的 1 条) |
| 2 | 边界:空表/单元素/槽位复用/代际回绕/超长桶/重名注册 | ✅ | `table_test.mbt` 的空表 / 删最后一条 / 回收槽拒绝旧 handle;`table_wbtest.mbt` 的 I9 代际耗尽退休;`bench_test.mbt` 长桶 `n/4 → n/8`;重名注册被拒且不改状态 |
| 2 | 泛型:自定义键 / Int 边界 | ✅ | 元组键 `(String, Int)`、`(Int, Int, Int)`;未注册索引时键类型无约束;`with_capacity(0/-5)`;I9 代际上限路径 |
| 2 | JSON 往返 | ✅ | `json_test.mbt` 3 条:round-trip 保插入序、重注册后答案一致、畸形输入报错不静默 |
| 3 | 压力用例(10k+ 操作) | ✅ | `bench_test.mbt`:10 000 次操作(5 000 insert + 2 500 remove + 2 500 复用 insert,全程 `verify_invariants`) |
| 3 | 基准无回退 | ✅(未改快路径) | 本版只改 `modify` 旧投影快照与脏索引容错:正常路径的桶操作不变,慢路径只在「按投影键取不到槽」时触发;沿用 `bench/README.md:154-171` 的实测数字,不新编测量值 |
| 4 | README API 表与 SPEC 一致 | ✅ | 33 个公开方法名全部出现在 README;SPEC §3.1 增 `unregister_index`、§3.7 增契约、§10 改为指向 mbti + README 的指针(`to_json` 在 SPEC 以 `ToJson` trait 登记) |
| 4 | 至少一个可运行示例 | ✅ | 生成 `moon.work`(`members = [".", "bench", "cmd/leaderboard"]`)后 `cd cmd/leaderboard && moon run .` → exit 0、34 行、首行 `== aurasuisui/multiindex VERSION: 0.3.0 (local workspace module) ==`、含 `verify_invariants: Ok`;**0.3.0 未上架前无 `moon.work` 会解析失败**(实测 `version 0.3.0 was not found in the registry`),M6 发布后回落到注册表版本;CI 的 example-smoke 覆盖 workspace 路径 |
| 4 | `docs/README.md` 地图无孤儿 | ✅ | 21 个 md 文件全部在地图中有对应行(`unlisted=0`);全仓相对链接 107 条、真实坏链 0 |
| 4 | `CHANGELOG.md` 有本版 entry | ✅ | `## [0.3.0] - 2026-11-08`(Fixed 在前:modify 静默损坏、脏索引 panic;Added:`unregister_index`) |
| 4 | 许可证与第三方来源齐备 | ✅ | `LICENSE`(Apache-2.0 正文)、`NOTICE`、`third_party/LICENSES/multi_index_map-MIT.txt`、README「致谢与来源」 |
| 发布 | 产物不含 PII / 开发态垃圾 | ✅ | 2026-11-09 `moon package` → `_build/publish/aurasuisui-multiindex-0.3.0.zip` **56 项**;PII 真 0;`moon.work` / `_build/` / `.coverage` / `.exe` 命中 0 |
| 发布 | `moon publish` 并确认 `build_status: success` | ✅ | 2026-11-09 单次 `moon publish` → `Server status: 200 OK`,exit 0(未重试);registry 复核:`latest_version = 0.3.0`、`build_status: success`、`yanked: false`、versions 含 0.3.0 |
| 发布 | 打 tag `v0.3.0` 并推送 | 📌 | 按表头约定;tag sha 记入下一版历史执行记录 |

### M5 的 dry-run 与解包核对(2026-11-08)

| 项 | 实测 |
|---|---|
| 命令 | `moon publish --dry-run`(本机 `moon 0.1.20261104`) |
| 干净树 | `git status --porcelain` 只允许 autocrlf 假阳(内容 `git diff --quiet` = 0);根目录无未跟踪 `*.coverage` |
| 服务端 | `Server status: 202 Accepted`;客户端 exit **0**,未重试 |
| 打包内容 | `moon package` → `_build/publish/aurasuisui-multiindex-0.3.0.zip`,**56 项** |
| 差异 | 相对 `v0.2.2` 的 55 项只多 `docs/plans/v0.3.0.md`(另一条 `docs/申报书.md` 是 git C-quote 转义假象),无删除 |
| PII / 垃圾 | 手机号 + 邮箱扫描 **0 真命中**;`moon.work` / `_build/` / `.exe` / `.coverage` 命中 **0** |
| 包内版本 | 六处版本全为 `0.3.0` |

> 这张表只证明「包能打、内容干净」,**不是**发布证据 —— `产物` / `publish` / `tag` 三行仍由 M6 填写。

## v0.4.0(2026-11-27 发布)

> **表头约定 —— 包内副本是发布前快照**:`moon publish` 打包的是**当时 HEAD 的快照**,因此**包里那份**
> 的 `产物` / `publish` / `tag` 三行按定义只能是 📌 或 ⏳(它们只能在包生成之后才发生)。**仓库 HEAD**
> 在 publish 完成后回填 `产物` + `publish` 为 ✅(带 registry 证据),`tag` 行在仓库 HEAD 也保持 📌:tag
> 打在**回填后的那个 commit** 上,它的 sha 记进**下一版**的「历史执行记录」—— 不回填,也不为 tag 再造一个
> 提交(沿用 v0.2.2 / v0.3.0 的表头约定)。
>
> **本段由 M5 起头、M6/M7/M8 续填。** 判定栏 `⏳` = 证据要到 **M6**(干净 clone / dry-run / 产物)、
> **M7**(publish / registry / tag / CI run id)或 **M8**(十门槛彩排)才存在,**证据格一律留空,发布前不预填**。
>
> **本段计数是本版真值**:**公开方法 38 / 测试 209 / md 22**。上方 v0.3.0 段里的 33 / 175 / 21 是**那一版的
> 历史快照**,按本仓库既有纪律(B8:历史快照只标注不改写)保持原样,不要拿它当本版数字。

| Tier | 项 | 判定 | 证据 |
|---|---|---|---|
| 0 | `moon fmt --check` | ✅ | 2026-11-25 本机 `moon 0.1.20261120 (aaf8010 2026-11-20)`:`moon fmt --check` → exit 0 |
| 0 | `moon check` | ✅ | exit 0 |
| 0 | `moon check --deny-warn --target all` | ✅ | exit 0(wasm / wasm-gc / js / native 全查) |
| 0 | 接口快照(见上方注①的口径) | ✅ | `moon info` 后 `git diff --stat -- src/pkg.generated.mbti` **只有 `VERSION` 一行**(0.3.0 → 0.4.0);提交后 `git status --porcelain=v1` 空 |
| 0 | `moon test` | ✅ | `Total tests: 209, passed: 209, failed: 0.`,exit 0 |
| 0 | `moon test --target all` | ✅ | 四行均为 `Total tests: 209, passed: 209, failed: 0.`(wasm / wasm-gc / js / native) |
| 0 | `moon build` | ✅ | exit 0 |
| 0 | 版本单一真源 | ✅ | 七处均 `0.4.0`:`moon.mod:3`、`src/lib.mbt:23`、`src/pkg.generated.mbti:10`(`moon info` 生成)、`cmd/leaderboard/moon.mod:2`、`bench/moon.mod:2`、`README.md:39`、`bench/README.md:18-19`;CI 的 version single-source 步(`ci.yml`)比对 `moon.mod` 与 `src/lib.mbt` |
| 0 | `moon.mod` 元数据 | ✅ | `name = "aurasuisui/multiindex"` / `version = "0.4.0"` / `readme` / `repository` / `license = "Apache-2.0"` / 5 个 `keywords` / `description` / `source = "src"`(`moon.mod:1-21`) |
| 0 | CI 工具链(不可固定) | ✅ | 2026-11-25 干净 clone(HEAD `7c4fab2`,复跑后删除)中 `moon version` → `moon 0.1.20261120 (aaf8010 2026-11-20)`;上游只服务 `latest`,CI 每步打印 `moon version`(`.github/workflows/ci.yml:17-36`),漂移由 `moon fmt --check` 检测而非预防 |
| 1 | 不变量 I1–I9 随机序列每步成立 | ✅ | `moon test -f "*qc:*"` **7/7**;`property_wbtest.mbt` 的 `check_invariants` 委托公开 `verify_invariants` |
| 1 | 模型对拍逐步一致 | ✅ | `moon test -f "*model differential*"` **2/2**(`src/model_test.mbt`) |
| 1 | 差分测试对参考实现一致 | ✅ | `moon test -f "*golden stream*"` **1/1**(`src/differential_test.mbt` 回放 `multi_index_map` 0.15.1 黄金序列) |
| 1 | 回归钉子仍在 | ✅ | `moon test -f "*regression*"` **1/1**;update 撞唯一键零变更、`modify` 双冲突零变更、`insert_or_replace` 双撞键 abort |
| 1 | 冲突路径:`Err` 后表与调用前一致 | ✅ | 对值类型 / 未被 `modify` 闭包就地修改的记录成立;共享容器的 Err 边界见 `docs/SPEC.md` §3.7 |
| 2 | 每条公开 API 有测试 | ✅ | `src/pkg.generated.mbti` 的 **38** 个 `pub fn Table::*` 全部出现在 README(missing=0);全量 **209** 条测试 |
| 2 | 行覆盖率 | ✅ **976/1002(97.41%)**(本行是**历史快照,不改写**;它对应的是 206 条测试时的提交 `7c4fab2`) | `moon clean` → `moon test --enable-coverage`(209/209)→ `$env:MOON_COVE_REPORT_ENABLED='0'; moon coverage analyze -p aurasuisui/multiindex -- -f summary` → `src/index.mbt: 319/326`、`src/table.mbt: 257/260`、`src/table_api.mbt: 345/361`、`Total: 976/1002`;`-f caret` 标出 **23 行**,逐条归因见 `docs/SPEC.md` §7.3 |
| 2 | `abort` 守卫有断言 | ✅ | `src/abort_guard_wbtest.mbt` **42 条 = 26 条 `test "panic …"` + 16 条伴生**;`moon test -f "*panic*"` **27/27**(含 `table_test.mbt` 的 1 条);`rebuild_index` 的未注册名守卫、`first_by` / `last_by` 的哈希象限守卫各有 1 条 panic 测试 |
| 2 | 边界:空表/单元素/槽位复用/代际回绕/超长桶/重名注册 | ✅ | `table_test.mbt` 的空表 / 删最后一条 / 回收槽拒绝旧 handle;`table_wbtest.mbt` 的 I9 代际耗尽退休;`bench_test.mbt` 长桶 `n/4 → n/8`;重名注册被拒且不改状态 |
| 2 | 泛型:自定义键 / Int 边界 | ✅ | 元组键 `(String, Int)`、`(Int, Int, Int)`;未注册索引时键类型无约束;`with_capacity(0/-5)`;I9 代际上限路径 |
| 2 | JSON 往返 | ✅ | `json_test.mbt` 3 条:round-trip 保插入序、重注册后答案一致、畸形输入报错不静默 |
| 2 | 新增方法的象限边界 | ✅ | `moon test -f "*contains_by*"` **4/4**、`"*count_by*"` **2/2**、`"*first_by*"` **5/5**、`"*last_by*"` **5/5**、`"*rebuild*"` **17/17** |
| 3 | 压力用例(10k+ 操作) | ✅ | `bench_test.mbt`:10 000 次操作(5 000 insert + 2 500 remove + 2 500 复用 insert,全程 `verify_invariants`) |
| 3 | 基准无回退 | ✅ | 2026-11-27 **发布后首次复测**。配方:`moon.work` → `moon run --release bench/main.mbt` → exit 0,输出**第 8 行**打印 `# aurasuisui/multiindex VERSION: 0.4.0 (local workspace module)`(首行是 `# [manual] swap_remove vs remove: …` 的分节标题,不是 VERSION);口径 `µs/op = median / n`(n = 20 000,自适应批次已由 batch_size 平均)。实测 vs `bench/README.md` 的 2026-10-19 基线(**不同机器,故看量级不看小数**):`insert-fresh.k1` 0.88 / 0.98、`remove.k1` 45.9 / 54.5、`swap_remove.k1` 1.68 / 1.49、`insert-fresh.k8` 11.3 / 11.6、`slot-reuse-storm.k8` 125 / 144 —— **逐项同量级,无项回退一个数量级**。`swap_remove` 相对 `remove` 的倍数在 k=1/2/4/8 为 27× / 21× / 5.7× / 3.4×,与 SPEC §13 R3 记录的「比值随 n 增长、随 k 收窄」一致 |
| 4 | README API 表与 SPEC 一致 | ✅ | **38** 个公开方法名全部出现在 README(missing=0);SPEC §3.1 已登记 `rebuild_index` 的签名与失败语义、§6 复杂度表含 4 个查询族方法与 `rebuild_index` |
| 4 | 至少一个可运行示例 | ✅ | 2026-11-25 干净 clone(HEAD `7c4fab2`):根写 `moon.work`(`members = [".", "bench", "cmd/leaderboard"]`,无 `[workspace]` 头)→ `cd cmd/leaderboard; moon run .` → exit 0、**34 行**;首行 `== aurasuisui/multiindex VERSION: 0.4.0 (local workspace module) ==`,含 `== adding players ==` 与 `verify_invariants: Ok`;跑后删 `moon.work`,`git status --porcelain=v1` 仍空 |
| 4 | `docs/README.md` 地图无孤儿 | ✅ | `git ls-files '*.md'` = **22**;`docs/README.md` 逐条核对:22 个 md 中 21 个在册,第 22 个是地图自身(`README.md(本文件)`),**孤儿 0**;相对链接 **112** 条、**坏链 0** |
| 4 | `CHANGELOG.md` 有本版 entry | ✅ | `## [0.4.0] - 2026-11-26`(Added:`rebuild_index` + 查询族四方法;Changed:降序惰性、工具链对齐、七处版本、文档对账;Notes 写明 bench 未复测) |
| 4 | 许可证与第三方来源齐备 | ✅ | `LICENSE`(Apache-2.0 正文)、`NOTICE`、`third_party/LICENSES/multi_index_map-MIT.txt`、README「致谢与来源」 |
| 发布 | 产物不含 PII / 开发态垃圾 | ✅ | 2026-11-25 干净 clone `moon package`(`Running moon check ... Check passed`)→ `_build/publish/aurasuisui-multiindex-0.4.0.zip` **59 项**(v0.3.0 为 56 项;+3/−0,差异见下);`_build` / `moon.work` / `*.coverage` / `.exe` / `.mooncakes` 条目名命中 **0**;邮箱形态 **0**,手机号/身份证号形态 **0 真命中**(11 条正则命中均为数值常量/checksum 误报,file:line 见下) |
| 发布 | `moon publish` 并确认 `build_status: success` | ✅ | 2026-11-27 单次 `moon publish`(未重试)→ `Server status: 200 OK`、exit 0;发布前 `--dry-run` → `202 Accepted`。registry 复核:`latest_version = 0.4.0`、`build_status: success`、`yanked: false`、`created_at 2026-11-27T02:12:53Z`、versions 含 0.4.0 |
| 发布 | 打 tag `v0.4.0` 并推送 | 📌 | 按表头约定:tag 打在**回填后的这个 commit** 上,其 sha 记入下一版「历史执行记录」;包内那份是回填前快照,这一行在包内只能是 📌 |

> **D3 补注(2026-11-28)**:上表「行覆盖率」那格记的 **976/1002** **不是** 0.4.0 tag 的值 —— 它是提交 `7c4fab2`(206 条测试)那次测量的结果,当时被误记为 0.4.0 真值。在 tag `0900a32`(209 条测试)上按同一配方复跑得到 **973/999 = 97.40%**(`src/index.mbt: 319/326`、`src/table.mbt: 256/259`、`src/table_api.mbt: 343/359`)。按 B8 纪律,**该历史格保留原数不改写**,只在这里标注;当前版本真值见 `CHANGELOG.md`、`docs/SPEC.md` §7.3、`CONTRIBUTING.md`。

### M5 的 dry-run 与解包核对(M6 已填打包项;服务端 dry-run 归 M7)

| 项 | 实测 |
|---|---|
| 命令 | 2026-11-25 干净 clone(HEAD `7c4fab2`,本机 `moon 0.1.20261120`):`moon package` → `Running moon check ... Check passed`、`Package to ..._build/publish/aurasuisui-multiindex-0.4.0.zip`,exit 0。**未执行 `moon publish --dry-run`** —— 它属发布动作,不在 M6 授权范围 |
| 干净树 | clone 初始 `git status --porcelain=v1` **空**;`git rev-parse HEAD` = `7c4fab2a63aa1b9ce589ea9b214af5c61eb25b35`;`git config --get core.autocrlf` = `false`(clone 时指定);全部门禁 + 示例跑完后 status 仍空,`moon.work` 已删 |
| 服务端 | `moon publish --dry-run` → `Server status: 202 Accepted`,客户端 exit 0(未重试);正式发布 → `200 OK` |
| 打包内容 | `moon package` → `_build/publish/aurasuisui-multiindex-0.4.0.zip` **59 项**(zip 条目数 = 解压后文件数 59,无目录条目) |
| 差异 | 相对 v0.3.0 的 **56** 项:**+3 / −0** —— 新增 `docs/plans/v0.4.0.md`、`src/query_family_test.mbt`、`src/rebuild_index_test.mbt`,无删除。注:计划 M6 出口写「之差只在本版新增的文档」,实测另含本版新增的 2 个测试文件(均为本版本源文件,非垃圾) |
| PII / 垃圾 | 包内 59 个文件逐行扫描:邮箱形态 **0**;手机号/身份证号形态 11 条正则命中,**真 PII 0** —— 全部误报:`docs/STYLE.md:101/102/108/596/597`(整型上下界与 `coshf` 浮点常量)、`tools/diffgen/Cargo.lock:36`(crate checksum 十六进制)。开发态垃圾条目名(`_build` / `moon.work` / `*.coverage` / `.exe` / `.mooncakes`)命中 **0**,`git` 元数据 0 |
| 包内版本 | 七处均 **0.4.0**(包内逐文件核对):`moon.mod:3`、`src/lib.mbt:23`、`src/pkg.generated.mbti:10`、`cmd/leaderboard/moon.mod:2`、`bench/moon.mod:2`、`README.md:39`、`bench/README.md:18-19`;各文件 `0.3.0` 残留 **0** |

> 这张表只证明「包能打、内容干净」,**不是**发布证据 —— `产物` 行由 M6 的打包核对填;`publish` / `tag` 两行仍待 M7(见本段表头约定)。

### M6 干净 clone 八项门禁复跑(2026-11-25)

> 在**临时目录的干净 clone** 上重跑 `.github/workflows/ci.yml` 的八项(`check-and-test` 七步 + `example-smoke`)。
> clone:`git clone --config core.autocrlf=false --branch dev <主工作树> <临时目录>`;clone 初始 `git rev-parse HEAD` = `7c4fab2a63aa1b9ce589ea9b214af5c61eb25b35`、`git status --porcelain=v1` 空、`core.autocrlf=false`、`moon 0.1.20261120 (aaf8010 2026-11-20)`。
> clone 中**未跑** `moon fmt`(只跑 `--check`),未 push、未改任何文件;复跑后删除临时目录。

| # | 门禁(按 `ci.yml` 顺序) | 命令 | exit | 关键输出 |
|---|---|---|---|---|
| 1 | 格式 | `moon fmt --check` | 0 | `Finished. moon: ran 20 tasks, now up to date` |
| 2 | 类型检查 | `moon check` | 0 | `Finished. moon: ran 4 tasks, now up to date` |
| 3 | 零警告(全后端) | `moon check --deny-warn --target all` | 0 | `Finished. moon: ran 12 tasks, now up to date` |
| 4 | 接口快照 + 版本单一真源 | `moon info`;`git diff --quiet -- src/pkg.generated.mbti`;`Int32→Int` 折叠后比对;`moon.mod` ↔ `src/lib.mbt` | 0 | `moon info` exit 0;mbti 裸 diff **0**、折叠后 **0**(114 行 vs 114 行);`moon.mod` 的 `0.4.0` == `src/lib.mbt` 的 `VERSION` `0.4.0` |
| 5 | 测试(默认后端) | `moon test` | 0 | `Total tests: 206, passed: 206, failed: 0.` |
| 6 | 测试(四后端) | `moon test --target all` | 0 | 四行均为 `206/206`:`[wasm]` / `[wasm-gc]` / `[js]` / `[native]` |
| 7 | 构建 | `moon build` | 0 | `Finished. moon: ran 1 task, now up to date` |
| 8 | 示例(example-smoke) | 根写 `moon.work`(无 `[workspace]` 头)→ `cd cmd/leaderboard; moon run .` | 0 | 34 行;三条 landmark 全中(见上方「至少一个可运行示例」行);跑后删 `moon.work` |

> 本段主表 Tier 0 的 `moon fmt --check` / `moon check` / `moon check --deny-warn --target all` / 接口快照 / `moon test` / `moon test --target all` / `moon build` 均在此干净 clone 上复跑并 exit 0,判定栏维持 ✅。

> 本段证据对应 clone HEAD `7c4fab2`(当时 206 条)。M6b 补入 3 条契约测试后本版为 **209** 条;最终发布提交上的完整复跑见 M8 的验收彩排记录。


### v0.4.0 验收彩排(2026-11-27,M8)

> **快照**:main = dev(树 `12f79c00`);tag v0.4.0 = `0900a32`(树 `e59ba4bf`),比 main 少 M8 段落 —— 按仓库表头约定,tag 冻结发布件,M8 是发布后证据;registry `aurasuisui/multiindex` = **0.4.0**,`build_status: success`,`yanked: false`。
> **方式**:发布后再跑一遍评审标准 §4 的十条 L0,证据取本仓命令原样输出,不采信历史记录。
> **工具链**:`moon 0.1.20261126` / `moonc v1.0.0-rc1`(与 CI 的 latest 一致)。

| # | L0 门槛 | 判定 | 证据 |
|---|---|---|---|
| 1 | MoonBit 为主体 | ✅ | 生产 **2698** / 测试 **6884** 行(非空行口径;快照 `ff12cac`/dev)。统计:`git ls-tree -r --name-only HEAD -- src \| ?{$_ -like '*.mbt' -and $_ -ne 'src/pkg.generated.mbti'}`,逐个 `git show HEAD:<path> \| ?{$_.Trim() -ne ''}` 计数,文件名含 `test` 归测试、其余归生产 → 18 个 `.mbt`(6 生产 + 12 测试),全部 MoonBit;无其他语言胶水 |
| 2 | 仓库公开、快照可追踪 | ✅ | GitHub 公开;main = dev(树 `12f79c00`)、tag v0.4.0 = `0900a32`(树 `e59ba4bf`,比 main 少 M8 段落 —— tag 冻结发布件,M8 是发布后证据);远端已同步(双向差 0) |
| 3 | 选题边界清晰 | ✅ | README 首段 + indexmap / bimap / slotmap 三类边界表;申报书「通用性、场景」段 |
| 4 | 核心 API 已交付 | ✅ | mbti 的 **38** 个 `pub fn Table::*`,申报书与 README 声称的方法**缺失 0**;本期新增 `rebuild_index` + 4 个查询族均在册 |
| 5 | README 可用 | ✅ | 干净目录 `moon new` → `moon add aurasuisui/multiindex@0.4.0` → 下载成功;快速开始块逐字编译且输出与文档一致(M6 实测) |
| 6 | CI 绿 | ✅ | main run `45927276086` success、dev run `45926853076` success;八步 check-and-test + example-smoke 两 job 全绿 |
| 7 | 示例可运行 | ✅ | `example-smoke` success;本地 `moon run .` 输出含 VERSION 行 / `== adding players ==` / `verify_invariants: Ok` |
| 8 | 测试可运行 | ✅ | `moon test --target all` → **209/209 × wasm / wasm-gc / js / native** |
| 9 | 已发布 mooncakes | ✅ | `latest_version = 0.4.0`、`build_status: success`、`yanked: false`、`created_at 2026-11-27T02:12:53Z`;七处版本一致 |
| 10 | 许可与归属 | ✅ | 根目录 Apache-2.0;NOTICE 逐条登记上游(`multi_index_map` MIT / `slotmap` Zlib / thunderdome / hecs);SPEC §0 源码级核查 |

**承诺矩阵(申报书核心功能 → 公开入口 → 黑盒测试)**

| 承诺 | 公开 API | 黑盒测试 |
|---|---|---|
| 记录存储与稳定句柄 | `Table::new` / `get` / `contains` / `RowId` | 空表 / 删最后一条 / 槽位复用拒旧 handle;I9 代际耗尽 |
| 索引注册·删除·修复 | `register_*` / `unregister_index` / `rebuild_index` | 注册回填 / 重名拒 / 未知名 abort;`rebuild_index_test.mbt` **7 条** |
| 写入与冲突归还 | `insert` / `insert_many` / `update` / `modify` / `insert_or_replace` / `remove` / `swap_remove` / `clear` | 批内冲突 / 批 vs 库冲突 / Err 归还;`model_test` 对拍线性扫描 oracle |
| 查询与遍历 | `get_by` / `iter_by` / `range_by` / `range_half_open_by` / `iter_asc_by` / `iter_desc_by` / `contains_by` / `count_by` / `first_by` / `last_by` / `iter` | `query_family_test.mbt` **7 条**;方向断言;哈希象限 abort |
| 一致性与可变记录契约 | `verify_invariants` / `index_stats` | `check_invariants` I1–I9;**写侧别名 3 条** + 读侧 1 条 + 容错 4 条 |
| JSON 与质量 | `to_json` / `from_json` | 往返 / 重注册 / 畸形输入可捕获 |

**边界矩阵覆盖(评审标准 §6)**

| 类别 | 覆盖 | 落点 |
|---|---|---|
| 生命周期对称 | ✅ | 注册 / 删除 / 空表 / 最后一条 / 最后索引 |
| **可变/别名** | ✅ | **读侧 1 + 写侧 3**(改容器后 verify 报 I4、旧键命中新键漏查) |
| 错误路径原子性 | ✅ | insert / insert_many / update / modify / rebuild_index 的 Err 均断言前后状态 |
| 脏态与恢复 | ✅ | 脏表 remove/swap_remove/update total;rebuild_index 一步;三步降级 |
| 唯一性 | ✅ | 重复键 / 批内重复 / 脏态插同键 / 唯一桶覆盖 |
| 迭代器 | ✅ | fail-fast(version);迭代中改表 abort;重建前游标走旧快照 |
| 跨表 / 外部输入 | ✅ | 跨表 RowId 契约化为未定义(README/SPEC);未知索引名 abort |
| 空 / 极端规模 | ✅ | bench_test:20k 插入 + 20k swap_remove,全程 verify=Ok |
| 序列化 | ✅ | 往返 / 畸形输入;from_json 无上限已登记为已知债 |
| 端到端核心链路 | ✅ | cmd/leaderboard 三类索引 + 唯一/非唯一/有序查询 + verify_invariants |
| 多索引 | ✅ | 四象限同字段共存;index_stats 桶分布;unregister 一个不影响其它 |

**放行结论**:10/10 门槛有本仓命令证据;承诺矩阵 6/6 行有 API + 黑盒测试;边界矩阵 11/11 类有覆盖。唯一未做自动化的是基准的**跨机器绝对数值**——已按「同量级」比对并说明,不作性能承诺。

## 历史执行记录

### v0.3.0 验收彩排(2026-11-09,M7)

> 按当前 `HEAD` 重填官方十门槛。仓库 `dev` = `d08b9cf`(本节提交前)、`main` = `7f161c7`、`v0.3.0^{commit}` = `7f161c7`;工作树 `git status --short` 空、`git diff --quiet` = 0。本机 `moon 0.1.20261104 (940aa18 2026-11-04)`;命令均在仓库根目录执行,可直接复制。**本节只改这一份文件;源码 / 版本 / tag 全未动。**

#### A. 官方十门槛

| # | 门槛 | 结果 | 命令 | 关键输出摘录 |
|---|---|---|---|---|
| 1 | MoonBit 主体 | ✅ | `git ls-files src`;按扩展名计数;`Select-String moon.mod '^import'` | `.mbt 16`、`.pkg 1`、`.mbti 1`;`moon.mod` 的 import 行 **0** |
| 2 | 仓库公开且快照一致 | ✅ | `git rev-parse 'v0.3.0^{commit}'`;同 `main` / `dev`;`git diff --quiet v0.3.0 main`(同 dev、main dev);`gh repo view --json visibility` | `7f161c7` / `7f161c7` / `d08b9cf`;三条 diff 均 `0`;`{"visibility":"PUBLIC"}` |
| 3 | 选题边界 | ✅ | `Select-String README '一张记录表'`;`Select-String docs/SPEC.md 'N 个彼此独立的索引'` | README:3「一张记录表,**N 个二级索引**」;SPEC:132「把它泛化为 **N 个彼此独立的索引**」 |
| 4 | 核心 API | ✅ | `(Select-String src/pkg.generated.mbti -Pattern '^pub fn\[.*\] Table::').Count`;33 个方法名在 README 中检索 | `33`;README 缺失 **0** |
| 5 | README 四节 + 空目录走通 | ✅ | `Select-String README '^## '`;仓库外 `moon new m7probe` → `moon add aurasuisui/multiindex@0.3.0` → 按 README 粘 `main.mbt` → `moon run .` | 安装 / 快速开始 / 运行示例 / API 在 `:31` / `:51` / `:112` / `:123`;`moon add` exit 0;示例 exit 0,8 行 |
| 6 | CI 绿 | ✅ | `gh run list --branch main --limit 2`;`gh run list --branch dev --limit 2` | main `42553885298`(7f161c7)success;dev `42553803310`(d08b9cf)success |
| 7 | 干净 clone 跑示例 | ✅ | `git clone --depth 1 --branch v0.3.0 …`;确认无 `moon.work`;`cd cmd/leaderboard; moon run .` | exit 0,**34 行**,首行 `VERSION: 0.3.0`,含 `verify_invariants: Ok` |
| 8 | 测试可运行 | ✅ | `moon test`;`moon test --target all` | `175/175` + `175/175` × wasm / wasm-gc / js / native |
| 9 | mooncakes 已发布 | ✅ | `Invoke-RestMethod https://mooncakes.io/api/v0/manifest/aurasuisui/multiindex` | `latest_version=0.3.0`、`build_status=success`、`yanked=False`、versions `0.3.0,0.2.2,0.2.1,0.2.0,0.1.0` |
| 10 | 许可与归属 | ✅ | `Get-Item LICENSE,NOTICE,third_party/LICENSES/*`;`Select-String moon.mod '^license'` | `LICENSE 10349`、`NOTICE 4782`、`multi_index_map-MIT.txt 1069`;`license = "Apache-2.0"` |

#### B. 计划 §四 的 10 条验收场景

| # | 场景 | 结果 | 证据(命令 / 输出) |
|---|---|---|---|
| 1 | 删除正常 | ✅ | `moon test -f "*unregister_index*"` → **6/6**;`unregister_index drops only the registry entry`:返回 `true`、`has_index=false`、`len` / `iter` 不变、`verify=Ok` |
| 2 | 删除幂等 | ✅ | 同上 6/6;`unregister_index is idempotent and answers false for unknown names`:再删同名 `false`,不 abort |
| 3 | 删除未知 | ✅ | 同上;`unregister_index("ghost")` → `false`,不 abort |
| 4 | 重注册 | ✅ | 同上;`unregister_index frees the name for a new projection`:回填成功、旧键不命中、新键命中、`verify=Ok` |
| 5 | 约束释放 | ✅ | 同上;`unregister_index releases a unique constraint`:删唯一索引后重复键从 `Err` 变 `Ok` |
| 6 | 可变 V 检测 | ✅ | `moon test -f "*external mutation*"` → **1/1**;`get` 后改被索引字段 → `verify` 返回 `Err`,消息含 `I4`(契约写明不承诺修复外部别名) |
| 7 | `modify` 就地改 | ✅ | `moon test -f "*modify snapshots*"` → **2/2**;旧键不命中、新键命中、`verify=Ok` |
| 8 | 脏索引删除(脏的是被删的那条) | ✅ | `moon test -f "*remove tolerates a record*"` → **2/2**;返回记录、不 panic、`verify=Ok`;含唯一索引 + 四象限 |
| 9 | 脏索引更新(脏的是被更新的那条) | ✅ | `moon test -f "*update tolerates a record*"` → **1/1**;成功、新键命中、旧桶清掉 |
| 10 | 兼容 | ✅ | `moon test` **175/175**;33 个公开方法仍齐;mbti 增 `unregister_index` 与 `VERSION`(另有工具链 `#derive` 拼写,见 M5 记录) |
| 残余 | 脏的是**另一条**记录 / 脏表 `insert` 预检 | 记录,不要求通过 | 见 `docs/SPEC.md` §3.7「拒绝路径的边界」与 README「限制」;本版不承诺顺带修复其他记录的脏条目 |

#### C. 附加证据

**跨表 `RowId`(仓库外 `m7probe`,已删)**

```text
A.id=RowId(0, 0) B.id=RowId(0, 0)
B.get(A.id) -> Some(B-record)
A.len=1 B.len=1
```

两张 `Table[Int32, String]` 首条都是 `RowId(0, 0)`;`B.get(A.id)` **命中 B 的记录**。与 `docs/SPEC.md` §2.1 的措辞一致:跨表**未定义**,`(0,0)` 可能命中另一张表的首条记录,不承诺 `None`。

**覆盖率(legacy reporter)**

`moon clean` → `$env:MOON_COVE_REPORT_ENABLED='0'` → `moon coverage analyze -p aurasuisui/multiindex -- -f summary`:

```text
src\table.mbt: 257/260
src\table_api.mbt: 269/284
Total: 850/868
```

`src/index.mbt` 269/269(满覆盖);850/868 = 97.93%。比 M5b 记录的 847 多 3 行,正是 M5c 新增三条守卫测试覆盖的 `iter_by` / `ordered_index` / `cursor_iter` 守卫行;没有新增未覆盖行。

**干净 clone 安装(仓库外)**

```text
moon new m7probe            → exit 0
moon add aurasuisui/multiindex@0.3.0 → exit 0(Using cached …@0.3.0)
按 README 粘 main.mbt;moon run . → exit 0,8 行,与 README:100-107 逐字一致
```

**文档链接**

`git ls-files '*.md'` = **21**;去掉围栏代码块与行内代码后,相对链接 **108 条、坏链 0**。

```text
md_files=21 unlisted=0
relative_links=108
broken=0
```

**结论**:官方十门槛 **10/10**;计划 §四 10 条场景 **10/10**;残余边界仅记录、不要求通过。所有探针均在仓库外,已删除。

### v0.2.2 验收彩排(2026-10-30,M7)

> 按当前 `HEAD` 重填计划 §2.2 的官方十门槛。仓库 `dev` = `6aecc33`、`main` = `2dbd7b1`、`v0.2.2^{commit}` = `2dbd7b1`;工作树仅 `src/pkg.generated.mbti` 的 `autocrlf` 假阳(`git diff --quiet -- src` = 0)。本机 `moon 0.1.20261020 (2284bd2 2026-10-20)`;命令均在仓库根目录执行,可直接复制。

| # | 门槛 | 结果 | 命令 | 关键输出摘录 |
|---|---|---|---|---|
| 1 | MoonBit 主体 | ✅ | `git ls-files src`;`Select-String -Path moon.mod -Pattern '^import'` | `.mbt 16`、`.pkg 1`、`.mbti 1`;`moon.mod` 无 `import` 行 |
| 2 | 仓库公开且快照一致 | ✅ | `git rev-parse 'v0.2.2^{commit}'`;`git rev-parse main`;`git rev-parse dev`;`git diff --quiet v0.2.2 main; $LASTEXITCODE`(同 dev、main dev);`gh repo view --json visibility` | `2dbd7b1` / `2dbd7b1` / `6aecc33`;三条 diff 均 `0`;`"visibility":"PUBLIC"` |
| 3 | 选题边界 | ✅ | `Select-String -Path README.md -Pattern '一张记录表'`;`Select-String -Path docs/SPEC.md -Pattern '一句话'` | README:3「一张记录表,**N 个二级索引**」;SPEC:132「`BiMap` 是…的特例;本库把它泛化为 **N 个彼此独立的索引**」 |
| 4 | 核心 API | ✅(注①) | `(Select-String -Path src/pkg.generated.mbti -Pattern '^pub fn\[.*\] Table::').Count` | `32`;32 个方法名全部出现在 README API 表(`missing=0`) |
| 5 | README 含目标 / 安装 / API / 示例 | ✅ | `Select-String -Path README.md -Pattern '^## '`;按 README 字面跑一遍(见下) | 命中 `:31` / `:51` / `:112` / `:123`;干净环境 `moon run .` exit 0,8 行与 README:99-107 逐字一致 |
| 6 | CI 绿 | ✅ | `gh run list --branch main --limit 3`;`gh run list --branch dev --limit 3` | main `39785836950` / `39784911637` / `39383979438` 全 success;dev `39785643537` / `39784642076` / `39768595546` 全 success |
| 7 | 示例可运行 | ✅ | 干净 clone(无 `moon.work`)后 `cd cmd/leaderboard; moon run .` | exit 0,34 行,含 `verify_invariants: Ok` |
| 8 | 测试可运行 | ✅ | `moon test`;`moon test --target all` | `148/148` + `148/148` × wasm / wasm-gc / js / native |
| 9 | mooncakes 已发布 | ✅ | `$m = Invoke-RestMethod 'https://mooncakes.io/api/v0/manifest/aurasuisui/multiindex'; $m.latest_version; $m.build_status; $m.yanked; $m.versions.version` | `0.2.2` / `success` / `False` / `0.2.2, 0.2.1, 0.2.0, 0.1.0` |
| 10 | 许可与归属 | ✅ | `Get-Item LICENSE,NOTICE,third_party/LICENSES/*`;`Select-String -Path moon.mod -Pattern '^license'` | `LICENSE 10349`、`NOTICE 4782`、`multi_index_map-MIT.txt 1069`;`license = "Apache-2.0"` |

> **注①(#4 的依据链有文档缺口)**:计划写「SPEC §4 有表」不成立 —— §4 是「核心不变量」(`docs/SPEC.md:526`),§10「完整 API 速查表」只有标题(`:715`)、没有表。核心 API 的完整性因此改由 `src/pkg.generated.mbti` 的 32 个方法与 README API 表互证(32/32 命中);**未改 SPEC** —— M7 只授权改本文件,此条列为「发现但未改」。

**干净环境彩排(仓库外空目录)**

```powershell
moon new m7probe
cd m7probe
moon add aurasuisui/multiindex@0.2.2
```

`moon add` exit 0,stderr 摘要 `Registry index updated successfully` / `Symbols updated successfully` / `Downloading aurasuisui/multiindex@0.2.2`;写入 `moon.mod` 的行是 `import { "aurasuisui/multiindex@0.2.2" }`。按 README 在根 `moon.pkg` 补 `import { "aurasuisui/multiindex" }` + `pkgtype(kind: "executable")`,把 README:58-94 原样粘进根 `main.mbt`,再 `moon run .` → exit 0,8 行与 README:99-107 逐字一致。

**干净 clone 示例**

```powershell
git clone --depth 1 --branch v0.2.2 https://github.com/aurasuisui/moonbit-multiindex.git m7-clone
cd m7-clone/cmd/leaderboard
moon run .
```

clone 后 `Test-Path moon.work` = `False`;`cmd/leaderboard/moon.mod` 钉 `aurasuisui/multiindex@0.2.2`;`moon run .` exit 0、34 行、`verify_invariants: Ok`。首行仍印 `(local workspace module)` —— 注册表副本也带这个后缀(实测),**不要拿它当本地源码的证据**,版本号才是。

**跨表 `RowId` 探针(仓库外)**

两张 `Table[Int32, String]`,A/B 首次 insert 都得 `RowId(0, 0)`;`B.get(A 的 RowId)` → `Some(B-record)`、`B.remove(A 的 RowId)` 删掉的是 B 的记录(B.len=0,A.len=1)。与 SPEC §2.1:165 的措辞一致:跨表**未定义**,`(0,0)` **可能命中**另一张表的首条记录,不承诺 `None`。

**覆盖率(legacy reporter)**

`moon test --enable-coverage` → `148/148`;默认新 reporter `moon coverage report -p aurasuisui/multiindex -f summary` 仍报 `error: conflicting trace metadata for file id 'aurasuisui/multiindex$index'`(exit 1,工具链问题,未改测试);`$env:MOON_COVE_REPORT_ENABLED='0'` 后同一命令 → `Total: 784/805`(`table.mbt 241/243`、`table_api.mbt 258/277`,与 0.2.1 持平)。

**文档链接**

`git ls-files '*.md'` = **20**(计划写 19,实际多出 `docs/plans/v0.2.2.md`);去掉围栏代码块与行内代码后,相对链接 **99 条、坏链 0**。3 条原始假阳性均为代码里的示例:`SortedMap[Int, String]([])`、`[HawkEye](…)`(TOML 围栏内与行内代码中各一次)。

**三条 grep 门禁(照实分口径,不四舍五入)**

- `20–44×` / `30–70×`:现役文档 `README.md` + `docs/SPEC.md` + `bench/README.md` 命中 **0**;全仓 **11**,全部是历史/自指(`CHANGELOG.md:29` 说明旧数字已归零、`:426` 的 0.1.0 历史段;`docs/plans/v0.1.0.md:87`、`v0.2.0.md:16`、`v0.2.2.md:96/110/113/195/196/213/215` 引用旧数字或门禁本身)。
- `^'`(README):**0**。
- `let _ = t.register`:代码(`cmd/`、`bench/`、`src/`)**0**;全仓 **2**,均在 `docs/plans/v0.2.2.md`(D8 定义 `:97` 与 M3 记录 `:214` 的引文)。

**结论**:官方十门槛 **10/10**(#4 带注①);以上补充质量门单列,不计入 10/10。

> **快照口径**:本节取证于 `dev = 6aecc33`(本文件这一提交之前的 HEAD)。**发布快照以 `v0.2.2` ↔ `main` 为准(长期为 0)**;`dev` 在发布后继续前进属正常,`git diff --quiet v0.2.2 dev` 之后的差异只会是发布后新增的文档提交(先是本文件,再是台账)。

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
- [ ] 冲突路径:**返回 `Err` 后表与调用前完全一致** —— 对值类型 / 未被 `modify` 闭包就地修改的记录成立;共享容器的 Err 边界见 `docs/SPEC.md` §3.7

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
