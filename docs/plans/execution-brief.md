# plans/execution-brief.md — 执行/审核分工与交接书

> 本仓库采用**执行会话 + 审核会话**分离的工作方式:**执行会话负责写代码,审核会话负责判定是否过关**。
> 这份文件是两者之间的契约 —— 执行会话**开工前必读**,审核会话**验收时逐条对照**。

---

## 一、角色与权限

| 角色 | 可以做 | 不可以做 |
|---|---|---|
| **执行会话**(executor) | 在 §四 范围内写实现与测试、提交 commit、更新 CHANGELOG 与文档 | 改 [`SPEC.md`](../SPEC.md) 的契约、放宽/删除不变量断言、跳过出口条件、扩大范围 |
| **审核会话**(reviewer) | 独立复跑 CI、读代码与测试、**驳回**未达标的里程碑、要求返工 | — |

**核心纪律**:执行会话**不给自己判分**。做完只能报"待审核",由审核会话复跑后判定 ✅。

---

## 二、执行会话开工前必读(按顺序)

1. [`../../AGENTS.md`](../../AGENTS.md) — 命令、架构、不变量、测试约定、代码风格
2. [`../SPEC.md`](../SPEC.md) — **API 唯一真源**(签名/语义有疑问以此为准)
3. [`../DEVPLAN.md`](../DEVPLAN.md) — 数据布局、三条汇聚点、四条高危路径
4. [`v0.1.0.md`](v0.1.0.md) — 里程碑与**出口条件**、§一"不是移植"
5. [`../SESSION_PLAYBOOK.md`](../SESSION_PLAYBOOK.md) — 卡住时的决策规则

---

## 三、执行纪律

1. **一个里程碑一个 commit**(Conventional Commits:`feat:`/`fix:`/`test:`/`docs:`),便于审核按里程碑回溯。
2. **不攒未编译代码**:每写完一段 `moon check`,每个小节点 `moon test`。
3. **不得削弱不变量断言**换测试通过 —— 那是本库的命根子。断言过不去说明实现有问题。
4. **不改 SPEC 契约**。发现 SPEC 有问题 → 在回复里**提出**,由审核会话裁定后再改。
5. **不扩大范围**。当前里程碑之外的东西一律不做(可以记进回复的"发现/建议")。
6. **不引入依赖**(`aurasuisui/bimap`、`aurasuisui/indexmap` 都不许 import)。
7. **卡住时的优先级**(SESSION_PLAYBOOK §3):编译错误查 `MOONBIT_REF.md`;语义不确定查 SPEC;
   单个测试卡超过 15 分钟 → 打 `// TODO:` 跳过并继续,**绝不停摆**。
8. **四象限 / 汇聚点 / 高危路径**是硬约束,见 DEVPLAN §2/§4。
9. **里程碑边界是审核关口,不是等待指令**:默认节奏是"完成里程碑 → 回报 → 等审核结论 → 继续下一个"。
   执行会话**不得越过未通过的关口**推进,但通过之后可以直接继续,不必每次另等"派发"。
   用户可**随时**要求在某阶段后暂停,此时执行会话保持 idle,直到收到返工单或恢复指令。
   > 暂停是**用户可选的节奏控制**,不是默认状态。

---

## 四、当前任务:**M1 — 记录存储**

### 范围(只做这些)

1. `src/lib.mbt`:补齐公开类型 `RowId`、`Conflict[K]`、`Rejected[K, V]`、`VERSION`(已存在部分,**按 SPEC §2 校对**)。
2. `src/table.mbt`:`Table` 骨架 —— 字段 `rows : Array[V?]`、`gens : Array[Int]`、`free : Array[Int]`、
   `order : Array[Int]`、`mut len`、`mut version`;以及**无索引**的基础操作:`insert` / `get` / `remove` /
   `len` / `is_empty` / `clear` / `iter`(插入序)。
3. **槽位分配与回收**:空闲栈 LIFO 复用;删除时 `gens[slot] += 1` 并归还槽位;
   陈旧 `RowId`(代际不匹配)的 `get`/`remove` 必须返回 `None` 且**不触碰槽的新占用者**。
