# MOONBIT_REF.md — MoonBit 语法/惯用法速查(实测版)

> **分工**:本文件讲**语言与 API 的事实**(语法、实测行为、错误码)。
> **命名约定、代码组织、文档注释、测试风格、CI、license header** 这些**官方约定**另见
> [`STYLE.md`](STYLE.md) —— 两份合起来才是完整的开发参考。

## 本文件的来源与可信度标记

> **审核记录(2026-10-14)**:本文件由独立调研会话重写,并由审核会话**独立复验**了以下关键结论
> (全部自建探针实跑,不采信报告):`\{x}` 插值成立、`\(x)` 报 `[4064]`;`SortedMap::range` 确为双闭
> `[lo, hi]`;`mut` 用在只做 `push` 的字段上报 `Error [0015]`(且会让 `moon check` 失败);
> `import {..} for "test"` 语法可用。审核同时**发现并补入 §3.0(Int 是 32 位)** —— 这是原文缺失、
> 且本项目已实际踩中的坑。


**基线工具链**(2026-10-14 本机实测):

```text
moon      0.1.20260920 (914d7da 2026-09-20)   ~\.moon\bin\moon.exe
moonc     v0.10.14+7d59c7ec9 (2026-09-18)      ~\.moon\bin\moonc.exe
moonrun   0.1.20260920 (914d7da 2026-09-20)   ~\.moon\bin\moonrun.exe
Feature flags enabled: rr_moon_mod, rr_moon_pkg
moonbitlang/core 版本: 0.10.14+7d59c7ec9     (%USERPROFILE%\.moon\lib\core\moon.mod)
```

**可信度四级标记**——每条结论都带标记,**没有标记的句子不要当事实用**:

| 标记 | 含义 |
|---|---|
| **[实测]** | 本机在临时探针工程里 `moon check` / `moon run` / `moon test` 真跑通过(或真报错),附可复现代码 |
| **[源码]** | 逐行读 `%USERPROFILE%\.moon\lib\core\<pkg>\pkg.generated.mbti` 或该包 `.mbt` 源码得到的签名 |
| **[文档]** | 来自 `https://docs.moonbitlang.cn/`(2026-10-14 抓取),未在本机复跑 |
| **[未核实]** | 未验证的推测/传闻/旧文件残留。**不要依赖** |

> 探针工程已删除。复现方法见 §11。

---

## §0 最容易踩的十条(全部 [实测],先看这个)

| # | 坑 | 正确写法 / 结论 |
|---|---|---|
| 1 | **字符串插值是 `\{expr}` 不是 `\(expr)`** | `"n=\{n}"`。写 `\(n)` 报 `Error [4064] Invalid escape sequence: \(` |
| 2 | **结构体/枚举泛型参数不能带 trait 约束** | `struct Index[K : Hash + Eq, V]` 是**解析错误**:`Error [3002] Parse error, unexpected token ':'`。约束写到方法上 |
| 3 | **`SortedMap` / `SortedSet` 不在 prelude** | 必须写 `@sorted_map.SortedMap([])` / `@sorted_set.SortedSet([])`,并在 `moon.pkg` 里 import |
| 4 | **`derive(Show)` 已废弃** | `Warning [0027] deprecated_syntax: 'derive(Show)' is deprecated`。改 `derive(Debug)` + 手写 `impl Show` |
| 5 | **`derive(Eq/Hash/Debug/...)` 会触发 `implicit_impl_as_method` 弃用警告 `[0079]`** | 紧跟 `pub extend T with Trait::{meth, ..}`。`--deny-warn` 下不写就挂 |
| 6 | **`SortedMap::range` / `SortedSet::range` 是双闭区间 `[lo, hi]`** | 不是 `[lo, hi)`。`range(1,3)` 在键 `1,2,3,4` 上返回 **3** 个元素 |
| 7 | **`Iter2` 只有极少方法** | 没有 `count` / `fold` / `map`。只有 `concat` `each` `iter` `iter2` `new` `next` `to_array` |
| 8 | **`m[k]` 缺键会 panic,不是抛可捕获的 Error** | `let _ = m["missing"]` 直接 abort,**`try`/`catch` 抓不到**。要安全取值用 `m.get(k)` 拿 `Option` |
| 9 | **`moon.pkg` 的测试依赖现在是 `import { .. } for "test"` / `for "wbtest"`** | 旧写法 `test-import { .. }` **不能编译**(`Lexing error`) |
| 10 | **`mut` 字段只在「字段赋值」时才需要** | `Array` 字段只做 `self.items.push(x)` 却标 `mut` → `Error [0015] unused_mut`(在测试构建里直接是 error) |

补充:`moon check` **查不出**某些方法不存在(如 `Iter2::count`),要到 `moon build` / `moon run` / `moon test` 才报 `Error [4015] ... has no method`。**新增 API 调用后一定要跑一次 `moon test`,不要只看 `moon check`。**

---

## §1 工程结构:三种清单文件

| 文件 | 作用域 | 现状 |
|---|---|---|
| `moon.mod` | 一个**模块**(= 一个可发布单元) | 当前格式;旧格式 `moon.mod.json` 仍被兼容 |
| `moon.pkg` | 一个**包**(= 一个目录) | 当前格式;旧格式 `moon.pkg.json` 仍被兼容 [文档] |
| `moon.work` | **工作区**(多个模块一起解析) | 可选,见 §1.5 |

### 1.1 `moon.mod` —— 本项目实文件 [实测:能 `moon check` 通过]

`moonbit-multiindex/moon.mod` 现状(逐字段可用):

```toml
name = "aurasuisui/multiindex"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/aurasuisui/moonbit-multiindex"

license = "Apache-2.0"

keywords = [
  "multi-index",
  "secondary-index",
  "record-store",
  "data-structure",
  "indexmap",
]

description = "A record store with N secondary indexes (unique / non-unique / sorted) over stable generational IDs - the N-index generalization of a BiMap"

source = "src"
```

**关键语义 [实测]**——这些是探针跑出来的,不是猜的:

- `source = "src"` 之后,**模块只扫描 `src/` 下的包**。放在同级的 `bench/`、`cmd/`、`tools/` **不是**本模块的包:`moon check` 于根目录**根本不会碰它们**(与 `AGENTS.md` 的说法一致),但反过来 `moon build bench` / `moon -C bench run .` 也会失败:

```text
Error: Cannot find package to build based on input path ...\bench
Hint: ... it is not in the path for searching packages, thus it cannot be resolved to any known package.
```

- 跨模块依赖**只能写带版本号的注册表式依赖**:`import { "probe/layout" }`(无 `@version`)直接报 `moon.mod only supports versioned registry dependencies in import, found probe/layout`。

- `repo` 的 `Name`, `Version`, `Readme` 等字段不必都有;本项目的 8 个字段都只是元数据,不参与编译。

### 1.2 `moon.pkg` —— 包清单(当前语法) [实测]

从核心库 `~/.moon/lib/core/hashmap/moon.pkg` 抄来的真实形态:

```
import {
  "moonbitlang/core/debug",
  "moonbitlang/core/json",
}

// 只对黑盒测试 (*_test.mbt) 可见
import {
  "moonbitlang/core/test",
  "moonbitlang/core/quickcheck",
} for "test"

// 只对白盒测试 (*_wbtest.mbt) 可见
import {
  "moonbitlang/core/test",
} for "wbtest"

// 可执行包(含 fn main)必须声明;库包不写
pkgtype(kind: "executable")
```

**易错点 [实测]**:

- 旧写法 `test-import { "moonbitlang/core/test" }` **不能编译**,报 `Failed when discovering packages ... Unable to read moon.pkg ... Lexing error at N..N`。正确关键字是 `import { ... } for "test"`。

- 官方文档 [文档] 把 `for "test"` 叫 *test-import section*;白盒测试看 `import` + `wbtest-import`,黑盒测试看当前包 + `import` + `test-import`。

- 项目当前 `src/moon.pkg` 只有一行注释(无 import),**这是合法的**——`pkgtype` 与 import 都可省略,库包默认为 library。[实测:`moon check` 通过]

- `@json` / `@test` / `@debug` / `@quickcheck` / `@string` 等 core 包名,**用了就必须 import**,否则 `Warning [0071] core_package_not_imported: Package 'X' from 'moonbitlang/core/' is used without import. This is deprecated.`

- `Map` / `Iter` / `Iter2` / `Array` / `String` 来自 **`prelude`**,**无需 import** [源码:`prelude/pkg.generated.mbti` 有 `pub using @builtin {type Map}`]。

- 自定别名写法 [文档]:`import { "user/pkgA", "user/pkgC" @c, }` → 用 `@c.xxx` 访问。

### 1.3 `.gitignore`

```
target/
_build/
.moon/
```

> 注:本机实测 `moon` 的产物目录是 `_build/`。旧文件只写了 `target/`,建议两个都留。

### 1.4 可执行包与 `pkgtype` [实测]

只有含 `fn main` 的包才需要 `pkgtype(kind: "executable")`;漏 `fn main` 会报:

```text
Error [4067] Missing main function in the main package.
```

而没声明 `pkgtype` 却写了 `fn main` 的包默认是 library,`moon run .` 跑不起来。

### 1.5 `bench/` / `cmd/` 这类「旁挂」目录怎么跑 [实测]

