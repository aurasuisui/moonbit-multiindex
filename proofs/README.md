# proofs/ — 用 SMT 校验核心不变量

这里放的是**可机器复跑**的不变量证明:每条 `.smt2` 把一条不变量编码成逻辑公式,断言其否定,交给 z3。
返回 `unsat`(否定式不可满足)当且仅当该不变量成立。

```powershell
powershell -NoProfile -File proofs/run.ps1                 # 用 PATH 上的 z3
powershell -NoProfile -File proofs/run.ps1 -Z3Path C:\z3\z3.exe
```

全部通过时输出 `all proofs checked`,退出码 0。

## 证明内容

| 文件 | 断言的不变量 | 结论 |
|---|---|---|
| `swap_remove_positions.smt2` | `swap_remove(i)` 之后,`positions` 仍是 `order` 在新长度上的逆(即 `positions[order[k]] == k`) | unsat ✅ |
| `clear_retires_generations.smt2` | `clear()` 批量退役槽位之后,clear 之前发出的 `RowId` 不可能命中 clear 之后的记录 | unsat ✅ |

### swap_remove_positions

对应 [`docs/SPEC.md`](../docs/SPEC.md) §13 R3 的「只重排 `order`、不搬 `rows`」设计。模型里 `order[k]`
是第 k 个位置上的槽位号,`positions[s]` 是槽位 s 当前所在位置;前提是 `order` 为有限双射、`positions`
为其逆;结论是换掉位置 i 之后逆关系仍成立。**这条不是恒真式**——它依赖「`order` 单射」这个前提:
若允许两个位置指向同一槽位,证明会失败。

### clear_retires_generations

对应 [`docs/SPEC.md`](../docs/SPEC.md) §2 的 `RowId` 契约。这条证明是**代数层面**的:它说明只要
`clear()` 对每个槽位把代际号加一(而不是清零或原样保留),「旧句柄复活」在算术上就不可能发生。
这正是本库把 `clear()` 实现成批量退役、而不是「清空 rows 后把槽位原样放回 free」的理由。

## 这些证明**不**覆盖什么

- 它们不验证 MoonBit 源码本身,而是验证**设计所依赖的逻辑关系**。代码是否忠实实现了 model,
  由单元测试、属性测试、对拍测试负责(见 [`CONTRIBUTING.md`](../CONTRIBUTING.md))。
- 并发、内存安全、性能都不在证明范围内。
- `swap_remove_positions` 只覆盖「逆关系保持」,不覆盖「未删除记录的内容不变」等其余性质。

## 与 `moon prove` 的关系(重要)

本仓库**没有**在 CI 里启用 `moon prove`,原因是在当前开发机上该链路跑不通,实测证据如下
(记录于此以免后人重复踩坑):

1. `moon prove` 需要 `moon.pkg` 里写 `proof_enabled = true`(不是 `options("proof": true)`,
   后者只是把选项透传给 moonc;写 `proof = true` 会报 `Unexpected key 'proof' found in moon.pkg.`)。
2. z3 可以通过 `Z3PATH` 或 PATH 被找到,WhyML 也能正确生成(例如最小目标 `ident'vc : eq x x = True`)。
3. 但**每一个**目标都返回 `Failure (no prover available)`,attempts 里是 `Z3: Failure (high failure)` ——
   包括 `eq x x = True` 这种恒真目标。这说明断在 why3 与 z3 的调用/解析层,而不是「题目太难」。
4. 已排除的变量:z3 5.3.1 / 4.13.4 / 4.12.6(4.12.x 是内置 why3 检测数据支持的最高版本)三个版本;
   `Z3PATH` 与 PATH 两种发现方式;带不带 `.exe` 后缀。结果完全一致。
5. z3 本身工作正常:命令行直接跑、以及按 why3 检测数据里的原始参数经 `why3cpulimit.exe` 调用,
   都能正确返回 `unsat`。所以不是 z3 二进制的问题。

因此本目录改用「直接写 SMT-LIB 交给 z3」的方式做形式化校验:绕开 why3,结论同样可复跑。
若将来 `moon prove` 在 Windows 上修好,可以把这些不变量迁移成 `.mbtp` 里的 predicate 直接用。
