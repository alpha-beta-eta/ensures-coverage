---
name: ensures-coverage
description: 用ensures-coverage检查Verus项目 (如vostd) 中exec/proof函数的postcondition是否提及了每个输出 (返回值, `#[verus_spec]`返回元组的分量, `&mut`参数), 并审阅报告. 用户要求检查或审阅Verus规格是否写全, "ensures覆盖", 审一个模块/文件/PR的规格, 或者要运行ensures-coverage的check/report, 读它的结果文件或报告时使用.
---

# 使用ensures-coverage审阅Verus规格

工具目录 (下文记为`$EC`): 本skill所在仓库的根目录, 即`.claude/skills/ensures-coverage/`的上三层, 其中应有`main.rkt`. skill被复制到了别处 (如`~/.claude/skills/`) 时上三层不是工具目录, 这时问用户. 被检查的项目检出记为`$SRC`.

第一次在会话中使用时, 先读`$EC/README.md` (怎样运行, 怎样读结果, 警告的含义); 对某条规则的确切含义有疑问时查`$EC/design.md` (设计结论, 注意, 经验). 本skill只讲流程和判断, 不重复它们.

工具只给出信号: "某个输出没有被postcondition提及". 是不是缺陷, 由你在阅读源码后判断, 并写明理由.

## 1. 先核对Verus版本和VIR

VIR的格式没有版本号, 完全跟着Verus走, 而且改得很频繁. 格式对不上时, 工具不会出错, 只会给出错误的结果. 所以**每次使用前**都要核对.

vostd总是跟着最新的Verus验证, 所以主要的风险不是Verus太旧, 而是**vostd升级Verus之后, 新版本落在已验证的范围之外**: 工具读的部分平均一两个月就会变一次. 每次看到项目的Verus比README表中最新的一行还新, 就按下面第2, 3步核对; 核对通过后, 提醒用户把新版本加进README的表. 审PR时merge-base可能比head旧, 需要更早的Verus, 这时head和merge-base要分别核对.

1. 查项目所用的Verus:

   ```bash
   $SRC/tools/verus/source/target-verus/release/verus --version
   git -C $SRC/tools/verus log -1 --format='%H %cd' --date=short
   ```

2. 用项目的Verus跑fixture测试 (`$EC/README.md`"测试"一节): `VERUS=... VERUS_Z3_PATH=... $EC/tests/run.sh`. 失败时**停下来告诉用户**, 附上diff, 不要用这份结果下结论; 修工具时以让测试恢复通过为目标, 不要随手`--update`.
3. 与`$EC/README.md`"Verus版本"一节的表比较.
   - 在表中: 可以用.
   - 不在表中: fixture测试通过是前提. 再按README中的命令, 对表中最近的提交`git diff` `source/vir/src/ast.rs`, `printer.rs`, `def.rs`和`builtin_macros/src/syntax.rs`, 逐项对照README列出的"本工具依赖的VIR名字" (fixture只覆盖它写到的写法). 有变化就**停下来告诉用户**, 说明变了什么, 不要用这份结果下结论. 没有变化时可以继续, 但在汇报中注明"该Verus版本未经验证, 已对照ast.rs的diff".
   - 两个提交不在同一个仓库里时 (例如一个来自asterinas/verus的另一个检出), 建一个临时的bare仓库, 把两边的提交都`git fetch`进去再diff, 不要改动现有的仓库.
   - 这一步不能省: 用2026-09-03的Verus导出的VIR, 返回值字段叫`:ret`而不是`:outer_ret`; 旧版工具照常结束, 不报警告, 只是一条返回值的报告也没有 (现在会警告, 但别的变化未必都能被警告抓住).
   - 有条件时 (表中某个提交的结果还在), 用新Verus对那个提交重跑, 与旧结果比较. 这是最可靠的核对.
4. 跑`check`时看stderr:
   - `the VIR format may have changed`: 结果不可信, 停下来告诉用户.
   - 源文件是绝对路径, 或在`$SRC`下找不到: 导出目录或`$SRC`给错了, 改正后重跑.
   - `item-index: ... parse error`: 这些文件中的函数没有源码行, 按行选函数时会漏掉. 按README改用项目自带的`verus_syn`重新编译`item-index`.
   - stdout上"N of them not found by the source parser": vostd的`ostd`约200个是正常的 (宏和`derive`生成的). 远多于此时, 源码或解析器与VIR不符.