因为它们不在 `source = "src"` 的扫描范围内,也不能靠相对路径 import(`moon.mod` 只接受带版本号的依赖),所以要**两步**:

```bash
# ① 让 bench/ 与 cmd/* 成为独立模块(各自一个 moon.mod),
#    再把它们和根模块一起登记进工作区清单 moon.work
moon work init
moon work use . bench cmd/demo

# ② 然后就能单独构建/运行
moon -C bench run .
moon -C cmd/demo run .
```

`moon.work` 的内容形如 [实测]:

```toml
members = [
  ".",
  "./bench",
  "./cmd/demo",
]
```

而 `bench/moon.mod` 里依赖**必须写成带版本号**的形式 [实测]:

```toml
name = "probe/layout-bench"
version = "0.1.0"
source = "."

import {
  "probe/layout@0.1.0",
}
```

> **对本仓库的提醒**:`AGENTS.md` 说 `cmd/*` 与 `bench/` 是 standalone、import **已发布**的包 —— 这与实测一致(版本号来自注册表)。但本仓库目前 `bench/` 下只有 `README.md`,没有 `moon.mod` / `moon.pkg` / `main.mbt`,`moon -C bench run .` 跑不起来;真要跑基准需要补齐这三个文件(见 `docs/DEVPLAN.md` §8 的 `bench/main.mbt`)。

---

## §2 常用命令

### 2.1 八项 CI(两个 job,本项目门禁,与 `AGENTS.md` 一致)

```bash
moon fmt --check                              # 1. 格式检查
moon check                                    # 2. 类型检查
moon check --deny-warn --target all           # 3. 零警告门禁(含 missing_doc)
moon info && git diff --exit-code             # 4. 公开接口快照必须已提交
moon test                                     # 5. 测试(默认后端)
moon test --target all                        # 6. 同一套测试 × 四个后端
moon build                                    # 7. 构建
```

第 8 项是**独立 job** `example-smoke`:在仓库根生成 `moon.work`(`members = [".", "bench", "cmd/leaderboard"]`,**没有** `[workspace]` 头),`cd cmd/leaderboard && moon run .`,断言演示输出的三处地标与 `VERSION`(必须等于本仓库 `moon.mod` 的版本 —— 注册表副本也打 `(local workspace module)` 后缀,只有版本能区分来源),结束时 `trap` 删除 `moon.work`。两个 job 都绿才算过。

第 4 步是**承重**的:`moon info` 重新生成 `src/pkg.generated.mbti`,这是**入库的接口快照**。改了公开签名必须 `moon info` 并提交,否则 CI 红。这一步在 CI 里还附带两件事:① 比较前把 `Int32`/`Int` 两种拼写归一化(CI 与本机工具链打印不同);② 校验 `moon.mod` 的 `version` 与 `src/lib.mbt` 的 `VERSION` 相等。

### 2.2 `moon test` 的过滤选项(**旧文件写错了**)

以 `moon test --help`(本机实测输出)为准:

| 选项 | 含义 |
|---|---|
| `-f, --filter <FILTER>` | 按**测试名 glob** 过滤,支持 `*` 和 `?` |
| `-i, --index <INDEX>` | 只跑**单个文件**里的第 i 个测试;接受 `0-2` 左闭右开区间;**仅在该次只选了一个文件时有效**;隐含 `--include-skipped` |
| `-p, --package <PACKAGE>...` | 只跑指定**包**(不是 filter!) |
| `-u, --update` | 更新快照 |
| `-l, --limit <LIMIT>` | 限制快照更新轮数,默认 256 |
| `--doc-index <DOC_INDEX>` | 只跑第 i 个 **doc test** |
| `--include-skipped` | 包含被跳过的测试 |
| `--outline` | 只打印将要执行的测试大纲 |
| `--build-only` | 只构建不跑 |
| `--test-failure-json` | 失败信息以 JSON 输出 |
| `-d, --deny-warn` | 警告当错误 |

**实测验证过的例子**:

```bash
moon test -f '*snapshot*'          # 只跑名字含 snapshot 的测试
moon test -i 0 src/lib_test.mbt    # 只跑该文件第 0 个测试
```

> **旧文件的错误**:`moon test --test-filter "pat"`。当前 CLI **没有 `--test-filter`**,正确的是 `-f/--filter`。`AGENTS.md` 里的 `moon test -f "*unique*"` / `moon test -i 0 src/table_test.mbt` 是**对的**。

### 2.3 其他常用

```bash
moon check -d            # = --deny-warn,警告当错误(本项目本地验收口径)
moon fmt                 # 格式化
moon fmt --check         # 只检查
moon info                # 生成/更新 pkg.generated.mbti
moon build --target all  # wasm / wasm-gc / js / native / llvm
moon run .               # 跑当前可执行包
moon bench               # CLI 基准子命令(不是 @bench;见 §8.4)
moon doc <symbol>        # 查文档
moon explain <诊断>      # 解释某条诊断
moon tree                # 依赖树
moon coverage            # 覆盖率工具
moon publish             # 发布到 mooncakes.io
```

---

## §3 语法与语言要点

### 3.0 **`Int` 是 32 位有符号整数** [实测,踩过坑 —— 审核会话补入]

**`@int.max_value == 2147483647`(即 2^31-1),在 native 与 js 两个 target 上实测一致。**
**不要把它当成 64 位来推理。**

```moonbit
println("1 << 30 = \{1 << 30}")        // 1073741824
println("1 << 62 = \{1 << 62}")        // 1073741824  ← 与 1<<30 完全相同!
println("max     = \{@int.max_value}")  // 2147483647
```

**`1 << 62` 不报错,它会静默变成 `1 << (62 mod 32)` = `1 << 30`。**
这是最危险的一类坑:编译通过、运行正常、**语义完全不同**。

- 需要真正的 64 位 → 用 **`Int64`**(显式类型,语义不随 target 变化);
- 需要"很大但安全"的常量 → 写**显式字面量**并在注释里说明依据,**不要用移位去表达"很大"**;
- 本项目的真实案例:`GEN_MAX` 最初写成 `const GEN_MAX : Int = 1 << 62`,注释还声称
  "fits in a 64-bit signed `Int`"。实际值是 2^30 —— 行为侥幸安全(2^30 次复用不可达),
  但**依据是假的、常量是误导的**,而测试全绿并不能暴露它。详见
  [`SPEC.md` §2.1.1](SPEC.md) 与 `src/table.mbt`。


### 3.1 字符串插值:是 `\{expr}` [实测]

```moonbit
let n = 3
let s = "n=\{n}"                 // => "n=3"   ✅
let d = "sum=\{1 + 2}"           // => "sum=3" ✅ 里面可以写表达式
// let bad = "n=\(n)"            // ❌ Error [4064] Invalid escape sequence: \(
                                 //    Hint: Use `\{x}` for string interpolation.
```

> **旧文件通篇使用 `\(x)` 风格?** 检查一下——当前工具链明确报 `Invalid escape sequence: \(`,并提示改用 `\{x}`。

### 3.2 结构体/枚举泛型**不能**带 trait 约束 [实测,本项目命门]

这是 `AGENTS.md` 和 `SPEC.md` §2.4 反复强调的那条。实测确认:

```moonbit
// ❌ 解析错误
// pub struct BadIndex[K : Hash + Eq, V] {
//   name : String
//   project : (V) -> K
// }
//
// Error [3002]
//   pub struct BadIndex[K : Hash + Eq, V] {
//                           ^
//   Parse error, unexpected token `:`, you may expect `,` or `]`.
```

正确做法:**类型参数裸写,约束写在使用它的每个方法/函数上** [实测可编译运行]:

```moonbit
///|
pub struct Index[K, V] {
  name : String
  project : (V) -> K
  unique : Bool
}

///|
pub fn[K, V] Index::key_of(self : Index[K, V], v : V) -> K {
  (self.project)(v)          // 见 §3.3
}

///|
// 约束按“这个方法真正需要什么”最小化地写
pub fn[K : Hash + Eq, V] Index::lookup(self : Index[K, V], bag : Map[K, V], v : V) -> V? {
  bag.get((self.project)(v))
}
```

**顺带一个警告雷 [实测]**:约束写多了会报 `Warning [0053] unused_trait_bound: This trait bound is unused.`。上面 `lookup` 初稿写成 `[K : Hash + Eq, V : Hash + Eq]` 时,`V : Hash + Eq` 就被 `[0053]` 点名。**只写真正用到的约束**。

对应的枚举同样如此:

```moonbit
pub enum Quad[K, V] {
  Unique(K, V)
  NonUnique(K, Array[V])
} derive(Debug, Eq)
```

### 3.3 闭包作结构体字段,以及 `(field)(arg)` 调用 [实测]

这是本库「运行时注册索引」的语法基础(`register_unique(name, (V) -> K)`)。实测可用:

```moonbit
///|
pub struct Index[K, V] {
  name : String
  project : (V) -> K          // 闭包直接做字段,无 Box/Fn trait 之类的东西
  unique : Bool
}

///|
pub fn[K, V] Index::key_of(self : Index[K, V], v : V) -> K {
  (self.project)(v)           // ⚠️ 必须给字段访问整体加括号再调用
}

///|
pub fn demo() -> Unit {
  let idx : Index[String, Int] = {
    name: "by_s",
    project: fn(v) { v.to_string() },   // 匿名闭包,参数类型由字段类型推断
    unique: true,
  }
  println(idx.key_of(7))         // => 7
}
```