4. **I9(代际号溢出即退役槽位)**:代际号达到上限时**不把该槽放回 `free`**(永久退役)。
   上限取值自行确定并写进 SPEC 的待裁定项(建议 `Int` 的某个安全上界,别等到真溢出)。
5. 测试:`src/table_test.mbt`(单元)、`src/property_test.mbt`(`check_invariants` + 随机序列)、
   `src/table_wbtest.mbt`(白盒:`free` 无重复且与活槽不相交、代际单调)。
6. `src/moon.pkg` 按需补 import(`test`/`quickcheck`/`debug`)。

### 关于类型参数 `K`

M1 还没有索引,用不上 `K`。两种做法**任选其一**,在回复里说明选了哪个:

- (a) 若 MoonBit 对未使用的类型参数**不报 warning**:先 `struct Table[K, V]`,M2 再加索引字段;
- (b) 若**会报 warning**:M1 就把索引注册表字段与 `Index` 枚举**声明**出来(只声明,不实现桶操作),
  使结构体形态一次到位,避免 M2 大改。

> 倾向 (b):结构形态早定,返工少。

### **不做**(属于后续里程碑)

索引注册与桶操作(M2)、冲突检查与 `update`/`modify`(M3)、有序索引与范围查询(M4)、
`insert_many`/`index_stats`(M5)、对拍/差分/基准/示例(M6)、发布(M7)。

### 出口条件(全部满足才算 M1 完成)

- [ ] `moon fmt --check` / `moon check` / `moon test` / `moon build` 全绿;
      `moon info` 后 `git diff --exit-code` 干净(即 `src/pkg.generated.mbti` 已提交)
- [ ] 单元测试覆盖:`insert` 返回的 `RowId` 可取回记录;删除后长度正确;`iter` 为插入序
- [ ] **槽位复用**:删除后再插入会复用槽位,且**旧的 `RowId` 被拒绝**(`None` / `false`)
- [ ] **代际号单调**:同一槽每次复用 `gen` 递增
- [ ] 属性测试:`check_invariants` 在随机 `insert`/`remove` 序列**每一步之后**成立,覆盖 I1 / I2 / I6
- [ ] 白盒测试:直接读私有字段断言 `free` 无重复、与活槽不相交
- [ ] `CHANGELOG.md` 有对应 entry
- [ ] 文档地图([`../README.md`](../README.md))仍无孤儿条目

### 完成后要交给审核会话的证据

1. 四条 CI 命令的**实际输出**(不是"已通过");
2. `moon test` 的**测试计数**;
3. `git log --oneline` 新增的 commit;
4. 做法说明:类型参数选了 (a) 还是 (b)、代际号上限取值、以及任何**偏离 SPEC 的地方**;
5. 你在实现中发现但**没有动手改**的问题(留给审核会话裁定)。

---

## 五、审核会话的验收清单(逐条对照,不通过则驳回)

**先独立复跑,不信报告:**

1. `moon fmt --check && moon check && moon test && moon build` —— **自己跑一遍**;
   `moon info && git diff --exit-code` 是否干净。
2. `git log --oneline` 与 `git show --stat` —— 是否按里程碑提交、有没有夹带范围外改动。

**再读代码与测试:**

3. `property_test.mbt`:`check_invariants` 是否**真的**断言了 I1/I2/I6?有没有被削弱、
   有没有把断言换成"$$ 打日志"、有没有 `ignore` 或提前 `return`?
4. `table_wbtest.mbt` 是否**直读私有字段**(而不是用公开 API 绕一圈装样子)?
5. 槽位复用时**旧 `RowId` 被拒绝**这条,是否真的有测试覆盖(这是最容易漏的原创点)。
6. 变更是否**汇聚**在少数几个函数里(汇聚点纪律),还是散落各处?
7. 有没有引入依赖、有没有 `TODO`/`ignore` 未说明?

**最后对照交付物:**

8. `CHANGELOG.md` / `docs/README.md` 地图 / `pkg.generated.mbti` 是否同步。
9. 出口条件逐条打勾;**任何一条不满足 → 驳回并列出返工项**。

**审核结论只有两种**:✅ 通过(可以进入下一个里程碑)或 ❌ 驳回(附具体返工清单)。
不允许"有条件通过"。
