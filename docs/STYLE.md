# MoonBit 官方代码约定与风格

> **审核记录(2026-10-14)**:本文由独立调研会话撰写,经审核会话**独立复跑核实**后才并入仓库。
>
> **我独立跑过的核实项**:
> - `[0079]` 实测 **14–15 条**(13 条在 `src/lib.mbt` + 1 条在 `src/table_wbtest.mbt`)✔
> - **`moon check --deny-warn` 在当前代码上直接失败** ✔ —— 所以 §H.1 / §H.2 是"把 `--deny-warn` 加进 CI"的**前置条件**,不是可选项
> - **`moon bundle --all` 在本项目确实 panic**(exit=101,`declared execution output has multiple producers`)✔ —— §H.7 的**反向建议成立**,别抄
> - `moon check --target all` / `moon test --target all`:**wasm / wasm-gc / js / native 四个后端全部 59/59、0 error** ✔
>   —— 原文 §I-3 的存疑项**已由本次复跑关闭**;这也佐证"MoonBit 的 `Int` 是 32 位"在所有 target 上成立(见 [`SPEC.md` §2.1.1](SPEC.md))
>
> **审核所做的修改**:
> - **修正 25 处代码块内的中文弯引号**(`“ ”` → `" "`)。原文 §H.1 声称"可直接粘贴",
>   但 `#deprecated(“...”)` 用的是弯引号 —— **粘进编辑器就是语法错误**。
> - 其余内容一律未动。
>
> **仍未核实**(照原文保留):HawkEye 对我们两行 SPDX 头的实际判定 —— 本机未装 HawkEye,
> 原文结论是**逐行比对推出的强推断**,真要用它当 CI 门禁前必须实跑一次。


> 调研日期:2026-10-14
> 工具链:`moon 0.1.20260920 (914d7da)` / `moonc v0.10.14+7d59c7ec9`
> 第一手来源:本机 `~\.moon\lib\core` 完整检出(与工具链同版本)+ 官方文档站 + 官方 CI 配置
> 本文档**只新增**,不改动 `docs/MOONBIT_REF.md` 或任何既有文件。

## 0. 证据层级与可信度标记

全文每条结论都带标记,含义如下:

| 标记 | 含义 | 例子 |
|---|---|---|
| 【官方明文】 | 官方文档 / 官方仓库内文档的原文 | `core/AGENTS.md`、`core/CONTRIBUTING.md`、`docs.moonbitlang.cn` |
| 【官方 CI】 | 从官方 CI 配置读出的**实际执行**事实 | `.github/workflows/*.yml` |
| 【实证】 | 对官方代码抽样统计得出,官方未明文规定 | `const` 命名统计 |
| 【社区】 | 非 moonbitlang 组织的代码/说法 | 社区仓库 |
| 【未核实】 | 未找到一手证据,存疑 | —— |

**来源层级**(重要:不要混用):
- **官方** = `moonbitlang` 组织:`moonbitlang/core`(标准库)、`moonbitlang/x`、`moonbitlang/async`、`moonbitlang/moon`(构建工具本体)。
- **社区** = `moonbit-community/*` 及其他个人仓库。**本文不把社区惯例当官方约定**。

本地核心检出路径速记(下文用 `<CORE>` 指代):
```
%USERPROFILE%\.moon\lib\core\            ← 标准库检出
%USERPROFILE%\.moon\lib\core\AGENTS.md   ← 官方 agent 重构/约定指引(109 行)
%USERPROFILE%\.moon\lib\core\CONTRIBUTING.md
%USERPROFILE%\.moon\lib\core\licenserc.toml
%USERPROFILE%\.moon\lib\core\.github\workflows\
```

---

## §A 命名

### A.1 函数 / 方法 / 变量 → `snake_case`【官方明文】

位置:`<CORE>/CONTRIBUTING.md:91-96`。全文的命名约定**只有三行**,原文:

```markdown
# Naming conventions

- function names, `snake_case` is preferred.
- type parameters, one character starting from `A` is preferred, e.g, `fn[A,B] Array::map(self : Array[A], f : (A) -> (B)) -> Array[B]`, for some established
  conventions, `Map[K,V]` it is also accepted.
- type names, `CamelCase` is preferred.
```

同文件 `:38` 补充(措辞更强):

```markdown
- All function names, method names, and variables should use `snake_case`, while all type names should use `PascalCase`.
```

**注意措辞差异**:所有权层级用 `should`(硬要求),`Naming conventions` 一节用 `is preferred`(倾向)。两条都不涉及常量。

### A.2 类型 → `PascalCase`【官方明文】

同上两条。

### A.3 常量 → `UPPER_SNAKE_CASE`【实证】

官方 `CONTRIBUTING.md` **完全没有提常量命名**(整份 96 行只有 A.1 那一处 Naming conventions)。因此只能实证。

对 `<CORE>` 全树 `*.mbt` 扫 `const` 声明,共 **196** 条,分类:

| 形态 | 条数 | 占比 |
|---|---|---|
| `UPPER_SNAKE_CASE`(`^[A-Z][A-Z0-9_]*$`) | **170** | 86.7% |
| `lower_snake_case` | **0** | 0% |
| 其它(26 条,全部来自同一处数学常量表) | 26 | 13.3% |

那 26 条例外**只有一个来源**:`<CORE>/builtin/double_pow_nonjs.mbt:34,37,40,78,81,84,88,92,95,98,…`,形如 `POW_two53` / `POW_lg2_h` / `POW_cp_l` —— 是 v8/fdlibm 移植代码里的多项式系数表,`POW_` 前缀 + 原论文下标。**属于移植代码的历史包袱,不是可效仿的风格**。

8 个可核实的正例:

| # | 声明 | 位置 |
|---|---|---|
| 1 | `const RADIX : UInt64 = 1UL << RADIX_BIT_LEN` | `<CORE>/bigint/bigint_default.mbt:89` |
| 2 | `const RADIX_MASK : UInt64 = RADIX - 1` | `<CORE>/bigint/bigint_default.mbt:93` |
| 3 | `const DECIMAL_CHUNK : UInt64 = 10_000_000_000_000_000_000UL` | `<CORE>/bigint/bigint_wide.mbt:548` |
| 4 | `const DIV_RECURSIVE_THRESHOLD` | `<CORE>/bigint/division_wide.mbt:25` |
| 5 | `const KARATSUBA_THRESHOLD` | `<CORE>/bigint/bigint_wide.mbt:42` |
| 6 | `const DEFAULT_MAX_RELATIVE_ERROR : Double = 0.000000000001` | `<CORE>/debug/delta.mbt:26` |
| 7 | ``const ANSI_RESET : String = \u001b[0m`` | `<CORE>/debug/delta.mbt:225` |
| 8 | `const HEX_DIGITS` / `const HEX_UPPER` | `<CORE>/encoding/hex/encode.mbt:16`、`<CORE>/encoding/percent/encode.mbt:16` |

测试文件里的常量同样遵守:`const BOM : Char = '\u{FEFF}'`(`<CORE>/buffer/buffer_test.mbt:397`)、`const QC_COUNT : UInt = 200`(`<CORE>/diff/quickcheck_test.mbt:19`)。

**结论**:常量用 `UPPER_SNAKE_CASE` 是 core 的一致实践(86.7% 严格符合,0% 反例用小写),可以安全地当作事实约定。【实证】

### A.4 `pub const` 与私有 `const`:**命名无区别,可见性有区别**【实证】

`<CORE>` 全树 `pub const` 只有 **15 条真实声明**(另有 15 条在生成物 `pkg.generated.mbti` 中重复出现),全部落在这几个包:

```
byte/byte.mbt:17      pub const MAX_VALUE : Byte = b'\xFF'
byte/byte.mbt:26      pub const MIN_VALUE : Byte = b'\x00'
int/int.mbt:17        pub const MAX_VALUE = 2147483647
int/int.mbt:26        pub const MIN_VALUE = -2147483648
int16/int16.mbt:17    pub const MAX_VALUE : Int16 = 32767
int16/int16.mbt:26    pub const MIN_VALUE : Int16 = -32768
int64/int64.mbt:17    pub const MAX_VALUE = 9223372036854775807L
int64/int64.mbt:26    pub const MIN_VALUE = -9223372036854775808L
uint/uint.mbt:17      pub const MIN_VALUE : UInt = 0U
uint/uint.mbt:26      pub const MAX_VALUE : UInt = 4294967295U
uint16/uint16.mbt:17  pub const MAX_VALUE : UInt16 = 65535
uint16/uint16.mbt:26  pub const MIN_VALUE : UInt16 = 0
uint64/uint64.mbt:17  pub const MIN_VALUE : UInt64 = 0UL
uint64/uint64.mbt:26  pub const MAX_VALUE : UInt64 = 18446744073709551615UL
math/trig.mbt:17      pub const PI = 0x3.243F6A8885A308CA8A54
```

观察:
1. **命名一模一样**:都是 `UPPER_SNAKE_CASE`。可见性不改变命名风格。
2. 私有 `const` 是绝对主流(15 : 181)。core 的态度是能私有就私有。
3. `pub const` 只用于**真正的全局常量**(数值类型的边界、数学常数)。
4. 类型标注**可省**:`int/int.mbt:17`、`math/trig.mbt:17` 都省略了标注,由字面量推断;`moon info` 会把类型补全进 `pkg.generated.mbti`(`pub const PI : Double = …`)。涉及字面量歧义(如 `UInt` vs `Int`)时官方都显式标注 → **建议我们仍显式标注**。

### A.5 类型参数:单字母从 `A` 开始;`K/V` 是已确立惯例的例外【官方明文 + 实证】

【官方明文】原文见 A.1:`one character starting from A is preferred` + `Map[K,V] it is also accepted`。

【实证】在 `<CORE>` 全树统计顶层泛型函数的类型参数:

- 单字母 `[A]` 形态:**516** 处 —— `pub fn[A] Deque::insert(self : Deque[A], …)`(`<CORE>/deque/deque.mbt:428`)、`pub fn[T] abort(msg : String) -> T`(`<CORE>/abort/abort.mbt`)。
- 双字母形态:**193** 处,分两类:
  - **`A, B, C` 顺序字母**(多类型参数时按出现顺序取字母):`pub fn[A, B, C] zip_with(l : Array[A], r : Array[B], merge : (A, B) -> C raise?) -> Array[C] raise?`(`<CORE>/array/array.mbt:36`)、`pub fn[A, U] Deque::map(…)`(`<CORE>/deque/deque.mbt`)。
  - **`T, K` 语义字母**:`pub fn[T, K : Compare] maximum_by_key(x : T, y : T, f : (T) -> K) -> T`(`<CORE>/cmp/cmp.mbt`)、`pub fn[T, K : Compare] Array::sort_by_key(…)`(`<CORE>/builtin/array_sort.mbt`)。

**实操判定规则**(综合明文 + 实证):
1. 默认:按出现顺序 `A`, `B`, `C`…
2. 只有一个参数且无语义时,`A` 或 `T` 都行(实证两者都大量存在)。
3. **有已确立的语义时用语义单字母** —— 这是被官方明文豁免的一类:`K`/`V`(map 类)、`T`/`K`(sort_by_key 的元素 / 排序键)。**我们的 `Table[K, V]` 正属于此类,合规。**

### A.6 枚举变体、错误类型、trait 的命名惯例

**(a) 枚举变体 → `PascalCase`**【实证】

```moonbit
// <CORE>/json/types.mbt:24
pub(all) suberror ParseError {
  InvalidChar(Position, Char)
  InvalidEof
  InvalidNumber(Position, String)
  InvalidIdentEscape(Position)
  DepthLimitExceeded
} derive(Eq, ToJson, @debug.Debug)
```

```moonbit
// <CORE>/argparse/arg_spec.mbt:21,34
pub(all) enum FlagAction { … }
pub(all) enum OptionAction { … }
```

**(b) 错误类型 → 一律 `*Error` 后缀,且用 `suberror` 而非 `enum`**【实证】

`<CORE>` 全树 `*Error` 类型声明 15 处,逐一核对:

| 声明 | 位置 | 可见性 |
|---|---|---|
| `pub(all) suberror ParseError` | `<CORE>/json/types.mbt:24` | 公开 |
| `pub(all) suberror JsonDecodeError` | `<CORE>/json/from_json.mbt:20` | 公开 |
| `pub(all) suberror InspectError` | `<CORE>/builtin/console.mbt:82` | 公开 |
| `pub(all) suberror SnapshotError` | `<CORE>/builtin/console.mbt:249` | 公开 |
| `pub(all) suberror BenchError` | `<CORE>/builtin/console.mbt:255` | 公开 |
| `priv suberror ArgError` / `ArgParseError` / `ArgBuildError` | `<CORE>/argparse/error.mbt:21,60,114` | 私有 |
| `priv suberror QcError` | `<CORE>/quickcheck/driver_test.mbt:86` | 测试夹具 |
| `suberror IntError` / `StringError` | `<CORE>/error/error_test.mbt:16`、`<CORE>/builtin/existensial_test.mbt:16,21` | 测试夹具 |
| `priv suberror DecodeError` | `<CORE>/json/json_encode_decode_test.mbt:39` | 测试夹具 |
| `priv suberror MyError` | `<CORE>/test/test_test.mbt:52` | 测试夹具 |

**15/15 无一例外**:错误类型全用 `*Error` 后缀,**全部用 `suberror`,没有一个是 `enum`**。

> **与我们的冲突(重要)**:本项目用的是 `pub enum RegisterError[K] { … }` / `pub enum UpdateRejected[K, V] { … }`(`src/lib.mbt:124,139`),**不是 `suberror`**。这不算错(MoonBit 允许 `Result[T, E]` 里 `E` 是普通 `enum`),但偏离了 core 的一致实践。至少 `*Error` 后缀我们已经符合;但 `UpdateRejected` **不**以 `Error` 结尾,是个小瑕疵。

**(c) trait → `PascalCase` 名词/形容词,无前后缀**【实证】

```moonbit
// <CORE>/debug/debug.mbt:17     pub(open) trait Debug
// <CORE>/random/random.mbt:22   pub(open) trait Source
// <CORE>/builtin/json.mbt:227   pub(open) trait ToJson
// <CORE>/cmp/cmp.mbt            pub(open) trait Compare / Eq / Hash
```

可见性修饰语是 `pub(open)`(可被外部 `impl`),对照 `pub(all)`(结构体/枚举完全公开)。`<CORE>` 里 `pub(all)`/`pub(open)` 共 46 处,是本仓库公开类型的标准写法。
---

## §B 代码组织

### B.1 `///|` block style:块顺序无关,块内不强制紧跟文档注释【官方明文 + 实证】

【官方明文】`<CORE>/AGENTS.md:5-7`(原文):

    - MoonBit code is organized in block style, each block is separated by `///|`,
    the order of each block is irrelevant. In some refactorings, you can process
    block by block independently.

【官方明文】官方文档 `docs.moonbitlang.cn/language/docs.html`(注释与文档)进一步说明 `///|` 的**性质**:

> 你也会经常在顶层代码块开头看到 `///|`。它是一条**空的文档注释行**,用来显式分隔顶层条目。这对于当前的文档工具链很重要,也能为未来的缓存和其他工具用途保留清晰的顶层块边界。实际使用中,`///|` 不仅适用于文档源码,在普通的 MoonBit 代码里也很有用。

【实证】实际切块习惯:

1. **几乎每条顶层条目一个块**。`<CORE>/array/array.mbt` 从第 15 行起,每一个 `///|` 后跟一段文档注释再跟一个 `fn`。
2. **块前是文档注释时,`///|` 是空行**;块前无文档时,`///|` 独占一行紧贴声明:

       // <CORE>/hashmap/types.mbt:15-21
       ///|
       priv struct Entry[K, V] {
         mut psl : Int
         hash : Int
         key : K
         mut value : V
       } derive(@debug.Debug)

3. **不强制**:可以拿 `README.mbt.md` 验证 —— 官方文档里的可执行代码块本身**要求**写成 `///|` 加 `test {`:`<CORE>/hashmap/README.mbt.md:33-39,45-56`。也就是说 `///|` 是“块分隔符”,不是“文档注释专属”。
4. **`///|` 不是“必须”**:只有需要文档工具链识别为独立顶层块时才写。`<CORE>/hashmap/types.mbt:23-27` 出现了一段**悬空文档注释**(紧跟 `///|` 但没有声明),说明 `moon fmt` 允许这种写法存在(但它是笔误,不要学)。

**结论**:一个文件 = 一串 `///|` 分隔的独立块;块之间的顺序不影响语义,可以逐块重构。这正是 `<CORE>/AGENTS.md:6-7` 说 block by block independently 的依据。

### B.2 文件名约定:各自职责【官方明文 + 实证】

【官方明文】`<CORE>/AGENTS.md:9`:

    - Try to keep deprecated blocks in file called `deprecated.mbt` in each directory.

【官方明文】`<CORE>/AGENTS.md:26-27`:

    - MoonBit packages are organized per directory, for each directory, there is a `moon.pkg` file listing its dependencies.
    Each package has its files and blackbox test files (common, ending in `_test.mbt`) and whitebox test files (ending in `_wbtest.mbt`).

【实证】`<CORE>` 全树 `*.mbt*` 文件计数(排除 `_build`):

| 文件名 | 数量 | 职责(实证) |
|---|---|---|
| `*_test.mbt` | **355** | 黑盒测试包;用 `@pkg.name` 访问被测包,看不到 `priv` |
| `*_wbtest.mbt` | **49** | 白盒测试包;**同包编译**,可直接读私有字段 |
| `README.mbt.md` | **64** | 包级文学化文档,内含可执行示例;被 `moon check`/`moon test` 检查 |
| `extends.mbt` | **53** | `pub extend` 促进/废弃声明集中地(见 §C) |
| `deprecated.mbt` | **25** | 已废弃但需保留的 API(`#deprecated` 声明本体) |
| `types.mbt` | **20** | 类型定义集中地(`priv struct` / `pub(all) struct` / `suberror`) |
| `*.mbti` | **80** | 由 `moon info` 生成的接口快照(1 包 1 个) |
| 其它 `*.mbt` | 382 | 实现本体 |

**`extends.mbt` vs `deprecated.mbt` 的分工**(实证,容易混淆):

- `extends.mbt` 放**促进/隐藏**声明:`pub extend T with Trait::{m}` 和 `#deprecated + #doc(hidden) pub extend …`。它**不改 API 行为**,只改“方法能不能用点语法调”。
- `deprecated.mbt` 放**真的旧函数**,函数体还在,只是标了 `#deprecated`。例:`<CORE>/deque/deprecated.mbt:15-22`

      ///|
      /// Creates a new empty deque with an optional initial capacity.
      ///
      /// Deprecated: use `Deque([], capacity=...)` instead.
      #deprecated("Use `Deque([], capacity=...)` instead")
      #as_free_fn(deprecated=“Use `Deque([], capacity=...)` instead”)
      pub fn[A] Deque::new(capacity? : Int = 0) -> Deque[A] {
        new_deque(capacity)
      }

  注意 `deprecated.mbt` 里的 `#deprecated(...)` **不带** `skip_current_package=true`(因为本包内也确实不该再用了),而 `extends.mbt` 里的**都带**(见 §C.3)。

### B.3 `priv`:测试夹具必须声明 `priv`,否则触发 `[0079]`【官方明文】

这是本次调研**对我们项目最直接有用**的一条。

【官方明文】`<CORE>/AGENTS.md:100-105`(原文逐字):

    **Test fixtures should be `priv`.** A type declared in a `_test.mbt` file with no
    visibility modifier is *abstract-public*, so `implicit_impl_as_method` fires for
    its derived impls and you end up writing `pub extend` ceremony that has nothing
    to do with the test. Declare such types `priv` instead — then they need no
    `extend` at all. If a test needs to call a promoted method on one, use the trait
    form (`ToJson::to_json(x)`, `Default::default()`).

**原理逐层拆解**:

1. MoonBit 里不给可见性修饰语的顶层类型走**默认可见性**。在 `_test.mbt` / `_wbtest.mbt` 里,这个默认值官方称为 ***abstract-public***(抽象公开):类型名对外可见,但构造子/字段不可见。
2. `derive(Eq, Debug, Hash, …)` 会为该类型生成 `impl Eq for T` / `impl @debug.Debug for T`。
3. 只要 `T` 是 public(包括 abstract-public),编译器就会**隐式把这些 trait 方法提升为 `T` 的常规方法**(即可以用 `x.equal(y)`、`x.to_repr()`)。这个兼容行为被 `[0079]` 判定为**已弃用**。
4. 声明 `priv` 后,类型不再 public → **根本不进入“公开方法表”,提升无从发生 → `[0079]` 不触发 → 连 `extend` 都不用写**。

【官方明文】`[0079]` 的含义与官方修法,`docs.moonbitlang.cn/language/error_codes/E0079.html` 原文:

> **E0079**
> 警告名称:`implicit_impl_as_method`
> `impl Trait for Type` 声明中的方法正被隐式附加到 `Type`。这种兼容行为不够显式,也不具备重构安全性,因此已经弃用。此警告默认启用。
>
> **修改建议**:对于需要支持点语法的方法,使用 `extend Type with Trait::{method}`。如果兼容方法只需在迁移期内保留,请在对应的 `extend` 声明上添加 `#deprecated`;否则以 `Trait::method(value)` 调用实现。

【官方明文】警告编号与开关,`docs.moonbitlang.cn/toolchain/moon/package.html` + 本机 `moonc check -warn-help` 实测输出:

    implicit_impl_as_method    `impl` implicitly promoted as method           79 warn
    core_package_not_imported  Packages in `moonbitlang/core` need to be explicitly imported.  71 warn
    unused_package             Unused package.                                29 warn
    unused_value               Unused variable or function.                    1 warn
    missing_doc                Missing documentation for public definition    74 off
    prefer_fixed_array         Suggest FixedArray for mutated array literal    66 off
    prefer_readonly_array      Suggest ReadOnlyArray for read-only array literal 65 off
    unqualified_local_using    unqualified local using                        72 off
    unnecessary_annotation     unnecessary type annotation                    73 off
    unnecessary_view_op        Unnecessary `[:]` view operator                75 off
    test_unqualified_package   Using implicitly imported API in test.         25 warn

(以上为本机 `moonc` 实际输出的行,已逐行核对。)

---

## §C `extend` / trait 方法促进策略

### C.1 官方策略全文复述【官方明文】

`<CORE>/AGENTS.md:34-98` 是完整的 `# Trait-method promotion (extend)` 一节。核心判据一句话:

> **The rule for what we promote vs. deprecate (…) is driven by** where the trait lives **— because promoting a method couples the type's package to the trait's package.**

即:**促进一个方法 = 让类型的包依赖 trait 的包**。所以判据是 **trait 的“逻辑归属包”**,而不是它当前物理所在的文件。

【官方明文】原文关键段落(逐字):

    - **Traits whose home is `builtin`** (`Add`…`Sub`, `Compare`, `Eq`, `Hash`,
      `Show`, `Default`, `Logger`, `ToStringView`): every package already depends on
      `builtin`, so promoting them creates **no cycle** — safe on any type.
    - **Traits whose home is a higher package** (`@json.FromJson`,
      `@quickcheck.Arbitrary`, `@debug.Debug`): promoting them on a lower-level type
      would form a cycle (`builtin → json` etc.), so they are **never promoted** —
      always use the free function (`@json.from_json`, `@quickcheck.…`,
      `@debug.Debug`).

    This is about the trait's *logical* home, not the file it currently sits in:
    **`ToJson` lives in `builtin` today only for bootstrapping but belongs in
    `@json`**, so it is treated as a higher-package trait (not promoted) — promoting
    it would have to be ripped out the day it moves.

### C.2 对照表(逐条复述 `AGENTS.md:57-96`)

| trait / 方法 | 策略 | 官方理由(原文摘要) |
|---|---|---|
| 运算符 `add, sub, mul, div, mod, neg, land, lor, lxor, shl, shr` | **促进**(每个类型都促进) | the named method is a first-class value the operator syntax can't give you |
| `Compare::compare` | **促进**(每个 `impl` 它的类型都促进) | they're all in `builtin`, no cycle, and it keeps the surface uniform;是 *required* trait method,唯一能当一等值传递的方式(如 `Int::equal` 传进 fold) |
| `Eq::equal` | **促进**(同上) | 同上 |
| `Hash::hash` | **促进**(同上) | 同上 |
| `Compare::{op_lt, op_le, op_ge, op_gt}` | **永不促进,保持 deprecated** | → use `<` `<=` `>=` `>`(defaulted members,加了也没用) |
| `Eq::not_equal` | **永不促进,保持 deprecated** | → use `!=` |
| `Hash::hash_combine` | **永不促进,保持 deprecated** | implementer-facing, use it via the trait |
| **元组**(tuple)的上述促进 | **促进,但带 `#doc(hidden)`** | the synthetic `Tuple(N)::…` names are ugly in the interface; the methods still work without a warning |
| `Show::to_string` | **有条件促进**:仅当类型有**规范字符串表示**时(scalars、strings);**集合类废弃它**,改用 `@debug.Debug` | Collections deprecate it toward `@debug.Debug` (there's no single canonical `Show` for a collection) |
| `Show::output` | **永不促进** | use `to_string` / 字面量插值 |
| `Default::default` | **废弃(deprecated)** | a literal (`0`, `[]`, `None`, 空字符串, `b'\x00'`) or `Default::default()` via the trait bound is clearer, and it keeps the interface lean |
| ↳ 例外:`Byte::default()` | **暂时保留促进** | Moon's generated test drivers call `FixedArray::make(512, Byte::default())`, so deprecating it breaks `moon test --build-only --deny-warn`;待 moonbitlang/moon#1938 落地后一并废弃 |
| `ToJson::to_json` | **永不促进** | use **`Json(x)`**, the constructor of `Json`(由 prelude 再导出,无需 import,从任何包都能用,`builtin` 也包括) |
| `@json.FromJson::from_json` | **永不促进** | 高层包 trait,促进成环 |
| `@quickcheck.Arbitrary` | **永不促进** | 同上 |
| `@debug.Debug::to_repr` | **永不促进** | 同上;用 `@debug.Debug` / `to_repr(x)` |

【官方明文】作用域限定,`<CORE>/AGENTS.md:98`:

    This policy governs a package's own `extends.mbt` (its public API surface).

【官方明文】改完后的收尾,`<CORE>/AGENTS.md:107-109`:

    After editing `extends.mbt`, run `moon info && moon fmt` and check the `.mbti`
    diff. `#doc(hidden)` alone (no `#deprecated`) keeps a promotion working but hides
    it from the generated interface — that's how tuples stay usable but tidy.
### C.3 `#deprecated(..)` / `#doc(hidden)` 的准确写法与用途

【实证】core 里 `#deprecated(` 出现 **601** 次,其中 `extends.mbt` 里是标准三行式。**最规范的样板**是 `<CORE>/hashmap/extends.mbt`(全文 45 行,短到可以整份背下来):

```moonbit
// <CORE>/hashmap/extends.mbt:15-45
// --- promoted: kept as regular methods ---

///|
pub extend HashMap with Eq::{equal}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend HashMap with @debug.Debug::{to_repr}

///|
#deprecated("Use `@json.from_json` instead", skip_current_package=true)
#doc(hidden)
pub extend HashMap with @json.FromJson::{from_json}

///|
#deprecated("Use `Default::default` instead", skip_current_package=true)
#doc(hidden)
pub extend HashMap with Default::{default}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend HashMap with Eq::{not_equal}

///|
#deprecated("Use `@json.to_json` instead", skip_current_package=true)
#doc(hidden)
pub extend HashMap with ToJson::{to_json}
```

**要素分解(每一条都是硬要求)**:

| 要素 | 说明 |
|---|---|
| `///|` 在属性**之前** | 属性属于这个块;顺序错了 `moon fmt` 会重排 |
| `#deprecated("…", skip_current_package=true)` | 必须带 `skip_current_package=true`。裸 `#deprecated("…")` 会让**本包自己的代码**在调用时也报 `[0020] deprecated`。core 的 `extends.mbt` **无一例外**都带这个参数(对照 `deprecated.mbt` 里不带) |
| 文案格式 | 一律 `Use X instead` 句型。祈使句,首字母大写,句尾无句号。core 里可复用的文案:`"Use `!=` instead"`、`"Use `@debug.Debug` instead of `Show` for collections"`、`"Use `Show::output` via the trait or `to_string` instead"`、`"Use `Debug::to_repr` instead"`、`"Use `@json.to_json` instead"`、`"Use `Default::default` instead"` |
| `#doc(hidden)` | 从 `.mbti` 生成的公开接口中隐藏该促进。**这是它和 `#deprecated` 的关键分工**:`#deprecated` 管报不报警告,`#doc(hidden)` 管进不进接口 |
| `pub extend T with Trait::{m1, m2}` | **必须 `pub`**。多个方法一次列全(如 `Show::{to_string, output}`) |
| 只 `#doc(hidden)` 不带 `#deprecated` | 官方明文说明这是“让方法可用但接口干净”的手法(元组用的就是它) |

【实证】同一文件里的排列顺序是**先所有 promoted,再所有 deprecated**,用注释分节:

```moonbit
// --- promoted: kept as regular methods (blessed public API) ---     // <CORE>/json/extends.mbt:15
// --- promoted: kept as regular methods ---                          // <CORE>/hashmap/extends.mbt:15
// --- deprecated: hidden from the generated interface ---            // 两者都用这一行
```

`<CORE>/json/extends.mbt` 是最完整的示例(139+ 行),四个类型 × 固定套路:

```moonbit
// <CORE>/json/extends.mbt:17-33
///|
pub extend JsonDecodeError with Eq::{equal}

///|
pub extend JsonDecodeError with Show::{to_string}

///|
pub extend JsonPath with Eq::{equal}

///|
pub extend JsonPath with Show::{to_string}

///|
pub extend ParseError with Eq::{equal}

///|
pub extend ParseError with Show::{to_string}

///|
pub extend Position with Eq::{equal}
```

**注意这个套路的周延性**:`JsonPath` 只促进了 `Eq::equal`,**没有** `Show::to_string`,但它照样出现在 deprecated 段里对 `Show::output` 和 `@debug.Debug::to_repr` 做了废弃声明 —— 因为 `impl` 本身会让**所有**方法都被隐式提升,所以必须逐个“关掉”。

### C.4 `ToJson::to_json` 不促进 → 用 `Json(x)`:可运行片段

【官方明文】`<CORE>/AGENTS.md:88-96`(原文):

    - **`ToJson::to_json`**: **not promoted** — use **`Json(x)`**, the constructor of
      `Json` (re-exported by the prelude, so it needs no import and works from every
      package, `builtin` included). Between that and `Json`'s literal sugar
      (`([x, y] : Json)`, `({ “k”: v } : Json)`) you rarely need `x.to_json()`
      at all, and serialization is cold, so nothing is lost by going through the
      constructor.

【实证】`Json(x)` 就是 `Json` 的**构造函数**,定义在 `<CORE>/builtin/json.mbt:221`:

```moonbit
// <CORE>/builtin/json.mbt:200-223
/// Converts any value implementing `ToJson` into a `Json`.
///
/// This is the constructor of `Json`, so it is written `Json(value)`, and it is
/// re-exported by the prelude — no import is needed. Prefer it over calling
/// `ToJson::to_json` directly.
///
/// Parameters:
///
/// * `value` : The value to convert.
///
/// Returns the `Json` representation of `value`.
///
/// Example:
///
/// ```mbt check
/// test {
///   @debug.debug_inspect(Json(42), content="Number(42)")
///   @debug.debug_inspect(Json("hello"), content="String(\"hello\")")
///   @debug.debug_inspect(Json([1, 2]), content="Array([Number(1), Number(2)])")
/// }
/// ```
pub fn[T : ToJson] Json::Json(value : T) -> Json {
  ToJson::to_json(value)
}
```

**可直接运行的最小验证片段**(放进任意包的 `*_test.mbt`,无需 import):

```moonbit
///|
test `Json(x) constructor needs no import` {
  debug_inspect(Json(42), content=`Number(42)`)
  debug_inspect(Json(`hi`), content=`String(\`hi\`)`)
  debug_inspect(Json([1, 2]), content=`Array([Number(1), Number(2)])`)
  // Json 字面量糖,同样不需要 to_json
  let obj : Json = { `k`: [1, 2] }
  debug_inspect(obj, content=`Object({\`k\`: Array([Number(1), Number(2)])})`)
}
```

对照的反面写法(**不要**):

```moonbit
let j = x.to_json()          // 错:ToJson::to_json 不促进(若包内有该 impl)
let j = ToJson::to_json(x)   // 对但啰嗦:官方推荐用 Json(x)
```

> 说明:上面 `debug_inspect` 的 `content` 是**示意**;真实快照请用 `moon test --update` 生成。core 原文的期望值来自 `<CORE>/builtin/json.mbt:216-218`。

---

## §D 文档注释

### D.1 风格:首行一句话摘要,段标题 `Parameters:` / `Returns:` / `Panics:` / `Example:`【官方明文 + 实证】

【官方明文】`docs.moonbitlang.cn/language/docs.html`:

> 文档注释使用 `///`,逐行写在 `fn`、`let`、`enum`、`struct`、`type` 等顶层条目前面。文档注释内容使用 **Markdown** 编写。
>
> 文档注释中的 Markdown 代码块如果标记为 `mbt check`,就会被视作**文档测试**;`moon check` 和 `moon test` 会自动检查并运行这些测试,从而保证文档注释中的示例始终是最新的。需要测试块时,请将代码包在 `test { .. }` 中。
>
> 目前,文档测试都是**黑盒测试**。所以**私有定义目前不能有文档测试**。

【实证】`<CORE>` 全树 `*.mbt*` 的段标题统计:

| 段标题 | 出现次数 |
|---|---|
| `/// Example:` | **763** |
| `/// Parameters:` | **729** |
| `/// Example`(无冒号) | 20 |
| `/// Notes:` | 12 |
| `/// Examples:`(复数) | 8 |
| `/// Note:` | 2 |
| `/// Panics:` | 2 |
| `/// Throws:` | 1 |
| `/// Returns:` | 1 |
| `# Examples`(Markdown 标题形式) | **0** |

**这就是官方风格的全貌**:
1. **有冒号的段标题**(Markdown 无序列表跟随),**不是** Rust 那种 `# Examples` / `# Panics` 标题形式。core 里 `# Examples` 一次都没出现。
2. 首行是**一句话摘要**(句号结尾),空 `///` 行,再分段。
3. 主体模板:摘要 → 空 → `Parameters:` → 空 → `* 参数名 : 说明` 列表 → 空 → (`Returns:` / `Panics:` / `Throws:`) → 空 → `Example:` → 空 → `mbt check` 代码块。
4. `Example:` 是**单数**为主(763 vs 8),但 canon 写法两种都有,不必纠结。
5. 段标题**不是强制的**:`<CORE>/math/hyperbolic.mbt:90-95` 用的是 `Special cases:` 这类自由标题,说明标题可自定义。

### D.2 五个写得好的真实例子

**例 1 —— 教科书模板:`Parameters` + `Panics` + `Example` 齐全**

`<CORE>/deque/deque.mbt:380-428`(节选):

```moonbit
/// Inserts an element at the specified position...
/// shifted in-place to make room for the new element, modifying the original deque.
///
/// Parameters:
///
/// * `self` : The deque in which the element will be inserted.
/// * `index` : The position at which to insert the element. Must satisfy `0 <= index <= self.length()`.
/// * `value` : The element to insert.
///
/// Panics:
///
/// * If `index` is out of bounds, the function will abort with an error message.
///
/// Example:
///
/// ```mbt check
/// test {
///   let v1 = @deque.from_array([1, 2, 3])
///   v1.insert(0, 0) // insert at the front
///   debug_inspect(
///     v1,
///     content=(
///       #|<Deque: [0, 1, 2, 3]>
///     ),
///   )
///   …
/// }
/// ```
#owned(value)
pub fn[A] Deque::insert(self : Deque[A], index : Int, value : A) -> Unit {
```

**看三点**:(a) `Panics:` 段明说会 abort;(b) 预览值用 `#|…` 多行字面量避免转义地狱;(c) 示例覆盖 front/middle/end **三个边界**。

**例 2 —— 同文件里的 `Returns:` 写法**:`<CORE>/deque/deque.mbt:459-499`

```moonbit
/// Removes and returns the element at the specified position in the deque. …
///
/// Parameters:
///
/// * `self` : The deque from which the element will be removed.
/// * `index` : The position of the element to remove. Must satisfy `0 <= index < self.length()`.
///
/// Returns:
///
/// * The element that was removed from the deque.
///
/// Panics:
///
/// * If `index` is out of bounds, the function will abort with an error message.
```

**例 3 —— 最简标准形态(最值得日常模仿)**:`<CORE>/array/array.mbt:15-42`

```moonbit
///|
/// Zips two arrays into a single array by applying a function to each pair of elements.
///
/// Parameters:
///
/// * `l` : The first array.
/// * `r` : The second array.
/// * `merge` : A function that takes two arguments, one from each array, and returns a value.
///
/// Returns an array containing the results of applying the function to each pair of elements.
///
/// Example:
///
/// ```mbt check
/// test {
///   let arr1 = [1, 2, 3]
///   let arr2 = [4, 5, 6]
///   let add = (a, b) => a + b
///   debug_inspect(@array.zip_with(arr1, arr2, add), content=`[5, 7, 9]`)
/// }
/// ```
pub fn[A, B, C] zip_with(l : Array[A], r : Array[B], merge : (A, B) -> C raise?) -> Array[C] raise? {
```

**例 4 —— 边界条件清单式文档**:`<CORE>/math/hyperbolic.mbt:90-110`

```moonbit
/// Special cases:
///
/// * Returns `infinity` if `x` is `infinity`
/// * Returns `NaN` if `x` is `NaN`
///
/// Example
///
/// ```mbt check
/// test {
///   inspect(@math.coshf(0), content=`1`)
///   inspect(@math.coshf(-0), content=`1`)
///   inspect(@math.coshf(1), content=`1.5430805683135986`)
///   inspect(@math.coshf(2), content=`3.7621958255767822`)
///   inspect(@math.coshf(1000), content=`Infinity`)
///   inspect(@math.coshf(-1000), content=`Infinity`)
///   inspect(@math.coshf(@float.not_a_number), content=`NaN`)
///   inspect(@math.coshf(@float.infinity), content=`Infinity`)
///   inspect(@math.coshf(@float.neg_infinity), content=`Infinity`)
/// }
/// ```
```

**看两点**:(a) **每个特殊值一条 `inspect`**,边界全覆盖;(b) `Example` 这里**没用冒号** —— 证明段标题格式有弹性。

**例 5 —— 类型/错误类型的文档**:`<CORE>/json/types.mbt:15-30`

```moonbit
///|
/// Type `Position` used by this package APIs.
pub(all) struct Position {
  line : Int // 1-based
  column : Int // 0-based
} derive(Eq, ToJson, @debug.Debug)

///|
/// Error type `ParseError`.
pub(all) suberror ParseError {
  InvalidChar(Position, Char)
  InvalidEof
  …
} derive(Eq, ToJson, @debug.Debug)
```

注意:**字段的语义(1-based / 0-based)用行尾 `//` 注释写**,而不是塞进文档注释。这是 core 处理“字段含义”的常见手法。

### D.3 `README.mbt.md` 是什么、怎么被测试/渲染【官方明文】

【官方明文】`docs.moonbitlang.cn/language/docs.html` 的「文学化 .mbt.md 文件」一节原文:

> MoonBit 也支持以 `.mbt.md` 结尾的文学化 Markdown 文件。这些文件既可以作为**包内**的可检查文档,也可以作为 `moon check` 和 `moon test` 的**独立单文件输入**。
>
> 对于独立文件,运行:
>
>     moon check README.mbt.md
>     moon test README.mbt.md
>
> 在项目内部,请继续使用**包级别**的 `moon check` 和 `moon test` 命令。
>
> 代码块的语言标记决定了每个代码块会如何处理:
>
> | 标记 | 处理 |
> |---|---|
> | `mbt` | 会编译其中的 MoonBit 代码,**但不会创建测试入口** |
> | `mbt check` | MoonBit **文档测试**代码。需要断言时,请在代码块内部使用 `test { .. }` 或 `async test` |
> | `mbt nocheck` | 仅展示,不编译 |

【实证】core 里 `README.mbt.md` **64** 个,几乎每个包一个。示例 `<CORE>/hashmap/README.mbt.md`:

````markdown
# HashMap

A mutable hash map based on a Robin Hood hash table.

## How It Works
…

```mermaid
flowchart TD
  S[“set(k, v)”] --> H[“idx = hash & mask, psl = 0”]
  …
```

# Usage

## Create

You can create an empty map using `HashMap([])` or construct it from entries using `HashMap([...])`.

```mbt check
///|
test {
  let _map1 = @hashmap.HashMap([(“a”, 1), (“b”, 2)])
  let _map2 : @hashmap.HashMap[String, Int] = HashMap([])
}
```
````

**三个可直接照抄的要点**:
1. 块内**必须**以 `///|` 开头,然后 `test {` —— 与普通 `.mbt` 文件同一套 block style。
2. 文档里的示例**直接用带 `@pkg.` 前缀的黑盒调用**(如 `@hashmap.HashMap(…)`),因为文档测试是黑盒。
3. `mermaid` 等其他语言标记的块原样保留,不编译。

> 对我们的意义:`README.md` 里的 API 表格目前**不可执行**,会漂移。若改名为 `README.mbt.md` 并把示例改成 `mbt check`,CI 的 `moon test` 会自动保证示例不过期。**注意** `moon.mod` 的 `readme = "README.md"` 字段需要同步(否则 mooncakes 页面无 README)。

---

## §E 测试

### E.1 `inspect`(快照)优先于 `assert`;循环里用 `assert_eq`/`assert_true`【官方明文】

【官方明文】`<CORE>/CONTRIBUTING.md:81-84` 原文:

    - Testing guidelines

      We encourage you to use `inspect` over `assert` in tests, as `inspect` provides more information about the values being tested and can
      be updated easily. For testing in the loop, you may use `assert_eq`/`assert_true` since snapshot testing does not work well in the loop.

【官方明文】`<CORE>/AGENTS.md:31-32` 原文:

    - When writing tests, you are encouraged to use `inspect` and run `moon test --update` to update
      the snapshots, only use assertions like `assert_eq` when you are in some loops where each snapshot may vary.
      You can use `moon coverage analyze > uncovered.log` to see which parts of your code are not covered by tests.

【实证】**数量比 12635 : 5889**(`inspect(` 约 2.15 倍于 `assert_eq`/`assert_true`)。方向与官方说法一致。

**准确写法与 `--update` 的关系**:

```moonbit
///|
test `insert returns a live handle` {
  let t : Table[Int, Int] = Table::new()
  let id = t.insert(1).unwrap()
  inspect(id, content=`RowId(slot=0, gen=0)`)   // ← 期望值写在 content= 里
}
```

- 首次写测试:**不写 `content=`**,直接 `inspect(id)`,然后跑:

      moon test --update     # 短选项 moon test -u

  生成的快照会被**回写进源文件**(所以 `.mbt` 文件会被改写,记得提交)。
- 之后每次 `moon test` 都是**比对**:不一致就失败,并打印 diff。
- 变量写法:`inspect(x)`、带期望值 `inspect(x, content="…")`、多值 `inspect((a, b), content=…)`。
- 多行期望值用 `#|…` 原始字面量,避免转义(见 §D.2 例 1)。
- 官方同时给了覆盖率路径:`moon coverage analyze > uncovered.log`(`<CORE>/AGENTS.md:32`)。

> 与我们的现状:`AGENTS.md` 已记录 Avoid `debug_inspect` inside loops,与官方一致。但项目里用的是 `debug_inspect`,而官方 `CONTRIBUTING.md`/`AGENTS.md` 写的是 `inspect`。二者在 core 里都存在,`inspect` 是主流写法。**建议统一到 `inspect`**(它来自 builtin,无需 import)。

### E.2 `test "…"` 的命名风格:描述**行为**,英文句子,动词开头【实证】

【实证】`<CORE>` 全树 `test "…"` 声明 **6286** 个。抽样(按文件字典序靠前的 `argparse` 包):

```
test `declarative parse basics` {                                  // 名词短语:可接受
test `command policies` {
test `unknown argument keeps suggestion in final message` {        // ← 典型:主语 + 动词 + 结果
test `parse error show is readable` {
test `unknown argument suggestions are exposed` {
test `unified error message formatting remains stable` {
test `unknown short suggestion can be absent` {
test `Debug for argparse enums` {                                  // ← 少数:描述对象/API
test `global option merges parent and child values` {
test `global requires is validated after parent-child merge` {
test `global append keeps parent argv over child env/default` {
test `global count merges parent and child occurrences` {
test `global count negation after subcommand resets merged state` {
test `nested subcommands inherit finalized globals from ancestors` {
test `compatible global flag can be redeclared in a subcommand` {
test `parse failure message contains error and contextual help` {
test `subcommand parse errors include subcommand help` {
test `render_help remains available for pure formatting` {
test `display help and version` {
test `full help snapshot` {
test `render help snapshot with groups and hidden entries` {
test `help subcommand styles and errors` {
test `builtin and custom help/version dispatch edge paths` {
test `version action dispatches on custom long and short flags` {
```

另一个包的对照(`<CORE>/sorted_map/*_test.mbt`,同一取样方式):

```
test `remove2` {                                     // ← 反面教材:数字后缀,无信息
test `remove3` {
test `remove on empty map` {                         // ← 正面:行为
test `SortedMap constructor` {
test `get` {                                         // ← 极简:只写 API 名
test `panic at` {                                    // ← 前缀 panic 标记 panic 测试
test `from_iter multiple elements iter` {
test `from_iter empty iter` {
test `to_json with non-empty map` {                  // ← X with <条件> 是高频句型
test `to_json with empty map` {
test `from_json rejects non-object` {                // ← X rejects Y
test `get_or_init inserts when absent` {             // ← X <动词> when <条件>
test `get_or_init returns existing value` {
test `range with inverted bounds returns empty` {
```

**归纳出的命名惯例(可直接照做)**:

| 句型 | 例子 |
|---|---|
| `<主语> <动词> <宾语>` | `unknown argument keeps suggestion in final message` |
| `<API> with <条件>` | `to_json with empty map` |
| `<API> <动词> when <条件>` | `get_or_init inserts when absent` |
| `<API> rejects <输入>` | `from_json rejects non-object` |
| `<API> returns <结果>` | `get_or_default returns default when absent` |
| `panic <API>`(panic 测试专用前缀) | `panic at` |
| `<API>`(极简,老代码常见) | `get`、`contains` |
| `<API> snapshot`(快照测试) | `full help snapshot` |

**其它实测事实**:
- **全小写英文句子**,无句号,不加 `test_xxx` 前缀,不用中文。
- 允许出现 `@pkg.` 前缀:`test "@sorted_map.merge"`(`<CORE>/sorted_map/map_test.mbt:302`)。
- 老代码里有 `remove2`/`remove3` 这种数字后缀,**不要学**。
- 可选:测试名可省略 → `test { … }`。**但 `README.mbt.md` 里的文档测试必须写成无名 `test { … }`**(实证全部如此)。
- 重复的测试名会触发 `[0061] duplicate_test`(`moonc check -warn-help` 实测:D`uplicate test name.  61 warn`)。

> 与我们的现状:`AGENTS.md` 已写 `test "descriptive english name"`,方向正确。**建议补上上表的句型表**,并明确 panic 测试以 `panic ` 开头。

### E.3 黑盒 `_test.mbt` 与白盒 `_wbtest.mbt` 的官方定义与边界【官方明文】

【官方明文】`<CORE>/AGENTS.md:26-27`:

    - MoonBit packages are organized per directory, for each directory, there is a `moon.pkg` file listing its dependencies.
    Each package has its files and blackbox test files (common, ending in `_test.mbt`) and whitebox test files (ending in `_wbtest.mbt`).

【官方明文】`docs.moonbitlang.cn/toolchain/moon/package.html` 的「测试导入」与「白盒测试导入」两节原文:

> **测试导入**用于指定此包的黑盒测试包依赖的其他包,配置语法与 `import` 相同……
> `test-import-all` 字段用于指定**是否导入被测试包的公共定义(默认为 true)**。
> **白盒测试导入**用于指定此包的白盒测试包依赖的其他包,配置语法与 `import` 相同。

【官方明文】`docs.moonbitlang.cn/language/docs.html`:

> 目前,文档测试都是**黑盒测试**。所以私有定义目前不能有文档测试。

**据此可确定的边界(权威版)**:

| | `*_test.mbt`(黑盒) | `*_wbtest.mbt`(白盒) |
|---|---|---|
| 编译方式 | 独立的**外部包**,通过 `@alias.name` 访问被测包 | 与**同包**一起编译 |
| 可见性 | 只能看 `pub` / `pub(all)`;看不到 `priv` | 可访问**一切**,包括 `priv` 字段 |
| 被测包公共定义是否自动可见 | 是(`test-import-all` 默认 `true`) | 不适用(本身就在包内) |
| 依赖声明 | `import { … } for "test"` | `import { … } for "wbtest"` |
| 数量(core 实证) | 355 | 49 |
| 文档测试能否用 | **能**(文档测试一律黑盒) | 不能 |

【实证】`<CORE>` 里两类文件的典型分工:
- `*_test.mbt` 用 `@pkg.f(…)` 调用,断言公开行为。
- `*_wbtest.mbt` 直接读写内部结构,例如 `<CORE>/bigint/bigint_default_wbtest.mbt:18` 的 `priv struct MyBigInt(BigInt)`、`<CORE>/debug/delta_wbtest.mbt:16` 的 `priv struct Empty {} derive(Debug)`。

> 与我们的现状:`AGENTS.md` 已经写对了(Tests are black-box: always the `@aurasuisui/multiindex.` prefix;`*_wbtest.mbt` files read private fields)。**唯一缺的是 §B.3 那条:白盒测试里的夹具类型必须 `priv`。**
---

## §F 包与模块布局 + CI

### F.1 `moon.mod` 的官方字段【官方明文 + 实证】

【实证】`<CORE>/moon.mod`(全文 13 行):

```toml
name = `moonbitlang/core`

version = `0.10.14+7d59c7ec9`

readme = `README.md`

repository = `https://github.com/moonbitlang/core`

license = `Apache-2.0`

keywords = [ `core`, `standard library` ]

warnings = `+test_unqualified_package+unqualified_local_using+missing_doc+unnecessary_view_op+unnecessary_annotation+prefer_fixed_array+prefer_readonly_array-implicit_use_builtin+implicit_impl_as_method`
```

**注意最后一行**:core **在模块级别**打开了 7 个默认关闭的警告(`+missing_doc`、`+unnecessary_annotation` 等),同时关掉了 `-implicit_use_builtin`,并**重新打开**了 `+implicit_impl_as_method`(它本身默认就是 `warn`,这里显式写出来是**声明意图**:core 要求 `extends.mbt` 必须显式,不接受隐式提升)。

【实证】其它官方模块(交叉验证字段用法):

```toml
# moonbitlang/x/moon.mod
name = `moonbitlang/x`; version = `0.5.5`; readme = `README.md`
repository = `https://github.com/moonbitlang/x`; license = `Apache-2.0`
keywords = [ `experimental`, `moonbitlang`, `json`, `time`, `crypto` ]
description = `experimental packages for moonbitlang/core`

# moonbitlang/async/moon.mod
name = `moonbitlang/async`; version = `0.22.4`; …
preferred_target = `native`
source = `src`
```

**常见字段**:`name`(必填)、`version`、`readme`、`repository`、`license`、`keywords`、`description`、`source`、`preferred_target`、`warnings`。
> 我们的 `moon.mod` 已有 `name/version/readme/repository/license/keywords/description/source`,**缺 `warnings`**。见 §H.8。

### F.2 `moon.pkg`:import 分组与 `for "test"` / `for "wbtest"`【官方明文 + 实证】

【官方明文】`docs.moonbitlang.cn/toolchain/moon/package.html` 给出 `moon.pkg` 的完整语法:

```
moon_pkg    ::= statement*
statement   ::= import | assign | apply
import      ::= `import` `{` (import_item `,`)* import_item? `}` import_kind?
import_item ::= STRING (`@` PKG_NAME)?
import_kind ::= `for` STRING
```

原文补充:

> 大多数 core 包在这里仍按普通包处理:如果你使用 `@json`、`@test` 或其他普通的 core 别名,请将对应的 `moonbitlang/core/...` 包加入 `import`,以避免 `core_package_not_imported` 警告。
> **`prelude` 是例外。它默认可用,因此它暴露的名称不需要显式导入对应的包。**

【实证】`<CORE>` 80 个 `moon.pkg` 的用法。最规范的样板 `<CORE>/sorted_map/moon.pkg`(全文 14 行):

```text
import {
  `moonbitlang/core/builtin`,
  `moonbitlang/core/debug`,
  `moonbitlang/core/json`,
}

import {
  `moonbitlang/core/quickcheck`,
  `moonbitlang/core/test`,
} for `test`

import {
  `moonbitlang/core/test`,
} for `wbtest`
```

**实测的分组规则**:
1. **第一个 `import { … }`(无 `for`)是生产依赖**,只放源码真正用到的。
2. **`import { … } for "test"` 是黑盒测试依赖**;`import { … } for "wbtest"` 是白盒测试依赖。
3. 有 `wbtest` 块的包很少(core 里只有 `bigint`、`diff`、`json` 等少数几个),因为白盒测试通常不需要额外依赖。
4. **别名写在路径后面**:`"moonbit-community/language/packages/pkgC" @c,`。
5. `moon.pkg` **支持 `//` 注释**:`"moonbitlang/core/math", // FIXME: IDE false alarm unused package`(`<CORE>/builtin/moon.pkg:17`)。
6. 其它顶层声明:`warnings = "-test_unqualified_package"`(`<CORE>/builtin/moon.pkg:22`、`<CORE>/prelude/moon.pkg:14`)、`pkgtype(kind: "executable")`、`options(targets: { "only_js.mbt": [ "js" ], … })`、`supported_targets = "js"`。
7. **`pkgtype(kind: "executable")` 取代旧的 `options("is-main": true)`**;`warnings` 取代 `warn-list`;旧的 `@` 前缀(把警告提升为错误)也已弃用,官方明确要求改用 `moon check --deny-warn`。

### F.3 官方 CI 到底跑什么【官方 CI】

`<CORE>/.github/workflows/` 有 5 个文件:`stable-check.yml`、`bleeding-check.yml`、`pre-release-check.yml`、`misc-check.yml`、`copilot-setup-steps.yml`。

**`stable-check.yml` 的 `stable-check` job 逐步(`:21-58`,OS 矩阵 ubuntu/macos/windows)**:

| # | 步骤 | 命令 |
|---|---|---|
| 1 | check | `moon check --deny-warn --target all` |
| 2 | moon info | `moon info --target wasm,wasm-gc,js,native` + `git diff --exit-code` |
| 3 | format diff | `moon fmt` + `git diff --exit-code` |
| 4 | run tests | `uses: ./.github/actions/test` |
| 5 | moon bundle | `moon bundle --all` |
| 6 | check core size | `find ./target -name '*.core' \| xargs ls -lh`(非阻断性巡检) |

**`stable-native-opt-test` job**(`:60-79`):`moon check --target native --deny-warn` + native release 测试。

**`misc-check.yml`(整个 job 是 `continue-on-error: true`,官方自己标注为非阻断)**:

| 步骤 | 命令 | 说明 |
|---|---|---|
| 1 | `jq '.' $f` 遍历所有 `moon.*.json` | 早期 JSON 配置的格式校验 |
| 2 | 下载 HawkEye `v5.8.1` → `hawkeye check` | **License header 检查** |
| 3 | `uses: crate-ci/typos@v1` | **拼写检查** |
| 4 | `moon test --enable-coverage` | 覆盖率 |
| 5 | `moon coverage report -f summary` + coveralls 上传 | 报告进 `GITHUB_STEP_SUMMARY` |

**`bleeding-check.yml`(nightly)= stable 的超集,额外跑**:`moon test --target wasm`(新分配器,`MOONC_INTERNAL_PARAMS: allocator = tlsf-mbt`)、重复 `moon check --deny-warn`、`moon bundle --all`。

**`pre-release-check.yml`**:多一步 `moonc -v` 版本日期比较(决定是否跳过)+ 上述全部。

**`CONTRIBUTING.md` 里写给贡献者的手动五步(`:47-53`)**

```bash
moon check
moon test
moon bundle --all
moon info   # Regenerate tracked package interfaces (.mbti)
moon fmt
```

加上 `:26-30` 那句 To verify that the core can be bundled for all supported targets, run: `moon bundle --all`,以及 `:57` 的 `moon test --target all` + release-mode 测试。

### F.4 与我们五步 CI 的逐项对比 → 该抄什么【差异分析】

我们现在的五步(`.github/workflows/ci.yml`):

```
moon fmt --check → moon check → moon info && git diff --exit-code → moon test → moon build
```

| 官方有的检查 | 我们有? | 官方证据 | 建议 |
|---|---|---|---|
| `moon check --deny-warn` | ❌ 只有 `moon check` | `stable-check.yml:29` | **强烈建议补** |
| `moon check --target all`(全后端) | ❌ 只默认后端 | `stable-check.yml:29` | **建议补**。JS/native 的 `Int` 宽度/溢出行为可能不同 |
| `moon fmt` + `git diff --exit-code` | ✅ `moon fmt --check` 等价 | `stable-check.yml:39-41` | 保持 |
| `moon info` + `git diff --exit-code` | ✅ 有 | `stable-check.yml:33-35` | 我们做得**更细**(官方不带全 target),不用改 |
| `moon test` | ✅ 有 | `stable-check.yml:43-45` | 可考虑补 `--target all` |
| **`moon bundle --all`** | ❌ 无 | `stable-check.yml:47-48`、`CONTRIBUTING.md:26-30` | **建议补,但先看下方实测结论** |
| **License header 检查(HawkEye)** | ❌ 无 | `misc-check.yml:36-42` | 可选。见 §G |
| **拼写检查(`crate-ci/typos`)** | ❌ 无 | `misc-check.yml:44-46` | **可选**。core 用 `_typos.toml` 配置排除项 |
| 覆盖率(`--enable-coverage` + report) | ❌ 无 | `misc-check.yml:51-67` | 可选。官方放在 **`continue-on-error: true`** 的 job 里 |
| 构建产物体积巡检 | ❌ 无 | `stable-check.yml:50-58` | 不适用于库 |
| native release 模式测试 | ❌ 无 | `stable-check.yml:77-79` | 可选。库项目收益中等 |
| `moon build` | ✅ 有(官方 CI **没有**单独的 `moon build` 步骤) | —— | 我们的 `moon build` 是冗余步骤;`moon bundle --all` 覆盖更多 |

**实测(本次调研验证过,可信度高)**:

1. `moon check --deny-warn` 在**原项目**上:`Failed with 0 warnings, 16 errors`(16 = 14 条 `[0079]` + 2 条 `[0029]`)。**一旦加上这个 CI 步骤,现状直接红。**
2. 在临时探针工程里完成 §H 的修复后:`moon check` **0 warnings 0 errors**,且 `moon test` **51/51 passed**,生成的 `pkg.generated.mbti` 与修复前**逐字节相同**(67 行无差异)。→ **修复不影响公开 API**,是纯内部的告警治理。
3. `moon bundle --all` 在本项目上**当前会 panic**:

       thread 'main' panicked at crates\moonbuild-rupes-recta\src\execution_plan\mod.rs:491:9:
       declared execution output has multiple producers: …\_build\wasm\release\bundle\multiindex.core

   这是 **moon 0.1.20260920 的 bug**(官方提示上报 `moonbitlang/moon`),`bundle` 无法在我们这种“根包 + `src` 子包”布局上工作。**结论:暂时不要抄 `moon bundle --all`**,或在 CI 里允许失败。
4. `moon.pkg` 加 `warnings` 打开 core 那 7 个警告后,**我们项目会产生 30 条 `[0073] unnecessary_annotation`**,分布:`src/index.mbt`(2)、`src/property_test.mbt`(8)、`src/table_api.mbt`(8)、`src/table_test.mbt`(12)。其中 `table_test.mbt` 那些正是 `@aurasuisui/multiindex.` 全限定前缀 —— **与 `AGENTS.md` 里黑盒测试一律加前缀的硬性约定直接冲突**。**结论:`+unnecessary_annotation` 不要抄。**
---

## §G License header

### G.1 官方 `licenserc.toml` 要求的 header 格式【官方明文】

`<CORE>/licenserc.toml`(全文 39 行,关键部分):

```toml
# Configuration file for the "license header checker github action" [HawkEye](…)

# https://github.com/korandoru/hawkeye/blob/badc166…/fmt/src/license/Apache-2.0.txt
inlineHeader = '''
Copyright ${hawkeye.git.fileModifiedYear} International Digital Economy Academy

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
'''

includes = [`*.mbt`]

[git]
ignore = 'auto'
attrs = 'enable'
```

**要点**:
1. 用的是 HawkEye 的 **`inlineHeader` = `Apache-2.0.txt`** 模板,也就是**完整 11 行 Apache 头**(模板本身不含 `#` 前缀,前缀由 HawkEye 按语言注释符自动加)。
2. `includes = ["*.mbt"]` —— **只检查 `.mbt`**(不查 `.md` / `.mbti` / `.toml`)。
3. 年份用 `${hawkeye.git.fileModifiedYear}` = **该文件的 git 最后修改年份**,不是项目起始年。
4. `[git] ignore = 'auto'` + `attrs = 'enable'` = 遵循 `.gitignore` 与 `.gitattributes`。
5. 该模板与上游 **HawkEye 内置 `Apache-2.0`** 完全一致(已比对 `korandoru/hawkeye` 仓库 `hawkeye/src/builtin/headers/Apache-2.0.txt`):

       Copyright {{ props.inception_year }} {{ props.copyright_owner }}

       Licensed under the Apache License, Version 2.0 (the “License”);
       … (同样 11 行)

【实证】core 里每个 `.mbt` 文件头部就是这 11 行 + 一个空行,例如 `<CORE>/array/array.mbt:1-14`、`<CORE>/hashmap/extends.mbt:1-14`。正文从第 15 行开始。

### G.2 两种写法是否都能被认可?Apache-2.0 项目的通行做法【官方明文 + 行业惯例】

**直接回答:不是“都行”,而是“取决于你用什么检查器”。**

| 写法 | HawkEye 默认 | SPDX 规范 | 通行度 |
|---|---|---|---|
| **完整 11 行 Apache 头**(copyright 行 + Licensed under…) | ✅ **唯一被 `Apache-2.0` 模板匹配的形式** | ✅ 接受(它**包含** SPDX 所说的完整声明) | Apache 基金会项目、`moonbitlang/core`、`moonbitlang/moon` 全用这个 |
| **`// SPDX-License-Identifier: Apache-2.0` 两行式**(copyright + SPDX 标识符) | ❌ **默认不匹配**;HawkEye 的 `Apache-2.0` 内置模板里没有 SPDX 行 | ✅ **这是 SPDX 推荐的精简形式** | 现代 Cargo/REUSE/内核风格;Linux 内核、大量 Rust/Go 项目 |

具体到我们的现状(`src/table.mbt:1-2`、`src/lib.mbt:1-2` 等):

```moonbit
// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0
```

**事实判断**:
1. 这两行**完全满足 Apache-2.0 的法律要求** —— Apache-2.0 §4(a) 要求给收到副本的人一份 License,§4(b) 要求修改过的文件带有显著的修改声明,§4(c) 要求保留所有版权、专利、商标、署名声明。用 SPDX 标识符 + 版权行是**被 SPDX 与 REUSE 规范认可的等价做法**。
2. 但 **HawkEye 用 `licenseHeader`/`inlineHeader` 做字面匹配**,它默认的 `Apache-2.0` 模板里没有 SPDX 行,所以 `hawkeye check` 会**判我们不通过** —— 这不是“我们的写法不合法”,而是“检查器的模板不匹配”。
3. **如果想两者兼得**,HawkEye 支持自定义模板,可以把 `inlineHeader` 换成我们这两行:

```toml
# licenserc.toml —— 认可 SPDX 两行式的自定义配置(示意,未在官方仓库出现)
inlineHeader = '''
Copyright (c) ${hawkeye.git.fileModifiedYear} moonbit-multiindex contributors
SPDX-License-Identifier: Apache-2.0
'''
includes = [`*.mbt`]
[git]
ignore = 'auto'
attrs = 'enable'
```

   这样 `hawkeye check` 就能过,同时保留 SPDX。**但要注意**:自行放宽 header 检查会降低许可证元数据的可见性,需自行权衡。
4. **Apache-2.0 项目的通行做法(按主流度排序)**:
   - **完整 11 行头** —— 最常见,尤其是有基金会/公司版权归属时;`moonbitlang/core`、`moonbitlang/moon` 都属此类。
   - **`SPDX-License-Identifier` 两行式** —— 现代项目、单一许可证、无 CLA 时;REUSE/SPDX 官方推荐。
   - 我们的两行式属于第 2 类,**是合规的**;是否改成第 1 类取决于我们是否想开 `hawkeye check`。
5. **我们的 LICENSE/NOTICE 已经到位**:`LICENSE` 是标准 Apache-2.0 全文,`NOTICE` 存在,`moon.mod` 里 `license = "Apache-2.0"`。**这三件事比文件头格式重要得多。**

> **【未核实】** 我**没有实机运行过 `hawkeye check`**(本机未安装 HawkEye)。上述“默认模板不匹配 SPDX 两行式”是从 `licenserc.toml` 的 `inlineHeader` 字面量与 HawkEye 内置模板比对推出的**强推断**,不是实测。若要拍板,请先 `hawkeye check` 跑一次。

---

## §H 我们项目应当照做的清单(可执行)

> 全部条目都在**临时探针工程**(项目完整副本)里实测过,**原仓库未被改动**。
> 探针验证结果:修复后 `moon check` = **0 warnings 0 errors**、`moon test` = **51/51 passed**、`pkg.generated.mbti` **逐字节不变**。

### H.1 【最高优先】14 条 `[0079]` 的根因与修法

**根因**:不是我们写错了什么,而是**所有 `pub`/abstract-public 类型上的 `derive(...)` 和一个手写 `pub impl Show` 都会隐式提升 trait 方法**。`moonc` 逐 `impl` 报一次。

**清单**(来自 `moon check` 实测,共 14 条,分两组):

**A 组:13 条在 `src/lib.mbt`,全部是公开 API 类型** —— 必须用 `extends.mbt`

| # | 位置 | 类型 | 触发的 impl |
|---|---|---|---|
| 1 | `src/lib.mbt:35:10` | `RowId` | `derive(Eq)` → `not_equal, equal` |
| 2 | `src/lib.mbt:35:14` | `RowId` | `derive(Hash)` → `hash, hash_combine` |
| 3 | `src/lib.mbt:35:20` | `RowId` | `derive(Debug)` → `to_repr` |
| 4 | `src/lib.mbt:39:1` | `RowId` | `pub impl Show for RowId` → `to_string, output` |
| 5 | `src/lib.mbt:59:10` | `Conflict` | `derive(Debug)` → `to_repr` |
| 6 | `src/lib.mbt:59:17` | `Conflict` | `derive(Eq)` → `not_equal, equal` |
| 7 | `src/lib.mbt:63:1` | `Conflict[K]` | `pub impl[K : Show] Show for Conflict[K]` → `to_string, output` |
| 8 | `src/lib.mbt:97:10` | `Rejected` | `derive(Debug)` → `to_repr` |
| 9 | `src/lib.mbt:101:1` | `Rejected[K, V]` | `pub impl[…] Show for Rejected[K, V]` → `to_string, output` |
| 10 | `src/lib.mbt:127:10` | `RegisterError` | `derive(Debug)` → `to_repr` |
| 11 | `src/lib.mbt:127:17` | `RegisterError` | `derive(Eq)` → `not_equal, equal` |
| 12 | `src/lib.mbt:142:10` | `UpdateRejected` | `derive(Debug)` → `to_repr` |
| 13 | `src/lib.mbt:142:17` | `UpdateRejected` | `derive(Eq)` → `not_equal, equal` |

> **结论已采纳(2026-10)**:
> - `src/extends.mbt` 已按修法 A 新建,`[0079]` 保持 0 条;
> - `src/json.mbt` 已存在;
> - `src/table_traits.mbt` **没有创建**——这些 promote 全部落在 `extends.mbt`,没有第二个文件需要它。

**修法 A(照抄 core 的三段式,直接可粘贴)**

新建 `src/extends.mbt`:

```moonbit
// Copyright (c) 2026 moonbit-multiindex contributors
// SPDX-License-Identifier: Apache-2.0

// --- promoted: kept as regular methods (blessed public API) ---

///|
pub extend RowId with Eq::{equal}

///|
pub extend Conflict with Eq::{equal}

///|
pub extend RegisterError with Eq::{equal}

///|
pub extend UpdateRejected with Eq::{equal}

// --- deprecated: hidden from the generated interface ---

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend RowId with Eq::{not_equal}

///|
#deprecated("Use Hash::hash via the trait instead", skip_current_package=true)
#doc(hidden)
pub extend RowId with Hash::{hash, hash_combine}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend RowId with @debug.Debug::{to_repr}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend RowId with Show::{to_string, output}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend Conflict with @debug.Debug::{to_repr}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Conflict with Eq::{not_equal}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend Conflict with Show::{to_string, output}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend Rejected with @debug.Debug::{to_repr}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend Rejected with Show::{to_string, output}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend RegisterError with @debug.Debug::{to_repr}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend RegisterError with Eq::{not_equal}

///|
#deprecated("Use `@debug.Debug` instead", skip_current_package=true)
#doc(hidden)
pub extend UpdateRejected with @debug.Debug::{to_repr}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend UpdateRejected with Eq::{not_equal}
```

**⚠️ 配套必改**:上面用了 `@debug.Debug`,`src/moon.pkg` **必须**加 `"moonbitlang/core/debug"`,否则换来 5 条 `[0071] core_package_not_imported`(探针实测,确切报错:`Package `debug` from `moonbitlang/core/` is used without import. This is deprecated.`)。

**⚠️ 关于 `Show::to_string` 的取舍**:官方策略是 `Show::to_string` 仅对有**规范字符串表示**的类型促进;集合类废弃它,改用 `@debug.Debug`。`RowId`/`Conflict`/`Rejected`/`RegisterError`/`UpdateRejected` **都是数据载体,不是集合**,`to_string` 有明确唯一表示 → **两者都可辩护**。探针里我选择了**保守做法(全部 deprecated)**,因为:(a) 我们已有手写 `Show::output`,行为不变;(b) 全部 deprecate 不影响 `.mbti`;(c) 未来若要促进,`pub extend T with Show::{to_string}` 随时可加。**若你想暴露 `RowId::to_string` 作为公开 API,把对应的 `Show::{to_string, output}` 那一行拆成 promoted 段的 `pub extend RowId with Show::{to_string}` + deprecated 段的 `#deprecated Show::{output}` 即可。**

**B 组:1 条在 `src/table_wbtest.mbt:321`,测试夹具 —— 一行修复**

```diff
--- a/src/table_wbtest.mbt
+++ b/src/table_wbtest.mbt
@@ -318,1 +318,1 @@
-struct CountedKey {
+priv struct CountedKey {
   value : Int
   counter : Array[Int]
 } derive(Debug)
```

**这一条正是 §B.3 官方 AGENTS.md 明说的场景(`Test fixtures should be priv`)**。加 `priv` 后:
- `[0079]` 立即消失(类型不再是 public,提升无从发生);
- **不需要任何 `extend`**;
- 但会连带产生一条 `[0001] unused_value: Unused trait implementation`(`derive(Debug)` 变得没人用了)—— **顺手删掉 `derive(Debug)`** 即可(探针实测)。

**⚠️ 检查其它 wbtest 夹具**:`src/property_wbtest.mbt` 里若有同类夹具类型,同样要加 `priv`。批量查:

```bash
grep -nE '^(struct|enum) ' src/*_wbtest.mbt src/*_test.mbt
```

凡是 `_test.mbt`/`_wbtest.mbt` 里以 `struct`/`enum` 开头(无 `priv`)的类型,都是同一个 `[0079]` 根因。

### H.2 【高优先】2 条 `[0029] unused_package` —— `moon.pkg` 依赖分组错误

实测报错(`moon check` 原文):

```
Warning: [0029] src/moon.pkg:2:3  → Unused package 'moonbitlang/core/random'
Warning: [0029] src/moon.pkg:5:3  → Unused package 'moonbitlang/core/test'
```

**根因**:`random` 与 `test` **只在测试代码里用**(`@random.Rand::new()` 在 `property_test.mbt`/`property_wbtest.mbt`;`@test.*` 在多个 test 文件),却被写在**生产 import 块**里。生产编译看不到它们 → 判为未使用。

**修法**(照抄 `<CORE>/sorted_map/moon.pkg` 的三段式),把 `src/moon.pkg` 改成:

```text
import {
  `moonbitlang/core/debug`,
  `moonbitlang/core/sorted_map`,
  `moonbitlang/core/sorted_set`,
}

import {
  `moonbitlang/core/random`,
  `moonbitlang/core/test`,
} for `test`

import {
  `moonbitlang/core/random`,
  `moonbitlang/core/test`,
} for `wbtest`
```

探针实测:此改动同时消灭 2 条 `[0029]` **和** 6 条 `[0071]`(`@random` 原本也是“用了但没在对应分组导入”)。**`moon test` 仍然 51/51 通过。**

### H.3 【中优先】常量命名 —— 我们已符合,建议在文档中固化

现状:`src/table.mbt:34` 的 `const GEN_MAX : Int = 1073741824`、`src/lib.mbt:23` 的 `pub const VERSION : String = "0.1.0"`。**两者都是 `UPPER_SNAKE_CASE`,与 core 实践一致,无需改动。**

建议补进 `CONTRIBUTING.md` 的 Style Guide 表(现在写的是 `UPPER_CASE`,与 `UPPER_SNAKE_CASE` 同义,可精确化):

| Rule | Example | 依据 |
|---|---|---|
| Constants(**无论 `pub` 与否**) | `UPPER_SNAKE_CASE`:`GEN_MAX`、`VERSION` | 【实证】core 196 条 `const` 中 170 条严格符合,0 条小写 |
| `pub const` 仅用于真全局常量 | `VERSION` ✅;`GEN_MAX` 保持私有 ✅ | 【实证】core 仅 15 条 `pub const`,全部是类型边界/数学常数 |

### H.4 【中优先】测试夹具 `priv` —— 写进约定,防止复发

在 `AGENTS.md` 的 Testing conventions 里加一条(可直接用官方原文改写):

```markdown
- Test fixtures in `*_test.mbt` / `*_wbtest.mbt` **must be declared `priv`**.
  An unmodified type declaration is *abstract-public*, so `implicit_impl_as_method`
  (`[0079]`) fires for its derived impls and forces `pub extend` ceremony that has
  nothing to do with the test. With `priv` they need no `extend` at all.
  If a test needs to call a promoted method on one, use the trait form
  (`ToJson::to_json(x)`, `Default::default()`).
  (Source: moonbitlang/core AGENTS.md, "Test fixtures should be priv".)
```

配套自查命令(建议进 `docs/RELEASE_CHECKLIST.md`):

```bash
grep -nE '^(struct|enum) ' src/*_test.mbt src/*_wbtest.mbt   # 期望:无输出
```

### H.5 【中优先】测试命名风格 —— 补句型表

现状:`test "the free stack recycles slots LIFO"`(`src/table_wbtest.mbt:54`)—— **完全符合**官方实证风格。建议把 §E.2 的句型表搬进 `AGENTS.md`/`CONTRIBUTING.md`,特别加两条:
- panic 测试以 `panic ` 开头(`test "panic at"`);
- 不要用 `remove2` / `remove3` 这类数字后缀(老 core 里的反面教材)。

### H.6 【中优先】`inspect` vs `debug_inspect` —— 统一

现状:`CONTRIBUTING.md:186` 的模板用的是 `debug_inspect(t.len(), content="0")`。官方 `CONTRIBUTING.md`/`AGENTS.md` 用的词是 `inspect`,core 里 `inspect` 也是主流。**建议统一到 `inspect`**(内建,无需 import)。

### H.7 【中优先】CI 五步的调整建议

**建议改成七步**(按性价比排序):

```yaml
- name: Format check
  run: moon fmt --check
- name: Type check (deny warnings)      # ← 新增,官方 stable-check.yml:29
  run: moon check --deny-warn
- name: Type check (all targets)        # ← 新增,官方 stable-check.yml:29
  run: moon check --deny-warn --target all
- name: Interface check (mbti up-to-date)
  run: |
    moon info
    git diff --exit-code
- name: Run tests
  run: moon test
- name: Build
  run: moon build
```

**不要加的**(有实测依据):
- ❌ `moon bundle --all` —— **moon 0.1.20260920 上本项目会 panic**(`declared execution output has multiple producers`,`moonbuild-rupes-recta/src/execution_plan/mod.rs:491`),属 moon 的 bug。
- ❌ `warnings = "+unnecessary_annotation"` —— 会与黑盒测试加全限定前缀的约定冲突(30 条 `[0073]`)。
- ❌ `moon build` 可以删 —— 官方 CI **没有**这一步;`moon check` + `moon test` 已覆盖编译。保留也无害。

**可选(取决于你的取舍)**:
- ✅ License header 检查(HawkEye)—— 见 §G.2,需先决定 header 格式。
- ✅ 拼写检查(`crate-ci/typos@v1`)—— 官方放在 `continue-on-error: true` 的 job 里,不阻断。core 用 `_typos.toml` 排除生成文件与字符串字面量。
- ✅ 覆盖率(`moon test --enable-coverage` + `moon coverage report -f summary`)—— 官方同样不阻断。

### H.8 【低优先】`moon.mod` 可加 `warnings`(谨慎)

core 在 `moon.mod` 里开了 7 个警告。**我们建议先只开 1 个**:

```toml
# moon.mod —— 建议追加
warnings = `+missing_doc`
```

理由:`missing_doc`(官方 id 74,`Missing documentation for public definition`)正好对应我们 Public API gets a `///|` doc block 的既有约定,能把约定变成**机器强制**。**加之前先跑 `moon check` 看有多少条**,再决定是否一次性补文档。

**明确不要抄的**:
- `+unnecessary_annotation`(冲突,见 H.7)
- `-implicit_use_builtin`(core 关它是因为 stdlib 特殊;普通库应保持默认 `warn`)
- `+implicit_impl_as_method`(它本来就默认 `warn` 开着,core 显式写出来只是声明意图;我们不需要)

### H.9 【低优先】`README.md` → `README.mbt.md`(可选,收益明确)

如果希望 README 里的 API 示例**永不过期**,可以:
1. 复制 `README.md` 为 `src/README.mbt.md`(放包目录内,跟随包级 `moon test`);
2. 每个示例代码块标 `mbt check`,块内以 `///|` + `test { … }` 开头;
3. 示例调用一律用 `@aurasuisui/multiindex.` 前缀(文档测试是黑盒);
4. `moon.mod` 的 `readme = "README.md"` **保持不动**(mooncakes 页面仍读根 README)。

官方 `README.mbt.md` = 64 个(每包一个),是明确的最佳实践;但**这是额外工作量,不建议在 v0.1.0 前做**。

### H.10 【可选】错误类型统一为 `suberror`

现状:`src/lib.mbt:57,124,139` 用的是 `pub enum Conflict[K]` / `pub enum RegisterError[K]` / `pub enum UpdateRejected[K, V]`。core 的 15 个错误类型**全部**是 `suberror`。

**风险提示**:改成 `suberror` 会改变 `.mbti` 与 API 语义(可用 `raise` 抛出),`Result[T, E]` 的用法可能需要调整。**建议评估后再定,不要顺手改。** 另外 `UpdateRejected` 不以 `Error` 结尾,与 `RegisterError` 不一致,是个小的命名瑕疵。

---

## §I 未核实 / 存疑

| # | 事项 | 状态 | 说明 |
|---|---|---|---|
| 1 | `hawkeye check` 对本项目两行 SPDX 头的**实际判定** | **【未核实】** | 本机未装 HawkEye。§G.2 的结论是从 `licenserc.toml` 的 `inlineHeader` 与 HawkEye 内置 `Apache-2.0.txt` 逐行比对推出的强推断,未实机验证。**拍板前请实跑一次。** |
| 2 | `typos` 检查对我们代码的实际误报率 | **【未核实】** | 官方用 `_typos.toml` + `extend-ignore-re` 排除字符串字面量。我们的标识符(`multiindex`、`RowId`、`gens`、`chokepoint`)可能有误报,未测。 |
| 3 | `moon check --target all` 在本项目的实际结果 | **【未核实】** | 探针只跑了默认后端。官方 `stable-check.yml:29` 用 `--target all`。**JS/native 上 `Int` 是 64-bit 还是 32-bit 会影响我们对 `GEN_MAX` / `1 << 30` 的推理**,建议单独跑一次。 |
| 4 | `+missing_doc` 打开后我们会有多少条 | **【未核实】** | 未在探针里开这个警告。 |
| 5 | `moon bundle --all` panic 是否已在更新的 moon 里修掉 | **【未核实】** | 官方提示上报 `moonbitlang/moon`(issue 模板)。本地版本 `moon 0.1.20260920`。未查 issue tracker。 |
| 6 | 官方 `CONTRIBUTING.md` 是否有常量命名的隐藏处 | 【已核实为无】 | 96 行全文通读,只有 `Naming conventions` 一节的 3 条(function / type parameters / type names),无常量条目。**§A.3 的“官方没提”是确定结论,不是搜索遗漏。** |
| 7 | `pub(all)` / `pub(open)` 的完整语义与推荐用法 | 部分 | 实证 core 里 46 处,但官方 `CONTRIBUTING.md` 未明文规定何时用哪个。**不展开。** |

---

## 附:本次调研的验证方法与可复现命令

**证据采集(全部在本机执行,可复现)**:

```powershell
# 1. 命名统计(常量)
Select-String -Path "$env:USERPROFILE\.moon\lib\core\**\*.mbt" -Pattern '^\s*(pub\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*(:[^=]*)?='

# 2. 文件类型计数
Get-ChildItem "$env:USERPROFILE\.moon\lib\core" -Recurse -File -Filter '*.mbt*' |
  Group-Object { switch -Regex ($_.Name) {
    '_wbtest\.mbt$' {'_wbtest.mbt'}; '_test\.mbt$' {'_test.mbt'}
    'README\.mbt\.md$' {'README.mbt.md'}; 'deprecated\.mbt$' {'deprecated.mbt'}
    'extends\.mbt$' {'extends.mbt'}; 'types\.mbt$' {'types.mbt'}
    '\.mbti$' {'mbti'}; default {'other'} } } | Sort-Object Name

# 3. 警告编号表(权威,来自本机 moonc)
moonc check -warn-help

# 4. 官方 CI 检查项
Select-String -Path "$env:USERPROFILE\.moon\lib\core\.github\workflows\*.yml" -Pattern 'run:|uses:'
```

**探针验证(已执行,已清理)**:
1. `Copy-Item moonbit-multiindex _tmp-style-probe -Recurse`(副本,原仓库不动)
2. 应用 §H.1 + §H.2 的改动
3. `moon check` → `0 warnings 0 errors`(修复前:`16 warnings`)
4. `moon test` → `Total tests: 51, passed: 51, failed: 0`
5. `git diff src/pkg.generated.mbti` → **无差异**(公开 API 未变)
6. `Remove-Item _tmp-style-probe -Recurse -Force`

> **原仓库未被本调研改动**。调研期间 `src/index.mbt`/`src/table_api.mbt` 已有其它会话的在制改动(283 insertions),`moon check` 的**警告行号**可能因这些改动而漂移;§H.1 的清单基于调研当时的工作树状态。