补充 [实测]:

- 闭包字段可以是**带效果**的:`g : (Int) -> Int raise`,调用 `(h.g)(x)` 需要外层函数标 `raise`。

- 结构体字面量用 `{ field: value, }`,**尾随逗号可有可无**;单字段 `{ code }`(简写)会触发 `Warning [0022] ambiguous_block`,写 `{ code, }` 更保险。

### 3.4 `mut`:字段赋值才是「可变」 [实测,反直觉]

MoonBit 的引用语义让「改对象内部」和「给字段重新赋值」是两件事:

```moonbit
// ✅ Array 字段不加 mut,元素级修改照样生效
pub struct BagA {
  items : Array[Int]
  name : String
}

///|
pub fn BagA::push(self : BagA, x : Int) -> Unit {
  self.items.push(x)            // 改的是 Array 的内容,不是字段本身
}

// ✅ 标量字段要重新赋值,必须 mut
pub struct Counter {
  mut n : Int
}

///|
pub fn Counter::bump(self : Counter, by : Int) -> Unit {
  self.n = self.n + by          // 字段赋值 ⟹ 需要 mut
}

// ❌ 标了 mut 却从不赋值 —— 即使你在改它指向的 Array
// pub struct BagB { mut items : Array[Int] }
// pub fn BagB::push(self : BagB, x : Int) -> Unit { self.items.push(x) }
// Error [0015] unused_mut: The mutability of field 'items' is never used, try remove `mut`.
```

**注意严重性 [实测]**:`unused_mut` 在 **`moon test` / `moon build` 里表现为 `Error [0015]`**(顶格 `Error Warning (...)`,整个检查 fail),不只是 warning。这就是本项目「本地按 `--deny-warn` 验收」的实际效果。

结论(`Table` 的字段要照此设计):`rows` / `gens` / `free` / `order` / `indexes` 若只做**容器内容修改**就不加 `mut`;只有 `len` / `version` 这种会 `self.x = ...` 的才加 `mut`。

### 3.5 模式匹配与守卫 [实测]

```moonbit
///|
pub fn klass(v : Int?) -> String {
  match v {
    Some(x) if x > 10 => "big"        // if 守卫可用
    Some(_) => "small"
    None => "none"
  }
}

// 解构带标签参数的构造器:用 .. 忽略其余字段
match json {
  Number(n, ..) => n.to_int()          // Json::Number(Double, repr~ : String?)
  _ => 0
}
```

`for` 循环遍历容器 [实测]:

```moonbit
for k, v in m { ... }     // Map / SortedMap / Iter2
for x in s { ... }        // Array / SortedSet / Iter
```

### 3.6 可见性 [实测]

| 写法 | 作用域 |
|---|---|
| `priv struct S { .. }` / `fn f()`(默认) | 仅本包(含本包的白盒测试) |
| `pub fn` / `pub struct` | 全模块可见 |
| `pub(all) struct` | 构造器也公开 |
| `pub(open) trait` | 可被外部实现 |

---

## §4 类型与 trait

### 4.1 内建 trait 的**准确形态** [源码:`builtin/pkg.generated.mbti`]

这才是要实现的签名:

```
pub(open) trait Eq {
  fn equal(Self, Self) -> Bool
  fn not_equal(Self, Self) -> Bool = _
}

pub(open) trait Compare : Eq {          // ← 注意:Compare 继承 Eq
  fn compare(Self, Self) -> Int
  fn op_lt(Self, Self) -> Bool = _
  fn op_gt(Self, Self) -> Bool = _
  fn op_le(Self, Self) -> Bool = _
  fn op_ge(Self, Self) -> Bool = _
}

pub(open) trait Hash {
  fn hash_combine(Self, Hasher) -> Unit     // 注意参数是 Hasher,不是 hasher~
  fn hash(Self) -> Int = _
}

#must_implement_one(output, to_string)
pub(open) trait Show {
  fn output(Self, &Logger) -> Unit = _
  fn to_string(Self) -> String = _
}

pub(open) trait @debug.Debug {              // 在 moonbitlang/core/debug 里
  fn to_repr(Self) -> @debug.Repr
}

pub(open) trait ToJson { fn to_json(Self) -> Json }
pub(open) trait Default { fn default() -> Self }

pub(open) trait Logger {
  fn write_string(Self, String) -> Unit = _
  fn write_view(Self, StringView) -> Unit = _
  fn write_char(Self, Char) -> Unit = _
  fn write(Self, &Show) -> Unit = _
  // ...
}
```

**关键点** [源码]:

- `Compare : Eq` —— `Compare` **继承** `Eq`,实现 `Compare` 前必须先有 `Eq`。这就是旧文件 §7 表格里「trait bound 不满足」的一大来源。

- `Hash` 要求实现的是 **`hash_combine(Self, Hasher) -> Unit`**;`hash(Self) -> Int` 有默认实现。所以**手写 `Hash` 时写 `hash_combine`**。

- `Show` 有 `#must_implement_one(output, to_string)`,**两者只实现一个**。

- `Show::output` 第二参数类型是 **`&Logger`**(带 `&`)。

### 4.2 手写 trait 实现 [实测,全部编译运行通过]

```moonbit
pub struct Pt {
  x : Int
  y : Int
}

///|
pub impl Show for Pt with fn output(self : Pt, logger : &Logger) {
  logger.write_string("Pt(")
  logger.write_string(self.x.to_string())
  logger.write_string(", ")
  logger.write_string(self.y.to_string())
  logger.write_string(")")
}

///|
pub impl Eq for Pt with fn equal(self : Pt, other : Pt) -> Bool {
  self.x == other.x && self.y == other.y
}

///|
pub impl Hash for Pt with fn hash_combine(self : Pt, hasher : Hasher) -> Unit {
  hasher.combine_int(self.x)
  hasher.combine_int(self.y)
}

///|
pub impl Compare for Pt with fn compare(self : Pt, other : Pt) -> Int {
  let cx = self.x.compare(other.x)
  if cx != 0 { cx } else { self.y.compare(other.y) }
}

///|
pub impl @debug.Debug for Pt with fn to_repr(self : Pt) -> @debug.Repr {
  @debug.Repr::opaque_("Pt", @debug.Repr::record(Map([
    ("x", @debug.Repr::Repr(self.x)),
    ("y", @debug.Repr::Repr(self.y)),
  ])))
}
```

实测行为(`moon run`):`show=Pt(1, 2) cmp=0 lt=false hash=851499103 mapget=Some(1) setlen=1 dbg=<Pt: { x: 1, y: 2 }>`

#### 4.2.1 `Repr` 的准确 API(旧文件写错了)[源码:`debug/repr.mbt`]

`Repr::map` 的参数是 **`Array[(Repr, Repr)]`**,不是 `Array[(String, Repr)]`。把 `String` 当 key 会报 `Expr Type Mismatch has type : String / wanted : Repr` [实测]。

`pkg.generated.mbti` 只导出了 `Repr::Repr(T)` / `Repr::to_string` / `repr` / `render`,但源码里 `pub fn Repr::*` 的构造器都在:

```
pub fn Repr::integer(x : String) -> Repr
pub fn Repr::double(x : Double) -> Repr
pub fn Repr::float(x : Float) -> Repr
pub fn Repr::bool(x : Bool) -> Repr
pub fn Repr::char(x : Char) -> Repr
pub fn Repr::string(x : String) -> Repr
pub fn Repr::tuple(children : Array[Repr]) -> Repr
pub fn Repr::array(children : Array[Repr]) -> Repr
pub fn Repr::record(fields : Map[String, Repr]) -> Repr   // ← 想用字符串键用这个
pub fn Repr::opaque_(name : String, children : Repr) -> Repr
pub fn Repr::literal(value : String) -> Repr
pub fn Repr::map(contents : Array[(Repr, Repr)]) -> Repr  // ← key 是 Repr 不是 String!
pub fn Repr::omitted() -> Repr
pub fn Repr::unit() -> Repr
pub fn Repr::ctor(name : String, args : Array[(String?, Repr)]) -> Repr
// 另有 pub fn[T : Debug] Repr::Repr(T) -> Self  —— 自动分发到 T 的 Debug
```

实测:`@debug.to_string(@debug.Repr::literal("hi"))` → `hi`;`@debug.to_string(@debug.Repr::opaque_("Pt", @debug.Repr::record(Map([("x", @debug.Repr::Repr(1))]))))` → `<Pt: { x: 1 }>`。

### 4.3 **`derive(...)` 与 `extend` 的配套纪律** [实测 + 文档]

**结论:派生 trait 后要显式 `extend` 把生成的方法挂成常规方法,否则吃 `[0079]` 弃用警告。**

```moonbit
pub struct D1 {
  x : Int
  y : String?
} derive(Eq, Compare, Hash, Debug, Default, ToJson)

///|
pub extend D1 with Eq::{not_equal, equal}

///|
pub extend D1 with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend D1 with Hash::{hash, hash_combine}

///|
pub extend D1 with @debug.Debug::{to_repr}

///|
pub extend D1 with Default::{default}

///|
pub extend D1 with ToJson::{to_json}
```