5. 核对源码: `$SRC`必须与导出VIR时的提交一致. 用`git -C $SRC status --short`看有没有未提交的改动 (以前审PR时就因为工作区里留着改动, 有13个函数对不上). 有改动时用`git archive <commit> ostd verified_libs | tar -x -C <dir>`取一份干净的源码作为`$SRC`.

## 2. 先查全部函数, 再选出要审阅的

- 导出**整个crate**的VIR (命令见第6节), 对全部函数跑`check`, 得到一份结果文件; 然后用选择器`report`出要看的部分. 不要试图只检查一部分函数: 检查只要几秒, 而一份完整的结果可以按不同选择器反复使用.
- 每个要审阅的crate各导出一份VIR, 一起传给`check` (用逗号分隔). 例如改了`vstd_extra`的PR, 要同时导出`ostd`和`vstd_extra`.
- 选哪些函数是审阅者的决定, 不由工具推断. 常见的选法:
  - 一个模块或文件: `(module "^ostd::mm::frame")`, `(file "^ostd/src/mm/tlb[.]rs$")`.
  - 用户指定的函数: 逐个写成`(name "...")`放进文件, 传`@文件`.
  - 一个PR: 在head上跑一遍完整的`check`, 用`$EC/contrib/pr-functions.rkt`选出与diff有交集的函数, 以及声明被改动的trait方法实现 (用法见README"审PR"; 再给出merge-base的结果时也列出新增的函数). 读一遍PR的diff, 确认清单合理; 清单外但PR改了其规格依赖的函数 (如被调用的下层函数), 自己补进来.
- 在汇报中写明用了哪个选择器, 选中了多少函数.
- 在Windows上用Git Bash运行, 或者把选择器写进文件; PowerShell会弄乱选择器中的双引号.

## 3. 逐条审阅报告

对每条报告, 打开源码 (报告给出了位置), 读函数的签名, `requires`/`ensures`, 文档注释, 必要时读函数体, 然后判定为下面四类之一, 并写一句理由:

| 判定 | 含义 | 典型情况 |
|---|---|---|
| 缺陷 | 调用者需要而规格没给, 而且给得出 | 同级函数都给了 (`try_lock`有而`lock`没有); 下层函数给了而这一层没转发; 后续调用要求的前提 (如`wf`, `inv`) 在调用后无从得知, 导致API只能调用一次; 文档写明了的返回值含义 |
| 很可能缺陷 | 调用者多半需要, 但要确认 | 返回值与参数的关系 (如`r.level == level`), 升级/降级前后值不变 |
| 有意不承诺 / 受抽象所限 | 当前的抽象写不出来 | 没有值的模型 (锁, 守卫); 数据在不透明的结构后面; 同级函数一致地不承诺 |
| 不是问题 | 调用者其实知道, 或不需要 | 经由返回值描述了`&mut`参数 (返回值借用它); 调用后马上销毁; 状态全在ghost模型中; `Debug::fmt` |

判断时要问的:

- **调用者需不需要这个值?** 用grep找已验证的调用者, 看它们之后用了这个值的什么性质. 没有调用者时, 按文档和API的正常用法设想一个.
- **是否经由别处描述了?** 返回值借用了`&mut`参数, 或者规格描述了某个ghost模型而不是这个值本身 (design.md结论10, 注意1).
- **标注**: "非pub"表示现有调用者都已验证通过, 报告更可能是"没被用到"; "只有类型不变量"表示调用者只知道值合法; "postcondition来自trait声明"时要决定补在实现上还是声明上; `external_body`的规格是被信任的.
- **能不能写出来?** 给出建议补的`ensures` (例如`final(self).wf(...)`, `r == *self`, `*final(x) == *old(x)`). 写不出来时说明缺什么 (如需要先加一个view或ghost模型).

**写调用者确认.** 对判为缺陷或很可能缺陷的报告, 尽量按真实用法写一个已验证的调用者: 调用该API, 再证明调用者接下来需要的性质 (或接着调用下一个API). 证不下去就确认了缺陷; 再补上建议的`ensures`, 确认调用者能证过, 函数本身也仍能验证. 这比只读规格可靠. 调用者和修改写在项目的副本或单独的分支中, 不要改用户的工作区; 汇报时给出diff.

