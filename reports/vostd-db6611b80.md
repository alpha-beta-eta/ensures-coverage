# vostd main的ensures-coverage检查: 明确的缺陷与旧报告的跟进

> 对象: vostd (`asterinas/vostd`的`main`, [`db6611b80`](https://github.com/asterinas/vostd/tree/db6611b8066458efe90f0bce701cccfd046ea833), 2026-11-10, #897合入后) 中`ostd`和`vstd_extra`的全部exec函数和proof函数.
> 时间: 2026-11-11.

## 1. 说明

在当前的`main`上, 本工具新找到**3处明确的缺陷** (第2节), 其中N1和N2的读者一侧的修补已用Verus验证. 上一份报告 (`36e90fe19`, 2026-10-26) 的21个问题中, LinkedList的9个已经修好, 其余12个仍在, 包括已验证过修补的D19 (第3节).

- **对象.** `ostd`和`vstd_extra`两个crate的全部exec函数和proof函数, pub和非pub, 共2283个. 上一份报告只看了`ostd::mm`和`ostd::sync`的pub exec函数.
- **方法.** 工具 (`ensures-coverage`) 报告postcondition (`ensures`和`returns`) 没有提及的输出: 返回值, `#[verus_spec]`返回元组的分量, 调用后的`&mut`参数. 这次共249条. 本文只收录逐条读过源码, 能指出具体后果的.
- **什么算明确.** 这个输出对调用者有用, 规格写得出来, 而且有证据: 下层函数已经承诺了它, 文档写明了它, 或修补已经用Verus验证. 有意不承诺, 受抽象所限, 或经由别处描述了的, 都不收录.
- **Verus.** 检查和验证用的都是vostd自带的`0.2026.11.08.68d8005`. vostd的CI当时用的是`0.2026.11.10.3d25756`, 两个版本上工具的fixture测试都通过.
- **后果的范围.** 下文的缺陷目前都**没有已验证的调用者**受影响, 后果是"已验证代码无法接着使用这个API", 不是"已有证明出错".

链接都固定在`db6611b80`上, 下文用`L`表示行号.

## 2. 新发现的明确缺陷 (3处)

三处都不在上一份报告的范围内 (proof函数, `vstd_extra`). 修补都只需在ensures中加一两行, N1和N2的读者一侧已用Verus验证.

| 编号 | 函数 | 未提及的输出 | 修补 | 验证 |
|---|---|---|---|---|
| N1 | `ExclusiveGhost::update` | 返回值`res` | `res == old(self).view()` | 已验证 |
| N2 | `VmSpaceOwner::activate_reader` / `activate_writer` | `self` | reader: `*final(self) == *old(self)`; writer见下 | reader已验证, writer未验证 |
| N3 | `<[T]>::as_mut_ptr`的`assume_specification` | `s` | `*final(s) == *old(s)` | 可信规格, 无需证明 |

### N1 `ExclusiveGhost::update`: 返回的旧值未被提及

**位置.** [`vstd_extra/src/resource/ghost_resource/excl.rs` L60-L70](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/verified_libs/vstd_extra/src/resource/ghost_resource/excl.rs#L60-L70)

**现状.** 文档写着"Updates the ghost value and returns the old value", ensures只有`final(self).id() == old(self).id()`, `final(self).view() == value`, `final(self).wf()`. 它调用的`update_helper`已经保证了`res == old(r).value()->Exclusive_0`, 这一层没有转发.

**后果.** 调用者拿到的旧值不受任何约束. 目前用到`ExclusiveGhost`的是`ostd/specs/task/cpu_core.rs`和`vstd_extra/src/scheduler_thread_view.rs`, 都没有调用`update`.

**修补和验证.**

```diff
             final(self).wf(),
+            res == old(self).view(),
```

`cargo dv focus --package vstd_extra -- --verify-only-module resource::ghost_resource::excl`: `5 verified, 0 errors`. 对照: 临时加上推不出的`res != old(self).view()`, 报`postcondition not satisfied` (`4 verified, 1 errors`).

### N2 `VmSpaceOwner::activate_reader` / `activate_writer`: `self`调用后的状态未被提及

**位置.** [`ostd/specs/mm/vm_space.rs` L314-L334](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/specs/mm/vm_space.rs#L314-L334) (`activate_reader`), [L389-L409](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/specs/mm/vm_space.rs#L389-L409) (`activate_writer`). 文件开头 (L68) 把它们列为激活读写者的接口.

**现状.** 两者都是`tracked &mut self`, requires `old(self).inv()`和`old(self).active`, ensures只描述`owner_r` / `owner_w`, 不提`final(self)`.

- `activate_reader`只借用`self.mem_view`, 并不修改`self`.
- `activate_writer`用`tracked_split`把`self.mem_view`切成两块, 左半给`owner_w`, 右半留在`self`中.

**后果.** 调用一次之后, 调用者推不出`self.inv()`和`self.active`, 所以**不能再激活第二个读者或写者**. 目前这两个函数没有调用者.

**修补和验证.**

- `activate_reader`: 加`*final(self) == *old(self)`. `--verify-only-module mm::vm_space::vm_space_specs`: `6 verified, 0 errors`; 对照 (临时加`final(self).active != old(self).active`) 报`postcondition not satisfied`.
- `activate_writer`: 至少应当给出`final(self).active == old(self).active`, 以及`final(self).mem_view`是切剩的右半块. 能否保证`final(self).inv()`, 取决于`mem_view_wf`对切分后的视图是否仍然成立, **没有验证**.

### N3 `<[T]>::as_mut_ptr`的可信规格: `s`调用后的状态未被提及

**位置.** [`vstd_extra/src/external/slice.rs` L16-L18](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/verified_libs/vstd_extra/src/external/slice.rs#L16-L18)

**现状.** `assume_specification<T>[ <[T]>::as_mut_ptr ](s: &mut [T]) -> (r: *mut T)`只保证`r == as_mut_ptr_spec(s)`.

**后果.** 取一次指针之后, 调用者对切片的内容和长度一无所知, 而标准库的`as_mut_ptr`并不修改切片. 已验证代码中的调用者 (如[`io.rs` L1341](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/src/mm/io.rs#L1341)的`read_slice`) 目前都不需要调用后的切片, 所以后果是潜在的.

**建议.** 加`*final(s) == *old(s)`. 这是可信规格, 不需要证明; 它只是把标准库的行为如实写出, 不引入新的假设.

## 3. 上一份报告的跟进

21个问题中9个已修, D6看似修了但问题仍在, 其余11个在当前`main`上都仍被报告. 我在开着的PR中没有找到修它们的改动.

| 编号 | 函数 | 现状 | 说明 |
|---|---|---|---|
| D1-D4 | `LinkedList::push_front` / `pop_front` / `push_back` / `pop_back` | 已修 | #866, #868补上了`final(self).wf_region(..)`, pop改为借用`&mut owner`并归还`frame_owner` |
| D5 | `LinkedList::contains`的返回值 | 已修 | #875补上了`returns`, 与建议一致 |
| D6 | `LinkedList::contains`的`self` | **仍在** | 见下 |
| D7, D8 | `LinkedList::cursor_mut_at` | 已修 | #866, #875 |
| 3.1 | `push_back`的插入位置 | 已修 | ensures改为`insert(old(owner).list.len(), ..)` |
| 3.2 | `cursor_mut_at`的ghost下标 | 已修 | 改为用`meta_to_index(..) == frame_to_index(frame)`比较 |
| D9 | `UniqueFrame::try_from_shared`的返回值 | 未修 | ensures仍只有`slots`和`slot_owners.dom()` |
| D10, D11 | `VmReader::has_remain`, `VmWriter::has_avail` | 未修 | 仍无ensures. #899只改了读写视图, 没有动这两个函数 |
| D12, D13 | `VmSpace::default` | 未修 | 仍无ensures; 签名中新增的`guards`同样未被提及 |
| D14 | `VmSpace::new`的返回值 | 未修 | `create_user_page_table`仍丢弃新页表的owner |
| D15-D18 | `VmSpace::cursor` / `cursor_mut` | 未修 | ensures仍只有`c.inv()`. #908只把泛型`G: InAtomicMode`换成了`AsAtomicModeGuard` |
| D19 | `CursorMut::map`的`tlb_model` | **未修, 修补仍然成立** | 见下 |

### D19: 一行修补在当前`main`上仍然可证

[`vm_space.rs` L838-L860](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/src/mm/vm_space.rs#L838-L860)的`map`仍然要求`old(tlb_model).inv()`, 却不保证调用后仍然成立, 所以map之后既不能再map, 也不能unmap. 在`db6611b80`上重新验证了上一份报告的修补:

```diff
             final(self).pt_cursor.0.invariants(*final(cursor_owner), *final(regions), *final(guards)),
+            final(tlb_model).inv(),
             old(self).map_item_ensures(
```

`cargo dv focus --package ostd -- --verify-only-module mm::vm_space`: `34 verified, 0 errors`, 与`36e90fe19`上的结果相同. **建议直接合入.**

### D6: `contains`仍会破坏空表的`wf`

#875之后工具不再报告这一条, 因为`returns`中出现了`final(self).list_id`, 而"提及一次就算提及". 但问题本身没有解决:

- `wf`要求`self.list_id == owner.list_id` ([`linked_list_owners.rs` L1032-L1040](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/specs/mm/frame/linked_list/linked_list_owners.rs#L1032-L1040)).
- `contains`现在以`&LinkedListOwner`借用`owner`, 而`lazy_get_id`在`list_id == 0`时仍给`self.list_id`写入新的非零id, `owner.list_id`仍为0.
- ensures和returns都没有给出`final(self).wf(*owner)`.

所以对一个`list_id`为0的空表调用`contains`之后, `wf`**实际上不成立**, 这个表不能再被验证地使用. 建议同上一份报告: `list_id == 0`时同步更新`owner.list_id` (`owner`改为`&mut`), 或放宽空表的`wf`, 再补`final(self).wf(*final(owner))`.

## 4. 需要注意的地方

下面几点不是"未提及"的缺陷, 但会影响上面的修补是否真正有意义, 或者会让人误读工具的结果.

- **D15-D18要转发的事实, 最终是假定的.** 底层`PageTable::cursor`承诺的游标`invariants`, 来自[`locking::lock_range`](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/src/mm/page_table/cursor/locking.rs#L254-L264)中的两处`assume(...)`. 补上D15-D18之后, `VmSpace`的游标就能用了, 但它的前提仍然依赖这两处假设.
- **`get_kernel_page_table`的可信规格对任意的`guards`断言了解锁.** 这个`external_body`函数 ([`kvirt_area.rs` L240](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/src/mm/kspace/kvirt_area.rs#L240)) 保证`guards.unlocked(内核根节点)`, 不论调用者传入的`guards`是什么. 调用者若正持有内核根节点的锁, 同一个`guards`就同时被认为加锁和未加锁. 是否能推出矛盾, **没有核实**. 也正是这条规格, 使`create_user_page_table`, `VmSpace::new`, `KVirtArea::map_frames`不提`final(guards)`目前不影响调用, 所以本文没有把它们列为缺陷.
- **embedding层的镜像仍在假设exec规格没有的事实.** 上一份报告指出的[`vm_space_new_embedded`](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/specs/mm/embedding/vm_space.rs#L35-L40), [`vm_space_cursor_embedded`](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/specs/mm/embedding/cursor.rs#L77-L90), [`vm_space_cursor_mut_embedded`](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/specs/mm/embedding/cursor.rs#L131-L132)和[`cursor_mut_map_embedded`](https://github.com/asterinas/vostd/blob/db6611b8066458efe90f0bce701cccfd046ea833/ostd/specs/mm/embedding/cursor.rs#L302-L303)都还在, 对应的exec规格 (D14-D19) 都还没有修. 修好exec规格后, 建议把这些axiom与它们重新对照.
- **DMA的取值函数不算缺陷.** `DmaStream`和`DmaCoherent`的`daddr`, `paddr`, `nframes`, `nbytes`, `direction`共报告9条, 规格与`36e90fe19`时相同. 它们受抽象所限: `RwArc::wf()`藏起了内部的segment (#883在`DmaStreamSlice::inv`的注释中也这样写), 外层说不出返回值是多少.
- **"没有报告"不等于规格完整.** D6就是例子. 工具只看输出有没有被提到, 提到一次就算, 哪怕只提到了一个字段.
- **这次没有审阅的.** 没有postcondition的函数上的205条报告, 以及`mm`, `sync`之外的模块 (`arch::kernel` 23条, `util::either` 5条等), 都还没有逐条读. 按上一份报告的经验, 其中约四分之一可能是缺陷.
- **工具本身的变化.** 自上一份报告以来, 工具适配了Verus `0.2026.11.08`的VIR格式, 并修正了一处遗漏: 以前不扫描`returns`子句, 只写在`returns`里的`final(x)`会被误报为未提及. 在当前`main`上, 这只影响`LinkedList::contains`一条.

## 5. 复现

环境: vostd `db6611b80`, vostd自带的Verus `0.2026.11.08.68d8005`, WSL的Ubuntu 24.04. 工具是`ensures-coverage`的当前工作区 (含`returns`的修正). 下文`$EC`是工具目录, `$SRC`是vostd检出.

1. fixture测试 (确认工具与这个Verus的VIR格式一致):

    ```bash
    VERUS=$SRC/tools/verus/source/target-verus/release/verus VERUS_Z3_PATH=$SRC/tools/verus/source/z3 $EC/tests/run.sh
    ```

2. 在`$SRC`中导出两个crate的VIR (每次用新的目录, 导出后确认`crate.vir`存在):

    ```bash
    cargo dv focus --package ostd -- --no-verify --log vir --log-dir logs/ostd
    cargo dv focus --package vstd_extra -- --no-verify --log vir --log-dir logs/vstd_extra
    ```

3. 检查并生成报告:

    ```bash
    racket $EC/main.rkt check logs/ostd/crate.vir,logs/vstd_extra/crate.vir main.results $SRC
    racket $EC/main.rkt report main.results main.md all
    ```

    应得到2283个函数, 249条报告, stderr上没有警告.

4. 验证修补: 在一份单独的检出中分别加上N1, N2 (reader), D19的一行, 然后:

    ```bash
    cargo dv focus --package vstd_extra -- --verify-only-module resource::ghost_resource::excl
    cargo dv focus --package ostd -- --verify-only-module mm::vm_space::vm_space_specs
    cargo dv focus --package ostd -- --verify-only-module mm::vm_space
    ```

    结果分别是`5 verified`, `6 verified`, `34 verified`, 都是`0 errors`. 只有输出中有`verification results`一行才说明真的验证了; 源码内容不变时cargo-verus会直接用缓存. 验证用的检出在验证后已撤销改动.