不写 `extend` 时的原话 [实测]:

```text
Warning [0079] (implicit_impl_as_method): The methods not_equal, equal from `impl Eq for Tally`
are implicit promoted as regular method for `Tally`. This behavior is deprecated and will be
removed in the future. Add a `pub extend Tally with Eq::{not_equal, equal}` declaration or
manually define regular methods for type `Tally` instead. If the promotion is not desirable,
add `#deprecated` on the `extend` declaration.
```

实测确认可派生且编译通过的 trait:

| derive | 生成的 impl | 建议 `extend` 的方法 |
|---|---|---|
| `Eq` | `Eq` | `not_equal, equal` |
| `Compare` | `Compare`(字段需 `Compare`) | `op_lt, op_le, op_ge, compare, op_gt` |
| `Hash` | `Hash` | `hash, hash_combine` |
| `Debug` | `@debug.Debug` | `to_repr` |
| `Default` | `Default` | `default` |
| `ToJson` | `ToJson` | `to_json` |
| `@quickcheck.Arbitrary` | `@quickcheck.Arbitrary` | `arbitrary` |
| `@quickcheck.Shrink` | `@shrink.Shrink` | `shrink` |
| `Show` | ❌ **已废弃**,见下 | — |

实测运行结果(`moon test` 输出):`eq=true cmp=0 lt=false h=-304803271 j={"x":1}` / `d={ x: 0, y: None } e=Case2(label="x")` / `qs=3 shr=3`。

**`derive(Show)` 已废弃** [实测]:

```text
Warning [0027] (deprecated_syntax): `derive(Show)` is deprecated.
Use `derive(Debug)` or manually implement the `Show` trait instead.
```

正确替代:`derive(Debug)` + 手写 `pub impl Show for T with fn output(self, logger) { .. }`(见 §4.2)。

> **`derive(Show)` 仍会写进 `.mbti`**(`} derive(Eq, Show, @debug.Debug)`),所以它「没坏」,但 `--deny-warn` 下会挂。

**`extend` 的细节** [实测]:

- `extend` 声明**不会**出现在 `pkg.generated.mbti` 里(生成文件只列 `impl`),所以加 `extend` **不会**引起 CI 的 `mbti` diff。

- 无 `pub` 前缀的 `extend` 也能消警告,但 `pub extend` 才让外部也能点调用 [文档]。

- 官方文档 [文档] 明确把「用 `extend` 显式声明哪些生成函数属于该类型的方法式 API」写成推荐做法,理由正是「避免依赖已弃用的隐式附加方法行为」。

### 4.4 点调用 vs 限定调用 —— `[0083]` 的**真实含义**(旧文件理解错了)

官方错误码页 E0083 [文档] 原文:

> Warning name: **`type_param_method`**。通过已弃用的**隐式方法解析**,在**类型参数**上调用 trait 方法。当方法来自所写约束的**父 trait**,或者类型参数有**多个可能提供方法的 trait 约束**时,点语法无法明确指出选中的 trait。请改用 `Trait::method(value, ...)`。

也就是说 `[0083]` 不是「多约束点调用一律警告」,而是**无法唯一确定 trait** 时才警告。修法固定:

```moonbit
// ❌ 依赖隐式方法解析
// pub fn[O : Object] position_of(object : O) -> (Int, Int) { object.pos() }

// ✅ 限定到声明该方法的 trait
///|
pub fn[O : Object] position_of(object : O) -> (Int, Int) {
  Position::pos(object)
}
```

本项目风格(`CONTRIBUTING.md` 已规定)照此执行:`Hash::hash(x)`、`Show::to_string(x)`、`Compare::compare(a, b)`。

**另一类同源警告 [实测]**:对**具体类型**(不是类型参数)点调用从 impl 隐式提升的方法,报的是 `Warning [0020] (deprecated): The method 'X' is implicitly promoted from 'impl ...'. This behavior is deprecated, either use 'Trait::method' instead or add a 'extend T with Trait::{method, ..}' declaration.` 实例:`p.compare(p2)`、`e.to_string()`、`r.to_json()`。**两个修法二选一**:写 `Compare::compare(p, p2)` / `Show::to_string(e)`,或者加 `extend`。

---

## §5 容器:Map / SortedMap / SortedSet [实测运行 + 源码]

### 5.1 三个类型的**准确身份**

| 名字 | 真实来源 | 需要 import? |
|---|---|---|
| `Map[K, V]` | **`builtin` 中直接定义的类型**,经 `prelude` 暴露(`pub using @builtin {type Map}`) | **不需要** |
| `@hashmap.HashMap[K, V]` | `moonbitlang/core/hashmap`(与 `Map` 是两个不同名字的类型!) | 需要 `"moonbitlang/core/hashmap"` |
| `@sorted_map.SortedMap[K, V]` | `moonbitlang/core/sorted_map` | **需要** |
| `@sorted_set.SortedSet[V]` | `moonbitlang/core/sorted_set` | **需要** |

> 旧文件多处写 `Map([])`——**这点是对的**,`Map` 确实不需要 import。但 `SortedMap` / `SortedSet` **必须**加 `@sorted_map.` / `@sorted_set.` 前缀 + `moon.pkg` 里 import,否则 `Error [4032] The type SortedMap is undefined.` [实测]

### 5.2 构造:都是 `Type([])` [实测]

```moonbit
let m  : Map[String, Int]                    = Map([])
let sm : @sorted_map.SortedMap[Int, String]  = @sorted_map.SortedMap([])
let ss : @sorted_set.SortedSet[Int]          = @sorted_set.SortedSet([])

// 从数组初始化(键重复的胜出规则未核实)
let sm2 : @sorted_map.SortedMap[Int, String] = @sorted_map.SortedMap([(1, "a"), (2, "b")])
let ss2 : @sorted_set.SortedSet[Int]         = @sorted_set.SortedSet([1, 2, 3])

// Map 还有 capacity 标签参数
let m2 : Map[String, Int] = Map([], capacity=16)
```

> **`Type::new()` 已废弃**。源码标注 [源码]:`HashMap::new` / `SortedMap::new` / `SortedSet::new` 全部带 `#deprecated`。用 `Type([])` 或 `Type::from_iter(..)` / `Type::from_array(..)`。

### 5.3 方法名与索引语法(**全部 [实测] 通过**)

```moonbit
///|
pub fn probe_containers() -> Unit {
  let m : Map[String, Int] = Map([])
  m.set("a", 1)              // 写入
  m["b"] = 2                  // 索引赋值语法,等价于 set
  let v_at  : Int   = m["a"]  // 索引读取,返回 V(缺键 panic,见下)
  let v_at2 : Int   = m.at("b")   // at = 索引读取的具名形式
  let g     : Int?  = m.get("a")  // 安全读取
  let c     : Bool  = m.contains("a")
  let n     : Int   = m.length()   // 不是 .size()
  let az    : Array[(String, Int)] = m.to_array()
  let kc    : Int   = m.keys().count()
  m.remove("a")               // 注意:返回 Unit,不返回旧值!
  for k, v in m { println("\{k}=\{v}") }

  let sm : @sorted_map.SortedMap[Int, String] = @sorted_map.SortedMap([])
  sm.set(2, "b")
  sm[1] = "a"                  // 索引赋值
  let sg  : String?      = sm.get(1)
  let sat : String       = sm[1]
  let srn : Int          = sm.range(0, 3).to_array().length()  // ⚠️ 双闭区间
  for k, v in sm { println("\{k}=\{v}") }

  let ss : @sorted_set.SortedSet[Int] = @sorted_set.SortedSet([])
  ss.add(3); ss.add(1)
  let sc : Bool     = ss.contains(1)
  let sl : Int      = ss.length()
  let sa : Array[Int] = ss.to_array()
  ss.remove(3)
  for x in ss { println("\{x}") }

  // 嵌套:非唯一索引桶 = Map[String, SortedSet[Int]]
  let buckets : Map[String, @sorted_set.SortedSet[Int]] = Map([])
  buckets.set("k", @sorted_set.SortedSet([]))
  match buckets.get("k") {
    Some(s) => s.add(7)       // 取出后改内部,原 Map 生效(引用语义)
    None => ()
  }
}
```

实测输出:`m.len=1 n=2 az=2 kc=2 sg=Some(a) sc=true sl=2 sa=2 v_at=1 v_at2=2 g=Some(1) c=true sat=a srn=2`

#### 5.3.1 `Map::remove` **返回 Unit** [源码]

`pub fn[K : Hash + Eq, V] Map::remove(Self[K, V], K) -> Unit`。想拿旧值必须先 `get` 再 `remove`。

#### 5.3.2 `m[k]` 缺键 = **panic,不可捕获** [实测]

```moonbit
let m : Map[String, Int] = Map([])
m.set("a", 1)
let x = m["zz"]        // ❌ abort:测试直接判失败,`try`/`catch` 接不住
let y = m.get("zz")    // ✅ Some/None
```

实测:`try { let _x = m["nope"] } catch { _ => .. }` **仍然 panic**(`try/catch` 抓的是 `Error` 效果,**抓不到 panic**)。

对照实验:测试名以 `panic` 开头时,测试**因 panic 而通过** [实测 + 文档]——这正是区分 panic 与 `raise Error` 的手段:

```moonbit
test "panic missing index key aborts" {
  let m : Map[String, Int] = Map([])
  m.set("a", 1)
  let _x = m["zz"]      // panics ⟹ 测试通过
}
```

> **对本库的意义(`SPEC.md`「绝不 panic」原则)**:索引查询 API **必须**返回 `Option` / `Result`,不能靠 `m[k]`。

### 5.4 `range` 是**双闭区间** `[lo, hi]` [实测,重要]

```moonbit
let sm : @sorted_map.SortedMap[Int, String] =
  @sorted_map.SortedMap([(1, "a"), (2, "b"), (3, "c"), (4, "d")])
sm.range(1, 3).to_array()   // => [(1,"a"), (2,"b"), (3,"c")]   3 个!
sm.range(1, 4).to_array()   // => 4 个

let ss : @sorted_set.SortedSet[Int] = @sorted_set.SortedSet([1, 2, 3, 4])
ss.range(1, 3).to_array()   // => [1, 2, 3]                        3 个!
```

`SortedMap::range(Self, K, K) -> Iter2[K, V]`,`SortedSet::range(Self, V, V) -> Iter[V]` [源码]。

> **这直接关系到 `SPEC.md` §3.3 的 `range_by` / `range_inclusive_by` 语义**:`SPEC.md` 写的是 `range_by` = `[lo, hi)`、`range_inclusive_by` = `[lo, hi]`,而 core 的 `SortedMap::range` 是 `[lo, hi]`。**本库若直接转发 core 的 range,两个方法会退化成同一个语义**;要实现半开区间,必须自己做 `hi` 的前驱调整,或在文档里改口径。**这是一个需要你拍板的设计问题,我没有替你决定。**

### 5.5 `Iter` / `Iter2` 的真实能力 [源码]

`Iter[X]` 方法很多 [源码]:

```
all any contains count(别名 length) count_if drop drop_while each eachi empty filter
filter_map find_first flat_map flatten fold intersperse iter iter2 join last map mapi
maximum minimum new nth repeat singleton size_hint take take_while tap to_array to_json zip
concat add( `+` ) clamped_view( `_[_:_]` )
```

**构造与 fail-fast 惯用法 [实测]**——本项目 `Table::iter` / `iter_by` 的核心模式:

```moonbit
///|
pub fn[C] Counter::iter(self : Counter) -> Iter[Int] {
  let mut pos = 0
  let version = self.version          // 变更计数器快照
  Iter::new(
    fn() -> Int? {
      if self.version != version {
        abort("Counter: mutated during iteration")   // fail-fast
      }
      if pos < self.items.length() {
        let v = self.items[pos]
        pos = pos + 1
        Some(v)
      } else {
        None
      }
    },
    size_hint=3,          // 具名参数;可省
  )
}
```

`let it : Iter[Int] = Iter::new(fn() -> Int? { None }, size_hint=3)` 实测可编译,`it.count()` 得 `0`。

**`Iter2[X, Y]` 只有这些方法** [源码,实测踩过坑]:

```
pub fn[X, Y] Iter2::concat(Self[X, Y], Self[X, Y]) -> Self[X, Y]
pub fn[X, Y] Iter2::each(Self[X, Y], (X, Y) -> Unit) -> Unit
pub fn[X, Y] Iter2::iter(Self[X, Y]) -> Iter[(X, Y)]
pub fn[X, Y] Iter2::iter2(Self[X, Y]) -> Self[X, Y]
pub fn[X, Y] Iter2::new(() -> (X, Y)?, size_hint? : Int) -> Self[X, Y]
pub fn[X, Y] Iter2::next(Self[X, Y]) -> (X, Y)?
pub fn[X, Y] Iter2::to_array(Self[X, Y]) -> Array[(X, Y)]
```

**没有 `count` / `fold` / `map` / `filter`**。实测报错:`Error [4015] Type Iter2[Int, String] has no method count.` / `. has no method fold.`

正确写法 [实测]:

```moonbit
// 要个数:先 to_array
let n = sm.range(0, 3).to_array().length()
// 要遍历:for k, v in .. 或 .each(..)
let mut acc = ""
sm.range(1, 3).each(fn(_k, v) { acc = acc + v })
// 想要 Iter 的能力:先 .iter() 降级成一元迭代器
let c = sm.iter().count()
```

### 5.6 Map 的其余常用方法 [源码]

```
get_or_default(k, default)   get_or_init(k, () -> V)   update(k, (V?) -> V?)
update_or_default(k, d, (V) -> V)   retain((K, V) -> Bool)   clear()
each / eachi   keys() -> Iter[K]   values() -> Iter[V]   iter() -> Iter[(K,V)]
capacity()   contains_kv(k, v)   get_from_string(StringView) / get_from_bytes(BytesView)
merge / merge_in_place   map((K,V) -> V2)   to_array()   copy()
```

`SortedMap` 独有:`range(lo, hi)`。其余与 `Map` 同形(约束从 `Hash + Eq` 换成 `Compare`)。

`SortedSet` 独有集合运算 [源码]:`union` `intersection` `difference` `symmetric_difference` `subset` `disjoint` `range` `singleton`。

**没有 `insert` 方法** [源码]:一律叫 `set`。`SortedSet` 用 `add`。

---

## §6 错误处理 [实测全部编译运行]

### 6.1 `suberror` 定义与匹配

```moonbit
pub suberror TableError {
  DupIndex(String)
  StaleHandle(Int, Int)
  Invariant(String)
} derive(Eq, @debug.Debug)      // 注意:@debug.Debug,不是裸 Debug

///|
pub impl Show for TableError with fn output(self : TableError, logger : &Logger) {
  match self {
    DupIndex(n) => logger.write_string("DupIndex(" + n + ")")
    StaleHandle(s, g) => logger.write_string("StaleHandle(\{s}, \{g})")
    Invariant(m) => logger.write_string("Invariant(" + m + ")")
  }
}
```

也可以写**无载荷**形式 [文档]:`suberror E2`(单一构造器 `E2`)。`suberror` 值可自动提升为 `Error`,也能模式匹配回来 [文档]。

### 6.2 `raise` 效果标注 —— **不要用 `!`**

```moonbit
///|
pub fn checked_div(a : Int, b : Int) -> Int raise TableError {
  if b == 0 {
    raise TableError::Invariant("division by zero")
  }
  a / b
}

///|
pub fn checked_sqrt(x : Int) -> Int raise {      // 省略错误类型 == raise Error
  if x < 0 { raise TableError::Invariant("negative") }
  x
}
```

[文档] `fn f() -> Unit raise { .. }` 与 `fn f() -> Unit raise Error { .. }` 等价。

**调用带效果函数的硬性规则 [实测]**:

```text
Error [4122] Function with error can only be used inside a function with error types in its
signature. Please fix the return type of this function.
```

两种合法处理:① 调用方也标 `raise`;② 用 `try/catch` 就地消化。**辅助函数里调 `@test.assert_eq` 也必须标 `-> Unit raise`** [实测 + 项目约定]。

### 6.3 `try` / `catch` [实测]

```moonbit
///|
pub fn parse_slot(s : String) -> Result[Int, TableError] {
  try {
    Ok(@string.parse_int(s))
  } catch {
    _ => Err(TableError::Invariant("bad int: " + s))
  }
}

///|
pub fn probe_errors() -> Unit {
  // 具名子错误构造器
  let a = try { checked_div(10, 2) } catch { TableError::Invariant(_) => -1; _ => -2 }
  // 绑定载荷
  let b = try { checked_div(1, 0) } catch { Invariant(m) => 0 - m.length(); _ => -99 }
  // 直接 raise 也能接
  let c = try { raise TableError::DupIndex("xy") } catch { DupIndex(n) => n.length(); _ => -1 }
  // 全捕获,绑成 Error
  let d = try { checked_div(4, 0) } catch {
    e => Show::to_string(e).length()
  }
  println("a=\{a} b=\{b} c=\{c} d=\{d}")
}
```

补充 [实测]:

- **`catch` 只接 `Error` 效果,接不住 panic**(§5.3.2)。

- `try { f() } catch { _ => default }` 可以做「缺省值」包装,这是本项目里处理 core 抛错 API 的推荐形态。

### 6.4 `Result` / `Option` [源码]

```
Result::map / map_err / bind / flatten / to_option
Result::unwrap / unwrap_err / unwrap_or / unwrap_or_default / unwrap_or_else / unwrap_or_error
Result::equal / compare / hash / to_json
Option::map / map_or / map_or_else / bind / filter / unwrap / unwrap_or / unwrap_or_default
Option::unwrap_or_else / unwrap_or_error / to_json / compare / equal / hash
```

**废弃项 [源码]** `Option::is_some` / `is_none` / `is_empty` / `flatten` / `to_string` 标了 `#deprecated`。判空请直接 `match`。

`Result::unwrap_or_default` 实测可用:`Err(TableError::Invariant("z")).unwrap_or_default()` 得 `0`。

---

## §7 测试

### 7.1 `test` 块 [实测 + 文档]

```moonbit
test "descriptive english name" {
  let t : @aurasuisui/multiindex.Table[String, (String, String)] =
    @aurasuisui/multiindex.Table::new()
  t.register_unique("name", fn(p) { p.0 })
  debug_inspect(t.len(), content="0")
}
```