**没有报告不等于规格完整.** 只要提及一次就算提及, 哪怕只有`final(x).inv()`, 或只在某个分支中, 或在条件恒假的条件式`ensures`中 (design.md注意2). 审阅选中的函数时, 对没有报告的函数也要读规格, 而且这一步往往发现更多: 审`mm::frame::unique`时工具只报了2条, 读规格又找出几处更严重的. 重点看:

- 返回的值或owner有没有`inv` (或同类的良构性), 以及后续API要求的前提能否从ensures推出;
- 修改了共享状态 (如`regions`) 的函数, 有没有说明其它部分不变 (框架条件); 同级函数给了而这里没给的, 多半是缺陷;
- 结果与参数的关系 (同一帧, 同一个值, 计数变成了多少);
- trait实现报告中"按trait方法合并"的实现: 它们的规格全部来自声明, 声明是条件式`ensures` (如vstd的`obeys_from_spec() ==> ...`) 时, 要查条件在这个类型上是否成立.

## 4. 同时留意工具看不到的问题

阅读中遇到下面这些, 记在汇报的单独一节 ("超出本工具范围的发现"), 不要混进工具的报告:

- 按值传入的tracked owner在函数结束后不交还, 调用者因此失去这部分ghost状态.
- 条件式`ensures` (`obeys_xxx() ==> ...`) 的条件在所有实现中都为假, 规格等于没写; 或者默认方法的`requires`在某个实现中恒假, 方法无法调用.
- 文档, 规格与实现三者不一致 (例如规格和实现错在同一处, 验证照样通过).
- `external_body`函数的`ensures`对来自未验证状态的值断言了性质.
- 经由`PCell`, 原子量, 全局状态等签名之外的修改 (design.md注意5).

这些在vostd中都出现过, 而且往往比"未提及"更严重.

## 5. 汇报

汇报写给维护者看, 要自足:

1. **背景和方法**: 检查了什么, 工具的原理一句话, Verus版本 (`verus --version`) 及是否在已验证的表中, 项目提交, 选择器和选中的函数数.
2. **结论**: 各判定的条数; 先列缺陷和很可能缺陷, 每条写明函数, 位置 (`file:line`), 未提及的输出, 判定理由, 建议补的`ensures`, 以及是否已用调用者确认.
3. **有意不承诺 / 不是问题**: 按原因归类, 简述即可.
4. **超出本工具范围的发现** (第4节).
5. **复现**: 导出VIR, `check`, `report`的完整命令; 写过的调用者和修改的diff.

区分工具给出的事实 ("`self`没有被postcondition提及") 和你的判断 ("这是缺陷, 因为..."). 没有核实过的说法要注明.

## 6. 运行Verus的经验

以下来自审vostd的8个PR时踩过的坑.

**导出VIR.**

- 用`--no-verify`只导出VIR, 不做验证, 每个crate约20到40秒:

  ```bash
  cargo dv focus --package ostd -- --no-verify --log vir --log-dir <log-dir>
  ```

  验证 (确认项目在这个提交上能通过) 另外做. 工具假定规格是验证过的; 项目验证不过时, 先把这一点告诉用户.
- `dv`的命令行随vostd的版本而变: 2026年10月的vostd用`cargo dv focus --package ostd`, 9月的用`cargo dv focus --targets ostd`. 报错`unexpected argument`时先看`cargo dv focus --help`.
- **命中cargo-verus的缓存时, `--log vir`什么也不写, 也不报错**: 照样退出码0, 打印"Verified ostd ... in 0.5s", 但`<log-dir>`根本不会被创建. 只改`--log-dir`不会让缓存失效 (已实测). 所以:
  - 每次导出用一个新的 (或清空的) `<log-dir>`, 按提交和crate命名 (如`logs/<commit>-ostd`); 导出后确认`<log-dir>/crate.vir`存在, 且修改时间是本次的. 不存在就是命中了缓存.
  - 强制重跑: 删掉该crate的fingerprint, 位置是`<target>/verus-partial/<triple>/debug/.fingerprint/<crate>-<hash>/` (`<target>`是`CARGO_TARGET_DIR`, 没设时是`$SRC/target`; `<triple>`如`x86_64-unknown-none`). 只删这个crate的, 注意`ostd-<hash>`与`ostd-pod-<hash>`等是不同的crate. `cargo clean -p ostd`删不到它. 删掉后重跑, vostd的`ostd`约20秒写出约100MB的`crate.vir`.
  - 删除时先用`ls -d`列出目录, 再按列出的字面路径`rm -rf`. 写成`rm -rf $(ls ...)`会被Claude Code的安全检查拦下 (目标无法事先检查).
