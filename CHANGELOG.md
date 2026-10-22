# Changelog

All notable changes to `aurasuisui/multiindex` are documented here.
格式参考 [Keep a Changelog](https://keepachangelog.com/);版本号遵循 [SemVer](https://semver.org/)。

---

## [0.2.2] - 未发布

**第四个发布版本,PATCH(进行中)** —— 无公开 API 变更(`src/pkg.generated.mbti` 只差 `VERSION` 一行)。
本段随里程碑追加;版本号与发布结果由 M5 / M6 补齐。

### Changed — 工具链与发布流程

- **接口快照按当前工具链重新生成**(`9b1fbf1`):`moon 0.1.20261020` 把 `src/pkg.generated.mbti` 的
  `Int` 印成 `Int32`(同一种类型,**纯拼写**,8 行)。提交生成物,使 `moon info` 之后工作树为空。
- **发布流程决定**:`dev` 逐节点提交 → `moon publish` → 在仓库 HEAD 回填 `publish` / `产物` 两行 →
  CI 绿 → `git read-tree --reset -u dev` **一次性**同步 `main`(只一个 commit)→ tag 打在回填后的
  提交上 → push `main` / `dev` / tag。不重写历史;`main` 与 tag 只出现在 publish 之后,避免
  「干净 clone 解析到未发布版本」的窗口。包内副本的 `publish` / `tag` 两行按定义只能是 📌
  (口径见 `docs/RELEASE_CHECKLIST.md` 的 v0.2.2 表头)。

### Notes / Deviations

- **0.2.1 遗留**:已发布的 0.2.1 包内 `cmd/leaderboard/moon.mod` 与 `bench/moon.mod` 仍 pin `@0.2.0`
  (发布提交 `c8e56fd` 的消息称已升,与实际不符);0.2.2 会在 M5 一并升到 `@0.2.2`。

## [0.2.1] - 2026-10-21

**第三个发布版本,PATCH** —— 无公开 API 变更(`src/pkg.generated.mbti` 除 `VERSION` 一行外与 0.2.0 完全一致)。
本版只做两件事:修文档纪律、补测试覆盖。

### Fixed — 文档纪律

- **3 条坏链**:`docs/MOONBIT_REF.md` 的 `../SPEC.md`、`docs/plans/v0.1.0.md` 的 `../NOTICE`、
  `docs/plans/v0.2.0.md` 的 `RELEASE_CHECKLIST.md`,全部指向真实路径。复核:全仓库 (19) 个 md / 89 条相对链接,坏链 0。
- **4 个幽灵文件**:文档里写着、仓库里从未存在的 `src/table_iter.mbt`、`src/table_traits.mbt`、
  `src/regression_wbtest.mbt`、`src/generics_test.mbt`。`CONTRIBUTING.md` 的目录树与测试表按真实文件重写;
  `AGENTS.md` 源码地图删掉 *planned* 条目,并写明迭代器**内联**在 `table.mbt` / `table_api.mbt`(该拆分已决定放弃)。
- **数字漂移**:`docs/README.md` 的可信度标记「三级」→ 四级(`[实测]` 41 / `[源码]` 23 / `[文档]` 14 / `[未核实]` 1,经脚本复算);
  `docs/RELEASE_CHECKLIST.md` 的测试计数按当前 HEAD 重算。

### Added — 测试

- **覆盖率工具链**接入:`moon test --enable-coverage` + `moon coverage analyze -p aurasuisui/multiindex -- -f summary`,`CONTRIBUTING.md` 写明用法。
- 覆盖率 **688/805 → 784/805**。`src/index.mbt` 与 `src/lib.mbt` **满覆盖**(230/230、43/43)。
- 测试 **102 → 148**:
  - `table_test.mbt` 51→57、`table_wbtest.mbt` 30→44:4 个 `register_*` 的错误路径(`DuplicateName` × 3、回填 `UniqueViolation`)、
    `Conflict` / `Rejected` 的 `Show` 完整串、12 条 `verify_*` **证伪**测试(故意弄脏 `order` / `free` / 桶,证明每项检查真会报错)、2 条防御分支。
  - 新增 `src/abort_guard_wbtest.mbt`(26 条):每条可达 `abort` 守卫一条 `test "panic …"`,另配**普通命名的伴生测试**
    原样重跑同一 fixture —— 防止「因别的原因 panic 也算通过」。

### Notes / Deviations

- **推翻一条旧结论**:曾认定「MoonBit 的 `abort` 无法断言」。正解是**测试名以 `panic ` 开头**——只有真的 panic 才算通过;
  `try`/`catch` 抓不到 `abort`(报 `[0023] unused_try`),`#panic` 属性不存在(`[4132]`/`[3002]`)。
  这条事实原本就写在 `docs/MOONBIT_REF.md` §7.1 里;此前的实现会话与我都没先查自己的速查表。
  教训已写进 `CONTRIBUTING.md`:推翻既有结论前,先 grep 本项目文档。
- `panic` 是**弱断言**:它看不到 panic 消息,所以每条守卫的**判据**仍由只读分类器单测钉死。
- 仍有 **21 行**未覆盖,均为结构不可达或防御性 `continue`:`src/table.mbt` 的 insert 后回读 abort 与 `insert_or_replace` 的 Err 分支;
  `src/table_api.mbt` 的查询族越界 `continue`、I5/I3 的 verify 分支、I7 分支。逐条理由见 `docs/SPEC.md` §7.1。
- `inspect(content=…)` 在当前工具链解析到已废弃的 `Show`,在 `--deny-warn` 下是 **Error** `[0020]`;
  断言字符串一律用 `@test.assert_eq(Show::to_string(v), …)`。
- 已知不可逆瑕疵(0.2.0 遗留):已发布的 0.2.0 包内 `bench/` 与 `cmd/leaderboard/` 的 `moon.mod` 仍写 `@0.1.0`。
  源码已修正,但旧版本包内容不可修改。

## [0.2.0] - 2026-10-20

**第二个发布版本** —— `0.1.0` 已于 2026-10-14 发布到 mooncakes.io(`build_status: success`)。下面按里程碑记录 M1–M12 的全部内容。

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

#### M2 — 索引核心(2026-10-14)

- **四象限索引注册表**(`src/index.mbt`):`Index[K, V]` = HashUnique / SortedUnique /
  HashMulti / SortedMulti;桶内只存**槽位号**,非唯一桶为 `SortedSet[Int]`。
- **四个 `register_*`**(`src/table_api.mbt`),均返回 `Result[Unit, RegisterError]`:
  重名 → `Err(DuplicateName)`;**对非空表回填扫描**(O(len),注册后立即可查);回填唯一索引
  遇冲突 → `Err(UniqueViolation(name, key))` 且**完全不注册**(原子,无半成品)。
- **查询**:`get_by(name, key) -> (RowId, V)?`(非唯一索引返回桶内**槽位号最小**者)、
  `iter_by(name, key) -> Iter2[RowId, V]`(槽位号升序;唯一索引产出 0/1 条)、
  `index_names() -> Array[String]`。未知索引名一律返回空,**绝不 panic**。
- **索引接进三个汇聚点**:`insert_impl`(加桶)、`remove_impl`(删桶,空桶即删)、
  `clear_impl`(清空全部桶、保留注册)。
- **`insert` 的唯一性前置检查**:`find_conflict` 在任何变更之前探测全部唯一索引;冲突时
  **表零变更**,记录随 `Err(Rejected{ conflict, record })` 原样归还。
- 新公开类型 `RegisterError`(SPEC §2.4);`Rejected` 的 Debug/Show M1 已具备。
- 测试 35 条(**M1 的 19 条一条未削弱**):`check_invariants` 扩展到 **I3/I4/I5/I7**
  (逐索引、逐桶断言投影一致 / 桶内无重复 / 唯一桶 ≤ 1 / 计数与覆盖两半)并在随机序列
  **每一步之后**校验;新增 2 条索引版「校验器非空转」元测试;黑盒新增注册与查询矩阵 9 条;
  黑盒与白盒各加一个带索引的随机序列(30 轮 × 120 步 / 25 轮 × 80 步,每步校验)。
- M1 遗留的 **6 条声明式死代码警告**(未构造的 `Index` 变体 / `IndexMeta`)随 M2 落地**全部消失**;
  当前 `moon check` 为 13 warnings / 0 errors(其余为 `derive` 的 `[0079]` 与 `moon.pkg` 的
  `unused_package`,与 M1 同源)。
#### M3 — 更新与冲突 + 偏差收敛(2026-10-14)

- **`update` / `modify`**(`src/table.mbt`):顺序固定为「算新投影 → 对每个唯一索引预检
  (**排除自身**)→ 全部通过后统一落地」;`f` 恰好调用一次。
- **新公开类型 `UpdateRejected[K, V]`**(SPEC §2.5):`StaleHandle(RowId, V?)` /
  `Conflict(Conflict[K], V)` —— 陈旧句柄与唯一冲突分开表达,失败**绝不吞掉调用方的数据**
  (`update` 归还待写入记录,`modify` 无从算起故为 `None`)。
- **逐索引键对比快路径**(`Index::retarget`):键未变的索引**不删不加**,无可观察中间态
  (SPEC §5 规则 3)。
- **新汇聚点 `modify_impl`**:先重定位索引桶、再覆盖行、最后 `version += 1`。
- **关闭 SPEC §12 台账 4 条**:`RegisterError[K]`(键原样携带,两个唯一注册方法不再要求
  `K : Show`)、`has_index(name)`、`Table::with_capacity(cap)`、`contains(id)`。
- 测试 51 条(**M1/M2 的 36 条一条未削弱**):回归钉子(update 撞已占用唯一键 → 逐条零变更)、
  excluding-self 合法改写、**双唯一索引冲突的 modify 原子性**、陈旧句柄、**快路径三重取证**、
  两个随机序列驱动接入 update/modify 并**每一步**校验不变量。
- `moon check` 现为 **15 warnings / 0 errors**(测试构建 16):比 M2 多 2 条,均为
  `UpdateRejected` 的 `derive(Debug, Eq)` 触发的 `[0079]`。

#### M4 — 有序索引与范围查询 + 失败分类收敛(2026-10-14)

- **有序遍历原语**(`src/index.mbt`):`Index::is_ordered`(可测谓词)、`BucketCursor`(一次只物化
  一个桶的游标,满足 §3.3「范围查询保持惰性」)、`Index::range_cursor(lo, hi, include_hi)`、
  `Index::ordered_cursor(descending)` / `reversed_cursor`。
- **四个有序查询**(`src/table_api.mbt`):`range_by`(双闭 `[lo, hi]`,转发 core 的
  `SortedMap::range`)、`range_half_open_by`(`[lo, hi)`,过滤键 `== hi`)、`iter_asc_by`、
  `iter_desc_by`。公开约束按 SPEC §3.3 为 `K : Compare`;非唯一有序索引会展开桶,**桶内按槽位号升序**。
- **失败分类收敛(关闭 SPEC §12 第 5 条)**:未知索引名由「返回空」改为 `abort`;在哈希索引上
  做有序查询同样 `abort`(SPEC §7.1)。判定抽成可测谓词(`Table::has_index` / `Index::is_ordered`),
  `abort` 各一行。
- 测试 59 条(**M1/M2/M3 的 51 条一条未削弱**;两处旧断言因契约变更改为经 `has_index` 断言缺失):
  四个查询在**唯一有序 / 非唯一有序**两种索引上、边界全覆盖(`lo > hi`、半开 `lo == hi`、空表、
  无匹配、单点、全量)、`iter_desc_by` **方向证明**,以及 remove / update / clear 之后的跟随。

#### M5 — 自检与诊断(2026-10-14)

- **`insert_many(vs) -> Result[Array[RowId], Rejected[K, V]]`**(SPEC §11):整批原子 —— 先对全部
  记录做唯一性预检(**既查活表、也查批内更早的成员**),全部通过后才逐条落库;任一条冲突 → `Err`
  且**整批零变更**,冲突记录原样归还。**不采用参考实现的 first-wins**(那是静默胜出规则),
  该偏离登记在 `tools/diffgen/README.md` 的不可差分清单。
- **公开 `verify_invariants() -> Result[Unit, String]`**(SPEC §3.4):**首个违反者即返回**,
  消息含不变量编号(I1–I9)与槽位/键;实现分 `verify_storage`(I1/I2/I6/I9)与
  `verify_indexes`(I3/I4/I5/I7)两半,约束只需 `K : Eq + Debug`。
- **`index_stats(name) -> IndexStats`**:桶数 / 条目数 / 最长桶 / 平均桶长(空索引全 0);
  新公开类型 `IndexStats`。
- **测试侧收敛为单一实现**:`property_wbtest.mbt` 的 `check_invariants` 改为**委托**公开校验器,
  5 条「非空转」元测试保留(委托前把老校验器里唯一没进公开实现的一条断言补进了 `verify_indexes`,
  确保委托**没有丢断言**)。
- 测试 71 条(**M1–M4 的 59 条一条未削弱**):insert_many 的**句柄对拍**与两类整批零变更、
  退化批次;`verify_invariants` 的健康表 Ok 与**消息定位**(I4 / I6 / I7);`index_stats` 的桶形统计;
  `planned_handles` 预测与真实分配一致。

#### M6 — 工程面(2026-10-14)

- **警告清零**:新建 `src/extends.mbt`(官方三段式:促进 `Eq::equal`,其余 `#deprecated + #doc(hidden)`),
  测试夹具 `CountedKey` 加 `priv`,`src/moon.pkg` 改三段式(基础 + `for "test"` + `for "wbtest"`)。
  结果:`moon check --deny-warn --target all` **0 warnings 0 errors**(此前 18 条)
> ⚠️ 该结论带**工具链前提**:它成立于 `moon 0.1.20260920`。`moon 0.1.20261012` 起
> `@random.Rand::new()` 报 `[0020]`,本地实测 7 处调用点(见 [`plans/v0.2.0.md`](docs/plans/v0.2.0.md) §七 B2)。
- **CI 加固**:五步 CI 新增 `moon check --deny-warn --target all`;明确不加 `moon bundle --all`
  (moon 0.1.20260920 上 panic)与 `+unnecessary_annotation`(30 条 `[0073]`,其中 12 条来自黑盒前缀约定)
- **`Conflict::DuplicateInBatch(String, K, Int)`**(落地 M5 审核裁定):批内冲突不再用预测句柄冒充
  §2.2 的「活记录」,改为指向更早成员在批次中的下标;`planned_handles` 及其测试作为死代码删除
- **对拍测试 `src/model_test.mbt`**:与朴素 `Array[(RowId, V)]` 线性扫描模型跑同一操作流,
  **每步**比对 `len` / `iter` / `get` / `contains` / 四个索引的 `get_by`、`iter_by`、有序游走与
  6 组区间(含空区间与倒置区间),并要求 `verify_invariants` 为 Ok
- **可运行示例 `cmd/leaderboard`**:id(唯一)/ team(非唯一)/ score(有序)三视图 —— 点查、团队遍历、
  排行榜降序、分数区间、冲突拒绝并归还记录、modify 同步各视图、陈旧句柄、`index_stats`、
  `verify_invariants`;实测 `moon run cmd/leaderboard` 输出见交付报告
- **基准 `bench/`**(官方 `@bench`,native+release,n=20000):点查(索引 vs 扫描)、非唯一遍历、
  区间查询、`insert`/`remove` 随 k=1/2/4/8、槽位复用风暴;`bench/README.md` 补**实测表与成因**
- **差分夹具(黄金序列)**:`tools/diffgen`(Rust,钉 `multi_index_map = "=0.15.1"`,`Cargo.lock` 入库)
  生成 `src/differential_fixture_test.mbt`,`src/differential_test.mbt` 回放并逐步比对;
  第二条 LCG 随机流**有意不实现**(理由与逐项覆盖面表写进 `tools/diffgen/README.md`)
- 测试 72 条(**M1–M5 的 69 条一条未削弱**;另 2 条随 `planned_handles` 死代码一并删除)

#### M7 — 发布准备与补漏(2026-10-14)

- **冲突报告顺序钉死**(SPEC §7):同一记录同时违反多条唯一索引时,报**索引名升序的第一个**,
  与注册顺序无关;实现只在**失败路径**收集全部违反者,成功路径零成本
- **JSON 往返**(SPEC §8,补计划漏项):`to_json` / `from_json`,线格式 `{"records": [...]}` 按插入序;
  **索引不参与序列化**,载入后重新 `register_*` 即由回填扫描重建;畸形输入报 `JsonDecodeError`
- **压力用例 `bench_test.mbt`**(补 RELEASE_CHECKLIST Tier 3):>10k 操作、单桶 1250 条的长桶、
  槽位复用风暴,每阶段复查不变量
- **基准补选择性数据点**:`bench/README.md` 现在给出**交叉点**(选择性遍历 ~58× 快、胖桶 ~5× 慢;
  窄区间 ~12× 快、宽区间 ~21× 慢),而不是只报一个不利数字
- **README 定稿**:API 三表(与 SPEC §3 逐项对齐)、实测得来的 Gotchas 8 条,并修正原文把 `range_by`
  写成半开的**错误表述**;偏离清单补 `insert_many` 整批原子、`index_stats`、JSON 往返
- **申报书 / 发布清单定稿**:`docs/申报书.md` 按实际交付更新;`docs/RELEASE_CHECKLIST.md` 增
  「最近一次执行」证据表(Tier 0/1/2/4 全绿,发布三条留空)
- 测试 78 条;`moon check --deny-warn --target all` 当时保持 0 warnings 0 errors
  (**该结论依赖 `moon 0.1.20260920`;换工具链后失效,见上**)

#### 计划 — v0.2.0 纳入评审阻断项(2026-10-19)

- `docs/plans/v0.2.0.md` 新增 **M7.5 发布基线修复**:CI 自 2026-10-14 起连续 6 次红在
  `moon fmt --check`;零警告门禁实测 7 条 `[0020]`;`v0.1.0` 无 tag;申报书含姓名与手机号;
  `bench/` 与 `cmd/leaderboard/` 依赖写死 `@0.1.0`,测的是已发布包。关闭顺序与证据见其 §七。
- 同一计划**纠正两处 semver 判定**:`IndexStats` 字段公开,加分位数属破坏性 → 改走新增独立
  方法/类型;约束擦除在现行架构下会牺牲 I3/I4/I5/I7 的逐步校验 → 本版不做,转 v0.3 候选。
- 申报书 PII 处置按 2026-10-19 决定**暂缓**(另行处理),计划把 B4 转 M12 发布前确认;
  `docs/plans/execution-brief.md` 的任务范围段标注为**停在 M1**,当前范围以 v0.2.0 计划为准。

#### M8 — 删除的二分:`swap_remove`(S8c,2026-10-19)

- 新增 `Table::swap_remove(id : RowId) -> V?`(**向后兼容的新增 API → SemVer MINOR,随 v0.2.0 发布**)。
  恢复动作与 `remove` 完全一致(清行、代际 +1、归还 `free` 或退役、每个索引删桶、`len` / `version`),
  唯一差别是 `order`:把末位槽换到被删位置再 `pop`,删除从 **O(len + I + Σ log 桶)** 降到
  **O(I + Σ log 桶)**。代价是**删除后迭代序不再等于插入序**;被移动的是槽位,所有存活 `RowId` 继续有效。
- 保序 `remove` 的签名、语义与复杂度不变;两条路径共用 `remove_impl` 的恢复段,只切换 `order` 维护方式。
- S8b 的常驻 `positions`(slot → `order` 下标)在换位时同步更新两个槽;`verify_invariants` 的 I1 双向校验覆盖此路径。
- 既有 83 条断言**一条未改**;新增 10 条(黑盒 5 + 白盒 5,含 300 步 insert / remove / swap_remove 混合序列每步校验),共 **93** 条。
- n = 1 000 / 10 000 / 100 000 三档与 `positions` 的写入代价见 `bench/README.md`(S8c 小节)。

#### M10 — 正确性加固(2026-10-19)

- **`+missing_doc` 门禁**(`265dc2f`):`src/moon.pkg` 顶层加 `warnings = "+74"`。
  实测该告警默认 off(`moonc check -warn-help` 的默认列表写作 `-74`)、**未知告警名会被静默接受**
  (`+alert_this_does_not_exist` 退出码仍是 0),所以「没报警告」不能证明开关生效——另做了正对照:
  scratch 包里放一个无文档的 `pub fn`,确认 `[0074]` 真报出。`options("warn-list": "+74")` 是**弃用**写法,报 `Error: [0027]`。
  开启后告警 **0 条**(公开 API 本就 100% 有 `///`),这道门是**防回归**;实测 `priv` 项缺文档不报 74。

- **`moon prove` 可行性探针 —— 结论:本机不可用(不再是「未判定」)**
  - 开关只有 `proof_enabled = true`;`proof = true` 报 `Unexpected key 'proof' found in moon.pkg.`,
    而 `options("proof": true)` 会被接受但只是把参数透传给 moonc,**不是**开关。
  - z3 不依赖 GitHub 获取:`python -m pip download z3-solver==4.12.6.0 --no-deps`,
    再用 `tar -xf` 解开 wheel(不能 `Expand-Archive`),`z3.exe` 位于 `<pkg>-*.data/data/bin/z3.exe`。
  - 现象:z3 **能被发现**(生成的 `why3.conf` 里登记为 `[partial_prover] name="Z3" version="4.12.6"`)、
    WhyML 能生成,但**每一个**目标都 `Failure (no prover available)` —— 包括 `ident'vc : eq x x = True`。
  - 已排除:z3 5.3.1 / 4.13.4 / 4.12.6;`Z3PATH` 指 exe、指无后缀路径、仅 PATH;目标难度(官方 37 目标示例同样全红);
    并验证 z3 自身用检测数据里的原始参数返回 `unsat`,说明故障在 why3↔z3 的调用/解析层。
  - 完整证据表见 `docs/SPEC.md` §15。

- **`proofs/`:替代方案(不是 `moon prove` 的成功)**
  - `swap_remove_positions.smt2`:`swap_remove(i)` 后 `positions` 仍是 `order` 在新长度上的逆(以 `order` 单射为前提,去掉前提即失败)。
  - `clear_retires_generations.smt2`:`clear()` 批量退役后,clear 之前的 `RowId` 不可能命中 clear 之后的记录。
  - 两条均被 z3 判为 `unsat`;`proofs/run.ps1` 一键复跑(脚本内消息必须纯 ASCII:Windows PowerShell 5.1 按 ANSI 读无 BOM 的 .ps1)。
  - 边界:证明的是**设计所依赖的逻辑关系**,不验证 MoonBit 源码;该目录**不进 CI**(CI 镜像无 z3)。

#### M11 — 能力扩展:`insert_or_replace` + `index_entries`(2026-10-20)

- **`Table::insert_or_replace(v) -> Result[(RowId, V?), Rejected[K, V]]`**(Issue #3,向后兼容新增):
  覆盖式 upsert。恰好一条记录在新值的某个**唯一**索引上撞键 → **原地替换并保留它的 `RowId`**
  (外部句柄继续有效,返回被顶替的旧值);无冲突 → 等价于 `insert`;两条**不同**记录分别撞键 →
  `abort`,消息写明两个索引与两条 `RowId`(按索引名升序,确定性)。**不新增 `Conflict` 变体** ——
  那会让既有 `match` 不再穷尽(MAJOR 破坏),而这条路径本就是调用方的数据问题。
- **复用 `update` 的机制**:只读判定 `replace_target`(唯一索引才参与,命中按槽位归组)→ `update` 用的
  `find_conflict_excluding(value, 该槽位)` → 共用的落地汇聚点 `modify_impl`。**没有第二套预检**;
  "自己撞自己"由"判定归组 + 提交排自身"这一对负责;失败路径表零变更。
- `modify_impl` 改为**返回被顶替的记录**(原来 `-> Unit`),`update` / `modify` 的调用处 `|> ignore`:
  返回值在这里是白拿的(调用方手里本来就有),省掉 `insert_or_replace` 为取旧值再查一次注册表。
- **`pub(all) enum IndexKind { HashUnique, SortedUnique, HashMulti, SortedMulti }`** +
  **`Table::index_entries() -> Array[(String, IndexKind)]`**(Issue #4,向后兼容新增):按索引名升序
  (与 `index_names` 同序)返回"名字 + 象限"。`IndexStats` 的四个公开字段**一个没动**(加字段即 MAJOR)。
  `IndexKind` 用 `derive(Debug)` + **手写 `Show`**(`derive(Show)` 已废弃)。
- 测试新增 9 条(黑盒 7 + 白盒 2),共 **102** 条:无冲突 / 单条替换且 `RowId` 不变(插入序、
  `iter_by` 两桶、`iter_asc_by`)/ 命中有序唯一索引 / 只撞自己 / 非唯一桶从不产生受害者 /
  **双撞键 `panic` 测试** / 判定函数逐分支白盒(含精确 abort 文本)+ 与 `update` 排除自身预检的一致性 /
  `index_entries` 的四象限与排序。
- 五步 CI 全绿;`moon check --deny-warn --target all` **0 警告**。

### Notes / Deviations
- **`Conflict` 故意没有「无冲突」变体**:无冲突用 `Option::None` 表达。加变体会与
  `Option::None` 在 match 位置混淆,并迫使调用方匹配一个不可能出现的 `Err`。
  (探针实测踩中,见 `docs/SPEC.md` §9)\
- **结构体泛型不带 trait 约束**(MoonBit 语法限制):约束写在方法上,与 bimap 保持一致。
- **不变量 I5 的由来**:最初的校验只覆盖 I3/I4,探针实测发现"更新成已占用的唯一键"可让唯一桶
  出现两个持有人而校验仍通过;由此补上 **I5(唯一桶长度 ≤ 1)**,并确立"I5 与 I7 成对校验"的纪律。

#### M1 记录存储(2026-10-14)

- **代际号上限 `GEN_MAX = 1073741824`(2^30)**(私有常量,`src/table.mbt`)。**MoonBit 的 `Int` 是
  32 位有符号**(实测默认 / js / native 三 target 一致,`@int.max_value == 2147483647`;`1 << 31 ==
  -2147483648`):`2^30` 是「`GEN_MAX + 1` 仍落在 `Int` 范围内」的最大 2 的幂,且远超任何实际
  可达的复用次数。常量写成**显式字面量**而非 `1 << 62` —— 后者会被**静默按位宽取模**成 `1 << 30`
  (无报错、无警告),一旦 `Int` 位宽变化语义会无声改变(**2026-10-14 审核驳回项,已修正**)。
  `gens[slot] == GEN_MAX` 的活记录被删除时,该槽**退役**(不入 `free`),其代际号保持不变。
  **SPEC §2.1 原本未规定上限取值** —— 审核会话已裁定接受 2^30 并写入 SPEC。
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

#### M2 索引核心(2026-10-14)

- **类型约束取并集(提请裁定)**:注册表是一个异构枚举,任何遍历它的操作都同时需要
  `Hash + Eq`(哈希象限)与 `Compare`(有序象限),因此 `insert` / `remove` / `get_by` /
  `iter_by` 写成 `K : Hash + Eq + Compare`。SPEC §2.5 要求"按方法最小化":真正最小化需要把
  有序象限的桶操作**擦除**成注册时捕获的闭包(或 trait object),代价是不变量检查无法枚举桶。
  **未做该优化,等审核裁定**;不触碰索引的方法(`new` / `len` / `is_empty` / `get` / `iter` /
  `clear` / `index_names`)保持**零约束**。
- **`index_names()` 的"升序"= MoonBit 的 `String` 序(shortlex)**:`String : Compare` 先比长度
  再比码元(`builtin/string.mbt`),所以 `["aa", "b"]` 枚举为 `["b", "aa"]`。按 SPEC §3.3.1
  「跟随平台语义」的先例处理,并在 API 文档与测试里**钉死该行为**(避免被当成字典序)。
- **`clear()` 保留索引注册**:SPEC §3.2 的"清空所有记录与索引"读作"清空记录与**索引条目**";
  注册(模式)保留 —— 否则 `clear` 之后新插入的记录会**静默地不被索引**。已提请 SPEC 明确措辞。
- **`insert` 的冲突探测只针对唯一象限**;非唯一象限没有冲突概念(`Index::holder` 对它们恒 `None`)。
- **`iter()` 改为返回 `Iter2[RowId, V]`**:SPEC §3.3 的统一查询形状是 M1 审核轮才写进 SPEC 的;
  M2 按 SPEC 对齐。M1 的 19 条断言**一条未削弱** —— 只把取值方式改成二元组,并**加强**为同时
  断言身份与值(`check_observable` 现在逐项比对 `(RowId, V)` 全对)。
- **`RegisterError` 暂无 `Show`**:SPEC §2.4 只要求 `derive(Debug, Eq)`;需要人读文案时再加。
- **桶枚举辅助函数放在测试侧**:`index_buckets` 只在白盒测试里需要,放在 `property_wbtest.mbt`
  而非库里,避免发布代码里出现"仅测试使用"的死函数(M5 的 `index_stats` 会在库里重新实现它)。
#### M3 更新与冲突(2026-10-14)

- **快路径的取证方式**:"实现了快路径"不算证据,所以用三种互补的白盒观测 ——
  ① **计数键** `CountedKey`(每次哈希自增)配**对照实验**(先证明"查一次必然哈希",否则探针
  空转),再断言同键 update 的哈希增量**严格小于**改键 update 的增量(两者都付了同样的预检成本);
  ② **破坏性探针**:白盒清空某个唯一桶后做同键 update —— 若走慢路径,`Index::remove` 会因为
  "桶不存在"直接 abort;实测通过,证明快路径确实没有碰那个桶;
  ③ `physical_equal`:update 前后注册表里的桶容器是**同一个对象**(没有被重建)。
- **容器同一性不是充分证据**(两条路径都不重建容器),所以它只作 ① ② 的补充,不作主证。
- **`update` 一定递增 `version`**:本库不要求 `V : Eq`,无法判断"写入的记录与原来相同",
  按"记录被替换 = 真实变更"处理(I8)。
- **`modify` 的 `f` 在预检之前调用**:新记录必须先算出来才能投影与预检;因此被拒绝的 modify 也
  **恰好调用 `f` 一次**(测试钉死),但表零变更。
- **`update` / `modify` 与 M2 同源的类型约束**:二者都要遍历异构注册表,故为
  `K : Hash + Eq + Compare`(并集约束已在 M2 Notes 登记,仍待裁定)。

#### M4 有序索引与范围查询(2026-10-14)

- **降序遍历必须物化**:core 的 `SortedMap` 没有反向迭代器,`iter_desc_by` 只能先把桶收集成数组
  再倒着走(内存 O(#桶));**范围查询两个方向都保持惰性**(一次一个桶)。这是实现限制而非设计
  偏好 —— 将来 core 提供反向迭代器即可去掉物化。
- **桶内顺序不随方向翻转**:`iter_desc_by` 只把**键**降序,同一个键内的槽位仍升序(`iter_by` 的
  既定语义)。因此 `desc` **不是** `asc` 的逐元素反转;测试按「键序列 + 桶内升序」两条分别断言,
  而不是简单 `reverse(asc)`(第一版测试正是这么写错的,已改成更强的方向断言)。
- **`abort` 的取证方式**:MoonBit 的 panic 不是 `Error`,`try`/`catch` 抓不住(MOONBIT_REF §0),
  所以 §7.1 的两类编程错误以**谓词测试**取证(`Index::is_ordered` 白盒、`Table::has_index` 黑盒),
  `abort` 行本身保持一行、由代码审阅覆盖。
- **`iter_asc_by` / `iter_desc_by` 的 `K : Compare` 被编译器判为「未使用」**(2 条
  `unused_trait_bound` 警告):这两个方法只走 `SortedMap` 的迭代器,并不需要比较。保留该约束是因为
  SPEC §3.3 把它们标注为「需 `Compare`」,且任何注册了有序索引的表其 `K` 必然实现 `Compare`;
  若 SPEC 去掉这个标注,删掉约束即可清零这 2 条警告。
- **`range_by` 跟随平台语义**(§3.3.1):双闭区间直接转发 core 的 `SortedMap::range`;半开区间
  另立名字明确的 `range_half_open_by`,不制造语义重叠。

#### M5 自检与诊断(2026-10-14)

- **I5 与 I3 在当前表示下是结构性保证,无法人为破坏**(实测确认):唯一象限是 `Map[K, Int]`
  (每桶恒 1 槽 → I5 恒真),非唯一桶是 `SortedSet[Int]`(槽位不重复 → I3 恒真),因此校验器里
  这两支**构造不出违反**。它们作为**防御性交叉校验**保留(SPEC §4 对 I3 也是这么写的),并补了一条
  **结构钉子**测试(唯一象限枚举出的每个桶恰好 1 槽;同时断言非唯一象限确实存在 2 槽桶,防止该断言
  因夹具巧合而空转)。若希望 I5 可被破坏/可测,需要把唯一象限的桶也换成集合类型(代价:holder 查询
  从 O(1) 退化)—— 本库不采纳,已在交付报告里提请裁定。
- **I7 的两半可达性不对称**:计数半可达并已测(删掉一个桶条目 → entries ≠ len);**覆盖半在
  I3 + I4 通过之后不可达**(投影正确的桶 + 无重复槽 ⟹ 每条活记录恰好出现一次),故同为防御性校验。
  验收清单里「I5 与 I7 各一条」按此现实落地:I7 计数半有消息定位测试,I5 以结构钉子 + 说明代替。
- **`insert_many` 批内冲突的 `holder` 语义**:SPEC §2.2 把 `holder` 定义为「活记录」,但批内冲突时
  没有活记录。本库落地为:返回**"更早成员将会获得的句柄"**,由只读的 `Table::planned_handles`
  精确预测(已有测试断言"预测 == 实际分配"),并在文档里写明「该句柄此刻不是活记录,因为整批被
  原子拒绝」。**提请裁定**:接受该语义并写进 SPEC,或给 `Conflict` 增加一个批内变体(会改动 §2.2)。
- **`insert_many` 的冲突顺序**:按批次顺序逐条查(先查活表、再查批内已声明键),因此报出的是
  **批次里第一个冲突的成员**;预检用 `Map[String, Map[K, Int]]` 记录"每个唯一索引已声明的键",
  只在预检阶段存在,失败时不发布任何东西。
- **`index_stats` 的返回类型**是 SPEC §3.4 里唯一没写死的签名(`-> ...`);本库定为公开结构体
  `IndexStats { buckets, entries, longest_bucket, average_bucket }`,**提请写进 SPEC**。
#### M6 工程面(2026-10-14)

- **`moon.work` 的处理(有实测证据)**:为让 `cmd/`、`bench/` 在包发布前解析本地模块,我用了临时
  workspace 清单并**实测其后果**:`moon publish --dry-run` 会把 `moon.work` **打进产物 zip**
  (逐条列出产物内容确认),但在解包目录上重跑 moon check 仍通过。结论:不是硬失败,但属于「发布物
  不该带的开发态文件」(与 bimap 的约定一致),故**不入库**并加入 `.gitignore`,配方写在 `.gitignore`
  注释与示例文件头。**M7 前仍建议复核**(真正的 mooncakes 行为只能在实际发布时确认)。
- **基准暴露的一处 SPEC 偏差**:实测显示 `remove` 比 `insert` 贵 20–44× 且随 n 增长 —— 因为 `order`
  数组是**原地压缩 O(len)**,而 SPEC §6 把 `remove` 记为 `O(I + Σ桶长)`。**提请裁定**:是把 SPEC §6
  改成含 `O(len)`,还是换掉 `order` 的表示(会牺牲插入序的紧凑性)。
- **两处不利基准数字照实报**:非唯一大桶的 `iter_by` 略慢于线性扫描、宽区间 `range_by` 比扫描慢
  ~20×,根因都是**每条产出记录一次 `(RowId, V)` 拷贝**(SPEC §3.3 已声明该代价)。
  由此给出一条 v0.2 候选:热循环用的「只给 id / 只给键」游走。
- **mbti 变化逐条**:`extends.mbt` 的促进让 5 个类型多出常规方法 —— `RowId::equal`、
  `Conflict::equal[K : Eq]`、`RegisterError::equal[K : Eq]`、`UpdateRejected::equal[K : Eq, V : Eq]`、
  `IndexStats::equal`;**没有任何既有签名被改或被删**;deprecated 的那些不出现在 mbti 里。
- **批内冲突的报告顺序**:同一成员同时撞「活记录」与「更早成员」时,表报告哪一条取决于注册表遍历序
  (稳定但非排序),SPEC 未规定;对拍按「模型给出冲突集合、表报告其中一条」处理。
  **提请裁定**:是否把冲突索引顺序钉死(例如按索引名升序)—— 代价是每次写入多一次排序。
- **示例与基准的运行前提**:`cmd/`、`bench/` 与差分夹具生成物都 **import 已发布的包**,发布前只能靠
  本地临时 workspace 运行(M6 已实测通过);M7 发布后按各文件头命令即可直接跑。
#### M7 发布准备(2026-10-14)

- **`moon publish` 未执行**(按派发要求:发布是不可逆的外部动作,等用户确认)。已做的是
  `moon publish --dry-run` + 产物清单核对。
- **`--dry-run` 的观察**:服务端返回 `202 Accepted / Dry run completed successfully`,打包 + 解包后
  重跑 `moon check` 也通过;但进程**以 1 退出**并打印 `moon publish failed`(两次一致)。原因未确认,
  记录在此以免后人误读「dry-run 全绿」—— **真正的发布形态只能在用户执行实际发布时确认**。
- **产物清单(实测,47 项)**:`moon.work` **已不在产物中**(gitignore 生效,命中数 0);仍会打包
  `bench/` `cmd/` `tools/` `docs/` `AGENTS.md` `CONTRIBUTING.md` `CHANGELOG.md` `third_party/`。
  `moon.mod` **没有排除字段**(官方字段只有 name/version/readme/repository/license/keywords/
  description/source/preferred_target/warnings),所以「不打包开发态目录」只能靠**把目录移出模块目录**
  达成,代价是一次仓库重排。**建议:按现状发布**(解包后 check 通过,非包目录对使用方是惰性的),
  这条留给用户拍板。
- **命名空间**:`aurasuisui/multiindex` 与作者已发布的 `aurasuisui/bimap`、`aurasuisui/indexmap` 同命名空间 ✓
- **仍未改动**:`docs/SPEC.md`(审核方所有)与 `docs/README.md` 的地图(新增的 `src/json_test.mbt`、
  `src/bench_test.mbt` 是测试文件,不入地图)。
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

#### M11 能力扩展(2026-10-20)

- **砍尾:`SparseSet` 本轮不做**。按 [`docs/plans/v0.2.0.md`](docs/plans/v0.2.0.md) §四「从尾部砍」:
  基准里哈希桶并不慢,这是**没有实测痛点**的推测性优化。相应地**没有开 Issue** —— 它不是实测到的问题
  (开了就是凑数)。记录在 SPEC §11 的 v0.2 候选里;`insert_or_replace` 与 `index_entries` 都做完了,
  被砍的只有这一项。
- **`index_entries` 的约束比简报更宽(有据)**:简报写 `K : Hash + Eq + Compare`,但方法体只查注册表,
  编译器直接给三条 `unused_trait_bound [0053]`;`--deny-warn` 下即 CI 红。删掉未使用的约束后签名是
  `pub fn[K, V] Table::index_entries(...)`,对调用方**只会更宽**,不是破坏(SPEC §2.5.1 补记)。
- **`insert_or_replace` 里那个"永不触发"的 `Err` 分支是故意的**:判定函数正确时,`Replace` 分支的
  排除自身预检必为 `None`;留着它,判定若回归就退化成 `update` 语义的 `Err(Conflict)`(表仍零变更),
  而不是把 I5 写坏。白盒测试把这条一致性钉住(SPEC §3.2.2)。
- **为什么 `abort` 而不是新变体**:`Conflict[K]` 只有 `UniqueViolation` / `DuplicateInBatch`,加第三个
  会让所有既有 `match` 不再穷尽;消息按索引名升序保证同一状态给出同一段文本(SPEC §3.2.2(b))。

#### M12 — 发布 v0.2.0(2026-10-20)

- **版本 `0.1.0` → `0.2.0`**:`moon.mod` 与 `src/lib.mbt` 的 `VERSION` 同步;CI 新增一步校验两者相等
  (此前没有任何检查能发现"忘了改 VERSION",而 `moon info` 的快照恰好把这个常量也带出去)。
- **SemVer 判定 = MINOR(有据)**:相对 `v0.1.0` tag,公开接口**只增不减** —— `swap_remove` /
  `insert_or_replace` / `IndexKind` / `index_entries` 四项,`src/pkg.generated.mbti` 里
  一行 `-pub` 都没有。
- **CI 从「永远红」修到全绿 —— 根因不在代码**:自 2026-10-14 起每次都在 13 秒内失败,死点是
  `setup-moonbit` **自己的下载步骤**返回 `curl: (22) ... 403`。实测 `cli.moonbitlang.com`
  **只提供 `latest`**:在 `0.1.20261012` 上试了 12 种写法(`+hash`、`%2B` 编码、`-dev`、`v` 前缀、
  相邻日期 `20261011` / `20261013` ……)全部 403,只有 `latest` 返回 200。所以「固定版本号」在
  这条通道上**不可能实现**,原 `ci.yml` 的 pin 是死配置。改为官方 `install/unix.sh` + 每步打印实际
  `moon version`,把"版本漂移"变成可见的红 + 精确版本号。
- **另一个一直没被发现的问题**:原触发器只有 `main` / `master`,**`dev` 上的所有改动从未跑过 CI**,
  这正是"本机能过、CI 红"拖了 6 次才被正面处理的原因之一;现已加入 `dev`。
- **接口门禁按拼写归一化**:CI 用 `0.1.20261016`、本机 `0.1.20261012`,前者把 `Int` 打印成规范的
  `Int32` —— 同一个类型的两种写法。归一化后比较,真实签名变化仍会被抓到
  (留证:CI 与本机的**全部**差异恰好只有 `Int32` / `Int` 这一处)。
- **B4(PII)关闭**:`docs/申报书.md` 的姓名与手机号在 HEAD 上已去标识化(只留 GitHub ID),
  联系方式改为指向报名问卷。**残留风险如实记录**:PII 从 commit `6108604` 起仍在 git 历史里,
  仓库是公开仓库,本版**未做** force-push 改写历史。
- **`docs/SPEC.md` 两处表格断裂修复**:`clear()` 行被 §3.2.1 截断、`get` / `contains` / `len` /
  `iter` 四行被 §3.3.1 截断,均已移回所属表格;删掉一行与 §3.1 重复的 `index_names()`。
- **`--dry-run` 的 exit=1 是假警报,已定位**:`moon publish --dry-run` 在服务端返回
  `202 Accepted` + "Dry run completed successfully" 时仍以非零码退出 —— 客户端把 202 当失败。
  真实发布返回 `200 OK`、exit=0(M7 实测),所以**不能**用 dry-run 的退出码判断能不能发布。
- **RELEASE_CHECKLIST Tier 0–4** 全绿,证据见该文档「最近一次执行」表。
- **发布结果(2026-10-20)**:`moon publish` → `Server status: 200 OK`、exit=0;注册表
  `latest_version = 0.2.0`、`build_status = success`、`versions = 0.2.0, 0.1.0`;tag `v0.2.0` 已推送。

---

## [0.1.0] - 2026-10-14

已发布到 mooncakes.io(发布 commit `8f69e79`,registry `build_status: success`,`yanked: false`)。
内容为 M1–M7;`0.2.0` 在其上做向后兼容扩展,故本节不再重复列出各项。