[文档] `test` 块本质是 `() -> Unit raise Error` 的函数;名字可选。

**断言 panic 的开关是测试名的 `panic ` 前缀——不是 `try/catch`,也不是属性。** [实测,2026-10-20 三组对照]

| 测试名 | 正文 | 结果 |
|---|---|---|
| `test "panic …"` | 真的 `abort` | **passed** |
| `test "panic …"` | 正常返回、不 panic | **failed: `panic is expected`** |
| `test "普通名字 …"` | 真的 `abort` | **failed: `Error`**,栈指向 `abort` |

两条**走不通**的路(别浪费时间,也别据此下"不可测"的结论):

- `try { abort("x") } catch { }` → 警告 `[0023] unused_try: The body of this try expression never raises any error`
  —— `abort` 抛的是 **panic**,不是 `Error`,`catch` 拿不到。
- `test "x" ( #panic ) { … }` → `[4132] Invalid test parameter` + `[3002] Parse error`;
  `#skip` 同样报错。**没有 `#panic` / `#should_panic` 属性。**

> ⚠️ **`panic ` 测试是弱断言**:它只证明"这个测试里发生过 panic",不证明是**哪一个** panic。
> 所以正文必须让目标守卫成为**唯一可能 panic 的地方**:先逐条断言前置状态(fixture 值、
> `verify_invariants`、索引存在),**最后一步**才是那个触发调用。框架自带负向性质——守卫一旦被
> 删掉或放宽,测试会以 `panic is expected` 失败。

### 7.2 断言 API —— 准确的包名 [源码:`test/pkg.generated.mbti`]

`moonbitlang/core/test` **实际导出的**只有这些:

```
#callsite(autofill(loc))
pub fn[T : Eq + @debug.Debug] assert_eq(T, T, msg? : String, loc~ : SourceLoc) -> Unit raise
pub fn[T : Eq + @debug.Debug] assert_not_eq(T, T, msg? : String, loc~ : SourceLoc) -> Unit raise
pub fn[T : @debug.Debug] assert_not_same_object(T, T, loc~ : SourceLoc) -> Unit raise
pub fn[T, E : Error] assert_raise(() -> T raise E, loc~ : SourceLoc) -> Unit raise
pub fn[T : @debug.Debug] assert_same_object(T, T, loc~ : SourceLoc) -> Unit raise
pub fn[T, E : Error] expect_error(() -> T raise E, loc~ : SourceLoc) -> E raise
pub fn[T] fail(StringView, loc~ : SourceLoc) -> T raise
// 以及 Test 类型 (快照用):Test::Test / Test::name / Test::snapshot / Test::write / Test::writeln
```

**关键纠正** [源码 + 实测]:

| 想用的 | 真实情况 |
|---|---|
| `@test.assert_eq(a, b)` | ✅ 存在。要求 `Eq + @debug.Debug` |
| `@test.assert_not_eq`, `@test.fail`, `@test.assert_raise`, `@test.expect_error` | ✅ 存在 |
| `@test.assert_true(cond)` | ❌ **`test` 包里没有 `assert_true`**。实测报 `Value assert_true not found in package 'test'` |
| 无前缀 `assert_true(cond)` | ✅ 来自 **prelude**,无需 import |
| 无前缀 `assert_eq` / `assert_false` / `fail` | ✅ 同样来自 prelude |

prelude 侧签名 [源码 `prelude/pkg.generated.mbti`]:

```
pub fn assert_true(Bool, msg? : StringView, loc~ : SourceLoc) -> Unit raise
pub fn assert_false(Bool, msg? : StringView, loc~ : SourceLoc) -> Unit raise
pub fn[T : @builtin.Eq + @debug.Debug] assert_eq(T, T, msg? : String, loc~ : SourceLoc) -> Unit raise
pub fn[T : @builtin.Eq + @debug.Debug] assert_not_eq(T, T, msg? : String, loc~ : SourceLoc) -> Unit raise
pub fn[T] fail(StringView, loc~ : SourceLoc) -> T raise @builtin.Failure
```

### 7.3 快照测试 [实测 + 文档]

三种快照:

```moonbit
// ① Debug 快照 —— 最常用
debug_inspect(value, content="expected")
debug_inspect(value)              // content 可省,`moon test -u` 会自动插入

// ② JSON 快照 —— 长结构更可读
json_inspect(value, content=(#|
  #|{
  #|  "k": 1
  #|}
  #|))

// ③ 任意内容快照 —— 测试块接收 @test.Test
test "record anything" (t : @test.Test) {
  t.write("Hello, world!")
  t.writeln(" And hello, MoonBit!")
  t.snapshot(filename="record_anything.txt")   // 写到本包 __snapshot__/ 下;总会 raise
}
```

**实测踩坑**:`debug_inspect` 走的是 **`Debug`**,**字符串会带引号**。

```moonbit
debug_inspect(@layout.VERSION, content="0.1.0")     // ❌
// Diff: (- expected, + actual)
//   -0.1.0
//   +"0.1.0"
debug_inspect(@layout.VERSION, content="\"0.1.0\"")  // ✅
```

`moon test -u` 修好后会把单值快照重写成多行形式 [实测]:

```moonbit
debug_inspect(@layout.VERSION, content=(
  #|"0.1.0"
))
```

**用法纪律**(项目已有约定,实测支持):

- 循环里、变值上**不要**用 `debug_inspect`,用 `@test.assert_eq`。(实测:两个同名 `debug_inspect` 快照会让 `-u` 反复重写,`-l/--limit` 默认 256 轮就是防这个死循环。)

- 调 `@test.assert_eq` 的辅助函数必须标 `-> Unit raise`。

### 7.4 黑盒 vs 白盒测试 [实测 + 文档]

| 文件 | 能看见什么 | 依赖来自 |
|---|---|---|
| `*_test.mbt` | **只**能访问包的 `pub` 成员;包本身被隐式导入 | `import` + `import { .. } for "test"` |
| `*_wbtest.mbt` | **能**访问 `priv` 类型/字段/函数 | `import` + `import { .. } for "wbtest"` |
| 源码文件内的内联 `test` 块 | 白盒(在本包内) | — |

实测对比:

```moonbit
// src/lib_wbtest.mbt —— ✅ 能读私有字段
test "whitebox reads private field" {
  let t = Tally::new("w")
  t.add(2)
  @test.assert_eq(t.n, 2)          // n 是 priv 字段,这里可见
  @test.assert_eq(t.tag, "w")
}

// src/lib_test.mbt —— ✅ 只能走 @<别名>.,且不能碰 priv
test "blackbox via package alias" {
  let t = @layout.Tally::new("x")
  t.add(3)
  @test.assert_eq(t.get(), 3)
}
```

**别名规则 [实测]**:黑盒测试里用 `@<包名末段>.` 或完整路径。`moon.mod` 的 `name = "probe/layout"` 对应 `@layout`;本项目是 `aurasuisui/multiindex` → `@multiindex`,项目约定同时接受完整写法 `@aurasuisui/multiindex.`。

**白盒测试不能写 `@layout.X`** [实测]:`Error [4020] Package "layout" not found in the loaded packages.` —— 白盒直接写裸名 `Tally::new(..)`。

**其他实测细节**:

- 在 `pkgtype(kind: "executable")` 的包目录里放 `_test.mbt` 会报:`Warning: Main package 'probe/x' uses blackbox-only test inputs ('_test.mbt' files) in package directory ... Main packages will stop generating blackbox tests in a future release.` → **测试文件放库包**(`source` 覆盖到的目录)。

- `[0001] unused_value: Unused function ...` / `[0009] struct_never_constructed` / `[0006] unused_constructor` 很常见;开 `--deny-warn` 前记得清理。

### 7.5 QuickCheck [源码 + 实测 + 文档]

```moonbit
test "qc samples" {
  let xs : Array[Int] = @quickcheck.samples(10)   // 生成 10 个随机值
  @test.assert_eq(xs.length(), 10)
  let one : Int = @quickcheck.gen()               // 生成 1 个
  ignore(one)
  // check:属性为 (A) -> Bool raise?;A 需 Arbitrary + Shrink + Debug
  @quickcheck.check(fn(x : Int) -> Bool { x + 0 == x })
  // report:不 raise,返回可 inspect 的报告
  @quickcheck.report(fn(x : Int) -> Bool { x * 1 == x }) |> ignore
}

test "qc custom generator" {
  let g : @quickcheck.Generator[Int] = @quickcheck.int_range(0, 5)
  let s : Int = g.sample()
  @test.assert_true(s >= 0 && s < 5)
  let arr : Array[Int] = g.samples(count=4)
  @test.assert_eq(arr.length(), 4)
}
```

**自定义类型**:实现 `Arbitrary` + `Shrink`。两者都从 `quickcheck` 门面拿(`@quickcheck.Arbitrary` / `@quickcheck.Shrink`),无需单独 import `quickcheck/shrink` [文档]。

```moonbit
///|
pub impl @quickcheck.Arbitrary for Tally with fn arbitrary(size, r0) {
  let r1 = r0.split()                       // 需要独立随机流时先 split
  let n : Int = @quickcheck.Arbitrary::arbitrary(size, r1)
  { n, tag: "g" }
}

///|
pub impl @quickcheck.Shrink for Tally with fn shrink(self) {
  @quickcheck.Shrink::shrink(self.n).map(n => { n, tag: self.tag })
}
```