- 缓存和结果文件也按提交命名 (如`<commit>-ostd.fasl`, `<commit>.results`), 不要让不同提交的文件混在一起.
- 改了别的架构的代码时, 用`--target` (如`--target loongarch64-unknown-none-softfloat`) 导出, 否则`cfg`掉的代码不在VIR中. head和merge-base要用同一个target比较, 否则"new"会包括该架构的全部代码.

**确认真的验证了.**

- cargo-verus只在源码内容变化时重新验证. 只`touch`文件, 只改变`--verify-only-module`或`--log-dir`参数, **或者上一次是`--no-verify`的运行**时, 它直接用缓存, 照样打印"Verified". 最后一种最危险: 用`--no-verify`导出VIR之后紧接着验证一个模块, 0.5秒就"Verified", 实际一个函数也没验证 (已实测). 判断方法: 本次输出中有`verification results:: N verified, M errors`一行; 只用了零点几秒, 没有这一行的"Verified"是缓存. 要强制验证, 按上面的办法删掉fingerprint, 或者改动源码内容.
- 写client时, 先放一个必定失败的断言 (如`assert(false)`) 跑一遍, 确认这段代码确实被验证了 (应报`1 errors`, 退出码非0), 再换成真正的client. 每次改动都改变了源码内容, 所以会重新验证; 把文件恢复原样后再跑, 也会重新验证一遍 (都已实测). 内容不变地再跑一次则命中缓存.
- dv默认最多报告5个错误 (`--multiple-errors=5`); 要看全部失败的函数, 加`-e 20`: `cargo dv focus --package ostd -e 20 -- --verify-only-module <module>`. 模块名不带crate前缀 (`mm::frame::unique`, 不是`ostd::mm::frame::unique`).
- 耗时: 一个小模块约20秒, 整个crate要几分钟. 只用零点几秒就"Verified"的, 是缓存而不是真的验证了.
- `resource limit (rlimit) exceeded`可能不稳定: 跑两次确认, 并在merge-base上跑同一个模块对比. 它是"该模块验证不过", 不是工具的问题, 单独汇报.
- 验证整个crate时放到后台运行, 输出重定向到文件 (如`logs/<name>.out`), 之后从文件中找`verification results`和`error`.

**版本和检出.**

- 审阅期间PR可能被rebase. 开始时记下head提交, 汇报前再看一次; 变了就重跑并在汇报中写明. rebase到新main后可能需要更新的Verus, 这时head和merge-base都用新的Verus检查, 并重新做第1节的核对.
- 旧提交在新Verus或新vstd上可能编译不过 (例如`vstd_extra`的外部规格与vstd重复). 先弄清原因; 只能替换不在PR改动中的文件来绕过时, 在汇报的"运行上的偏差"一节写明替换了什么.
- 多个worktree可以经由符号链接共用一份已编译的`tools/verus`, 省去重复编译; 但要确认它正是这个提交需要的Verus (`verus --version`). 在Windows上给每个worktree设一个短的`CARGO_TARGET_DIR` (如`D:/pr/t-<name>`), 避免路径过长, 也避免几个worktree共用构建目录.
- client放在被审模块的文件末尾, 写在worktree中, 不提交. 汇报中给出可依次打上的diff: 先只有client (显示失败), 再加上修改 (显示通过), 并用表格列出每个client在merge-base, PR head, PR head加修改上的结果. 修改之后, 被修改的函数本身也要重新验证通过.
- `contrib/pr-functions.rkt`的"new"按模块和函数名比较, 函数改名或移动模块时也算new; 读清单时留意这一点.

## 不要做的

- 不核对Verus版本就使用结果, 或者忽略`check`的警告.
- 看到"Verified"就认为验证通过, 而不确认本次输出中有`verification results`一行.
- 导出VIR后不确认`crate.vir`存在且是本次写出的, 就拿`<log-dir>`里的东西 (可能是旧的, 或者根本没有) 去检查.
- 用与VIR不一致的源码 (工作区里有未提交改动) 跑`check`.
- 只检查一部分函数, 或者手改结果文件.
- 把每条报告都当成缺陷, 或者把没有报告当成规格完整.
- 为了消除报告而写`ensures true`之类的空话; 建议补的`ensures`必须是调用者用得上, 且函数证得出的.
- 未经用户同意修改项目的工作区或推送任何东西.
