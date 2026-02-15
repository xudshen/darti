# POC-2: 双视图值栈性能

> 方案来源: `docs/plans/2026-02-15-poc-implementation.md` Task 7–9

## 目标

验证共享 ByteBuffer 双视图（Int64List + Float64List）的性能表现，对标 AOT 原生 1/5~1/3 目标。

## 任务

### Task 7: 双视图值栈实现

**依赖:** Task 1
**产出文件:**
- `packages/poc_bench/lib/src/value_stack.dart`
- `packages/poc_bench/test/value_stack_test.dart`

**TDD 步骤:**
- [x] 写失败测试 `value_stack_test.dart`
- [x] 运行验证测试失败
- [x] 实现 `value_stack.dart`
- [x] 运行验证测试通过
- [x] **Commit**（ValueStack 实现）— `19effc1`

### Task 8: 基准场景实现

**依赖:** Task 7
**产出文件:**
- `packages/poc_bench/lib/src/benchmarks.dart`
- `packages/poc_bench/lib/src/dispatch_sim.dart`
- `packages/poc_bench/test/dispatch_sim_test.dart`

**TDD 步骤:**
- [x] 实现 `benchmarks.dart`（4 种基准：int 累加、double 累加、混合、装箱对照）
- [x] 实现 `dispatch_sim.dart`（分发循环模拟 + 迭代 Fibonacci 字节码）
- [x] 实现 `dispatch_sim_test.dart`（正确性验证 fib(0)..fib(30)）
- [x] **Commit**（基准场景 + 分发模拟）— `dfedcba`

### Task 9: 基准 CLI 与 AOT 测量

**依赖:** Task 8
**产出文件:**
- `packages/poc_bench/bin/bench.dart`

**TDD 步骤:**
- [x] 创建 `bin/bench.dart` CLI
- [x] JIT 模式运行基准，记录结果
- [x] AOT 编译后运行基准，记录结果
- [x] 对比分析性能数据
- [x] **Commit**（基准场景 + CLI + 测量结果）— `d7cfebd`

## 关键发现

### 1. JIT vs AOT 性能差异

| 基准 | JIT (ops/sec) | AOT (ops/sec) | 说明 |
|------|--------------|---------------|------|
| int_arith (dual-view) | ~370M | ~485M | AOT 更快 |
| int_arith (boxed) | ~1.28B | ~413M | JIT 推测优化大幅领先 |
| int_arith (native) | ~1.3B | ~1.78B | 裸 int 基线 |
| double_arith (dual-view) | ~310M | ~360M | 与 int 类似 |

### 2. 双视图 vs 装箱性能

- **JIT 模式**: 装箱 (`List<Object?>`) 反而 **3x 快于** 双视图。原因：Dart VM JIT 能对 `List<Object?>` 做推测性类型专化，消除拆箱开销。
- **AOT 模式**: 双视图 **1.2x 快于** 装箱。AOT 无推测优化，typed_data 视图的静态类型优势体现。
- **结论**: darti 解释器以 AOT 编译为目标场景时，双视图方案成立。

### 3. 与原生代码的差距

- AOT 下 dual-view 约为 native 的 **27%** (~485M vs ~1.78B)
- 目标 1/5~1/3 → **27% 落在 1/4 区间，符合目标**

### 4. 分发循环

- 32 位定宽指令编码（ABC/AsBx 格式）工作正常
- 跳转偏移公式 `offset = target_pc - current_pc - 1`（因 dispatch loop 先 `pc++` 再 switch）
- 迭代 Fibonacci 对小 n 值执行太快（<1μs），需更大计算量才能体现 interp/native 比值
- fib(40) 级别能稳定测出比值