实测:`@quickcheck.samples(3)` 对自定义类型可用,`Shrink::shrink({ n: 5 }).to_array()` 得 3 个候选。

**也可用 derive** [文档 + 实测]:`derive(Debug, @quickcheck.Arbitrary, @quickcheck.Shrink)` 后配 `pub extend Q2 with @debug.Debug::{to_repr}` 等。

`check` 的具名参数 [源码]:`filter?` `observe?` `counterexample_context?` `count?` `max_size?` `max_shrinks?` `discard_ratio?` `seed?`。`samples(n)` / `gen(size?, state?)` / `Generator::sample(size?, seed?)` / `Generator::samples(count?, size?, seed?)`。

> ⚠️ **`Iter::collect()` 需要元素 `Show`** [实测]:`Error [4018] Type Q1 does not implement trait Show`。想收集迭代器结果用 **`.to_array()`**,别用 `.collect()`。

### 7.6 `debug_inspect` 与 `@debug`

[源码] `@debug` 包导出:`debug_inspect(&Debug, content?, ..)`(**注意第一参数是 `&Debug` 引用**)、`debug(T)`、`to_string(T)`(别名 `repr`)、`render(Repr, max_depth?)`、`Repr::Repr(T)`。废弃:`dump`、`inspect`(别名到 `debug_inspect`)。

---

## §8 常用核心包

### 8.1 `@json` [源码 + 实测]

```
pub enum Json {
  Null
  True
  False
  Number(Double, repr~ : String?)
  String(String)
  Array(Array[Json])
  Object(Map[String, Json])
}

pub fn[T : ToJson] to_json(T) -> Json
pub fn[T : FromJson] from_json(Json, path? : JsonPath) -> T raise JsonDecodeError
pub fn parse(StringView, max_nesting_depth? : Int) -> Json raise ParseError
pub fn valid(StringView) -> Bool          // 不抛,返回 Bool
pub fn json_inspect(&ToJson, content? : Json, ..) -> Unit raise InspectError

Json::string / boolean / number / null / object / array / empty_object
Json::stringify(escape_slash?, indent?, replacer?) / transform

pub(open) trait FromJson { fn from_json(Json, JsonPath) -> Self raise JsonDecodeError }
```

**实测警告**:`Json::as_array` / `as_bool` / `as_number` / `as_object` / `as_string` / `as_null` / `item` / `value` **全部标了 `#deprecated`** [源码]——旧文件没提。请改用**模式匹配**:

```moonbit
match o {
  Object(mm) => println(@debug.to_string(mm.get("k")))
  _ => println("not obj")
}
match parsed {
  Array(a) => println(a.length())
  _ => ()
}
```

**手写 JSON 往返的完整可跑样例** [实测]:

```moonbit
pub struct Row {
  id : Int
  label : String
  score : Double
} derive(Eq, @debug.Debug)

///|
pub impl ToJson for Row with fn to_json(self : Row) -> Json {
  Json::object(Map([
    ("id", Json::number(self.id.to_double())),
    ("label", Json::string(self.label)),
    ("score", Json::number(self.score)),
  ]))
}

///|
pub impl @json.FromJson for Row with fn from_json(json : Json, path : @json.JsonPath) -> Row raise @json.JsonDecodeError {
  let obj = match json {
    Object(o) => o
    _ => raise @json.JsonDecodeError((path, "expected object"))     // 注意是二元组 (path, msg)
  }
  let id = match obj.get("id") {
    Some(Number(n, ..)) => n.to_int()
    _ => raise @json.JsonDecodeError((path.add_key("id"), "expected number"))
  }
  let label = match obj.get("label") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path.add_key("label"), "expected string"))
  }
  let score = match obj.get("score") {
    Some(Number(n, ..)) => n
    _ => raise @json.JsonDecodeError((path.add_key("score"), "expected number"))
  }
  { id, label, score }
}

///|
pub fn roundtrip(r : Row) -> Row raise {
  let s = ToJson::to_json(r).stringify()
  let back : Json = @json.parse(s)
  @json.from_json(back)
}
```

实测输出:

```text
{"id":1,"label":"a","score":1.5}
{
  "id": 1,
  "label": "a",
  "score": 1.5
}
valid=true/false back={ id: 1, label: "a", score: 1.5 } eq=true
obj={"k":"v"} arr=[1,true,null]
dec=42 dec2=["x"]
```

**错误类型** [源码]:`suberror JsonDecodeError { JsonDecodeError((JsonPath, String)) }`、`suberror ParseError { InvalidChar(Position, Char) / InvalidEof / InvalidNumber(Position, String) / InvalidIdentEscape(Position) / DepthLimitExceeded }`。

**`stringify` 的具名参数** [源码]:`escape_slash? : Bool`,`indent? : Int`,`replacer? : Replacer`(`Replacer::exclude` / `Replacer::keep`)。

### 8.2 `@string` [源码]

```
parse_int(StringView, base? : Int) -> Int raise      parse_double / parse_bool / parse_int64 / parse_uint / parse_uint64
Regex::Regex(StringView) -> Self raise               Regex::find / capture / split / replace_by / execute
String::split(String, StringView) -> Iter[StringView]      rev_split_once / split_once / split_at
String::trim(chars? : StringView) / trim_start / trim_end  -> StringView
String::strip_prefix / strip_suffix / has_prefix / has_suffix
String::replace(old~, new~) / replace_all(old~, new~)
String::to_lower / to_upper / repeat / pad_start / pad_end / rev
String::find / rev_find / contains / contains_char / is_empty / is_blank
String::char_length / length / get_char / to_array / from_array / view
String::to_string_view / code_units / offset_of_nth_char
pub(open) trait FromStr { fn from_str(StringView) -> Self raise }
```

废弃 [源码]:`String::substring`、`trim_space`、`to_bytes`、`String::from_iter`、`String::exact_view`、`Option::to_string` 等。

### 8.3 `@array` / 内建 Array [源码]

`moonbitlang/core/array` 几乎**只剩一个函数** [源码]:

```
pub fn[A, B, C] zip_with(Array[A], Array[B], (A, B) -> C raise?) -> Array[C] raise?
#deprecated pub using @builtin {type ArrayView as View}
```

`Array` 的方法**都在 `builtin` / prelude**,常用 [源码]:

```
length()  push(x)  pop()?  last()?  get(i)?  at(i)  set(i, v)  [i]  [i] = v
map / mapi / filter / filter_map / fold(init~, ..) / foldi / rev_fold / each / eachi / rev_each
contains / search / find_first / all / any / is_empty / to_array / rev / sort / sort_by / sort_by_key
stable_sort / binary_search / chunks / windows / chunk_by / starts_with / ends_with / join(sep)
flatten / flat_map / take / drop / take_while / drop_while / zip / zip_with / intersperse / dedup
make(len, v) / makei(len, f) / from_iter / from_array / to_json / hash / equal / compare
```

`Array::sort()` 要求 `T : Compare`;`Array::sort_by((T,T) -> Int)`;`sort_by_key((T) -> K)` 要求 `K : Compare`。

### 8.4 `@bench` [源码 + 文档]

```moonbit
///|
fn main {
  let b = @bench.Bench()                  // 注意:@bench.Bench(),`Bench::new` 已废弃
  b.bench(name="tally_add", fn() {
    let t = Tally::new("b")
    for i = 0; i < 100; i = i + 1 {
      t.add(i)
    }
    b.keep(t)                             // 防优化删除
  })
  println(b.dump_summaries())

  let s = @bench.single_bench(name="single", fn() { ignore(VERSION) })   // 单次基准
}
```

API [源码]:`Bench::Bench()`、`Bench::bench(name?, () -> Unit, count?)`、`Bench::dump_summaries() -> String`、`Bench::keep(Any)`、`single_bench(name?, () -> Unit, count?) -> Summary`、`monotonic_clock_start() -> Timestamp` / `monotonic_clock_end(Timestamp) -> Double`。

⚠️ **`@bench` 与 `moon bench` 是两回事** [实测]:`moon bench` 是 CLI 子命令;`@bench` 是可以在**任何** `fn main` 或 `test` 里手写的库。本项目的 `bench/main.mbt` 属于后者。

### 8.5 `@debug`

见 §7.6。要点:`debug_inspect` 第一参数是 `&Debug`;**打印请用 `Debug`,不要用 `Show`**——`println` 带 `Show` 值会报 [实测]:`Warning [0020] (deprecated): Use Debug instead of Show for debugging purposes.`

---

## §9 本项目(`Table[K, V]`)相关的落地建议

这一节把上面的结论翻译成本库的具体写法,**都不是新事实,只是应用**。

### 9.1 类型定义形态

