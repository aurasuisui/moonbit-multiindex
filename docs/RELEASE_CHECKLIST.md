# RELEASE_CHECKLIST.md — 发布门禁

> **每次 `moon publish` / bump `moon.mod` 版本之前,逐项跑到全绿。**
> 勾选结果记一行到 `CHANGELOG.md`。任何一项不绿 = 不发版。

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
