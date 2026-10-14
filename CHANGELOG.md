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