```moonbit
// RowId:src/lib.mbt 里是 derive(Eq, Hash, Debug) —— 可直接用,但记得配 extend
pub struct RowId {
  slot : Int
  gen : Int
} derive(Eq, Hash, Debug)

///|
pub extend RowId with Eq::{not_equal, equal}

///|
pub extend RowId with Hash::{hash, hash_combine}

///|
pub extend RowId with @debug.Debug::{to_repr}

// 已有手写 Show(src/lib.mbt:39) —— 保留,不要改回 derive(Show)

// Conflict[K]:同理
pub enum Conflict[K] {
  UniqueViolation(String, K, RowId)
} derive(Debug, Eq)
// ⚠️ derive(Debug) 需要 K : Debug;若要 --deny-warn 干净,补 extend 或改成手写 impl
```

### 9.2 `Table` 的字段与 `mut`

按 §3.4 的实测规则:

```moonbit
pub struct Table[K, V] {
  rows : Array[V?]                       // 无 mut(只做元素级修改)
  gens : Array[Int]                      // 无 mut
  free : Array[Int]                      // 无 mut
  order : Array[Int]                     // 无 mut
  indexes : Map[String, Index[K, V]]     // 无 mut
  mut len : Int                          // 要 mut(self.len = self.len + 1)
  mut version : Int                      // 要 mut
}
```

> **但请以实际编译结果为准**:如果某处写了 `self.free = ..`(整体替换而非 `self.free.push(..)`),那个字段就**必须**加 `mut`。`unused_mut` 会精确地告诉你哪个字段不需要,反过来「need mut」也会告诉你哪个需要。

### 9.3 索引注册签名

`project` 是闭包字段,注册方法必须是**方法级泛型 + 方法级约束**、不能是结构体级:

```moonbit
pub struct Index[K, V] {
  name : String
  project : (V) -> K
  // ... 四象限的具体桶
}

///|
pub fn[K : Hash + Eq, V] Table::register_unique(
  self : Table[K, V],
  name : String,
  project : (V) -> K,
) -> Unit raise {
  // 重名检查 → raise;sorted 变体额外需要 K : Compare
}
```

> `SortedIndex` 那一路是 `K : Compare`。**注意 `Compare : Eq`**(§4.1),所以写了 `Compare` 就自动有 `Eq`,但**不会**自动有 `Hash`。`Table` 的四象限需要不同的约束集合,正对应 `SPEC.md` §3.1 的四个注册方法。

### 9.4 公开自检 `verify_invariants`

`Map[String, Index[K, V]]` 上的遍历 [实测可用]:

```moonbit
for name, idx in self.indexes {
  // name : String, idx : Index[K, V]
}
// 或
self.indexes.each(fn(name, idx) { .. })
self.indexes.keys().to_array()      // index_names()
```

### 9.5 `moon info` 会写出什么

实测一个最小库包的 `pkg.generated.mbti`:

```
// Generated using `moon info`, DON'T EDIT IT
package "probe/layout"

import {
  "moonbitlang/core/debug",
  "moonbitlang/core/quickcheck",
  "moonbitlang/core/quickcheck/shrink",
  "moonbitlang/core/quickcheck/splitmix",
}

// Values
pub const VERSION : String = "0.1.0"

// Types and methods
pub struct Tally {
  mut n : Int
  tag : String
} derive(Eq, Hash, @debug.Debug)
pub fn Tally::add(Self, Int) -> Unit
pub fn Tally::get(Self) -> Int
pub fn Tally::new(String) -> Self
pub impl @quickcheck.Arbitrary for Tally
pub impl @shrink.Shrink for Tally
```

观察到的规律(对本项目 CI 很重要):

- **`extend` 声明不出现在 `.mbti` 里** ⟹ 加 `extend` 不会造成 `moon info && git diff --exit-code` 失败。

- `impl` 会出现(`pub impl @quickcheck.Arbitrary for Tally`),`derive(...)` 会出现在类型行末。

- `mut` 字段原样写成 `mut n : Int`。方法的 `Self` 会替换掉具体类型名。

---

## §10 常见编译错误 / 警告对照表(**全部实测**)

| 代码 | 名字 | 触发条件 | 修法 |
|---|---|---|---|
| `[3002]` | parse error | `struct S[K : Hash + Eq, V]` | 约束移到方法上 |
| `[4064]` | invalid escape | 字符串里写 `\(x)` | 写 `\{x}` |
| `[4015]` | no method | 如 `Iter2::count` / `Iter2::fold` | 先 `.to_array()` / `.iter()` |
| `[4032]` | undefined type | 用了 `SortedMap` 但没 import / 没加 `@sorted_map.` | 加 import + 前缀 |
| `[4122]` | error effect | 在无 `raise` 签名的函数里调带错函数 / `@json.parse` | 加 `raise`,或 `try/catch` 包起来 |
| `[4018]` | trait not impl | `Type X does not implement trait Show`(常见于 `.collect()` / 打印) | 实现该 trait,或改用 `.to_array()` |
| `[0015]` | `unused_mut` | 标了 `mut` 的字段从不被赋值 | 删 `mut`(注意:测试构建里它是 **Error**) |
| `[0053]` | `unused_trait_bound` | 泛型约束写了但没用 | 删掉多余约束 |
| `[0027]` | `deprecated_syntax` | `derive(Show)` | `derive(Debug)` + 手写 `impl Show` |
| `[0079]` | `implicit_impl_as_method` | `derive(..)`/`impl ..` 后点调用生成的方法 | 加 `pub extend T with Trait::{..}` |
| `[0020]` | deprecated | 对具体类型点调用 impl 提升的方法;`println` 带 `Show` 值 | `Trait::method(..)`,或 `extend`;打印改用 `Debug` |
| `[0083]` | `type_param_method` | 类型参数上点调用,无法唯一确定 trait(父 trait / 多约束) | `Trait::method(value, ..)` |
| `[0071]` | `core_package_not_imported` | 用了 `@json` / `@test` 等但 `moon.pkg` 没 import | 加进 `moon.pkg` 的 `import` |
| `[0029]` | `unused_package` | `moon.pkg` import 了但没使用 | 删掉,或移到 `for "test"` 段 |
| `[0002]` | `unused_value` | 变量/let 绑定没使用 | 用起来 / 加 `ignore(..)` / `_` 前缀 |
| `[0009]` `[0006]` `[0001]` | never constructed / unused ctor / unused fn | 骨架代码未接完 | 正常,收口时清理 |
| `[4020]` | package not found | 白盒测试里写 `@pkg.X` | 白盒直接写裸名 |
| `[4067]` | missing main | `pkgtype(kind: "executable")` 但无 `fn main` | 加 `fn main`,或去掉 `pkgtype` |
| `[0013]` | unresolved type variable | `SortedMap([])` 在无类型标注时元素类型未定 | 补类型标注 `SortedMap[Int, String]([])` |
| `[0022]` | `ambiguous_block` | 单字段结构体字面量简写 `{ code }` | 写 `{ code, }` |

---

## §11 怎么复现本文的 [实测] 结论

临时探针工程的结构(用完删掉):

```
mb-probe/
├── moon.mod              name = "probe/x" / version = "0.0.1" / source = "."
├── moon.pkg              import { .. } / import { .. } for "test" / for "wbtest"
├── main.mbt              fn main { .. }
├── a.mbt                 被验证的语法/API
├── a_test.mbt            黑盒测试(用 @<别名>. 前缀)
└── a_wbtest.mbt          白盒测试(直读 priv)
```

三步走:

```bash
moon check      # 抓语法/类型错;⚠️ 查不出「方法不存在」
moon run .      # 跑出真实值 —— 必须做,才能验证行为
moon test       # 验证测试机制本身
```

**教训**:`moon check` 通过 ≠ 代码正确。`Iter2::count` 这种「方法不存在」是 `moon build`/`run` 阶段才报的 `[4015]`。本文凡标 [实测] 的结论,都跑了 `moon run` 或 `moon test` 并看到了真实输出。

---

## §12 明确**未核实**的条目(不要当事实用)

| 条目 | 状态 |
|---|---|
| 重复键时 `Map::from_iter` / `SortedMap::from_array` 的胜出规则 | **未核实**(源码未逐行读) |
| `moon run --target` 各后端的具体差异 | **未核实**(help 里有 `wasm`/`wasm-gc`/`js`/`native`/`llvm`/`all`) |
| `moon publish` 的完整流程与账号要求 | **未核实**(以 `docs/RELEASE_CHECKLIST.md` 为准) |
| `#skip(...)` / `#coverage.skip` / `#cfg` 等属性的准确语义 | **[文档]** 有,未在本机复跑 |
| `@test.T::snapshot` 产出的 `__snapshot__/` 目录细节 | **[文档]**,未复跑 |
| 跨模块 path dependency(除 `moon.work` 之外的写法) | **未核实**;`moon work use` 路线 [实测] 可行 |
| `moon.mod` 的 `warnings` 字段(核心库在用,如 `warnings = "+test_unqualified_package+..."`) | **未核实**语义,未在本项目试用 |
| `Map::new()` 是否也被标了废弃 | **未核实**:`builtin` 的 `Map::new` 在 `.mbti` 里**没有** `#deprecated`,而 `HashMap::new` / `SortedMap::new` / `SortedSet::new` 都有 |
| core 里其他未提到的 trait 的完整列表 | 只核了本文提到的那些 |

---

## 附录 A 与旧版 `docs/MOONBIT_REF.md` 的**错误对照**

见本次变更摘要(已直接回复给 reviewer)。摘要里逐条列出:原文怎么写 → 正确是什么 → 依据。此处不重复,避免两处漂移。
