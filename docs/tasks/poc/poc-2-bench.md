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

### 1. AOT 完整对比（10M 迭代，10 次取中位数）

| 场景 | dual-view | boxed | native | dual/boxed | dual/native |
|------|-----------|-------|--------|------------|-------------|
| **int** | 491M | 466M | 1.70B | 1.05x | 29% |
| **double** | 238M | 139M | 247M | **1.71x** | 96% |
| **mixed** | 204M | 126M | — | **1.63x** | — |

### 2. JIT 完整对比

| 场景 | dual-view | boxed | native | dual/boxed |
|------|-----------|-------|--------|------------|
| **int** | 364M | 1.25B | 1.34B | 0.29x |
| **double** | 261M | 133M | 1.12B | 1.97x |
| **mixed** | 272M | 212M | — | 1.28x |

### 3. 分析

**int 场景差异小（AOT 1.05x）:**
- int 不涉及堆分配，装箱/拆箱只是类型检查开销
- AOT 编译器对 int 的优化已经很好，双视图优势微弱

**double 场景差异大（AOT 1.71x）:**
- 装箱 double 每次写入都需要堆分配 `Double` 对象
- 双视图直接写 `Float64List` 槽位，零分配
- 双视图 double 达到 native 的 **96%**，几乎无损

**mixed 场景（AOT 1.63x）:**
- 同时操作 int/double，更接近真实解释器工作负载
- 装箱方案的 double 堆分配拖累整体性能

**JIT 反转现象:**
- JIT 下 int 装箱反而 **3.4x 快于** 双视图（VM 推测性类型专化）
- 但 double/mixed 场景 JIT 下双视图也更快，说明推测优化对 double 不生效

**结论:** darti 解释器将同时处理 int/double，双视图方案在 AOT 下有 **63%~71%** 性能优势，方案成立。

### 4. 与原生代码的差距

- int: AOT 下 dual-view 约为 native 的 **29%**（491M vs 1.70B）→ 符合 1/5~1/3 目标
- double: AOT 下 dual-view 约为 native 的 **96%**（238M vs 247M）→ 远超目标

### 5. 分发循环

- 32 位定宽指令编码（ABC/AsBx 格式）工作正常
- 跳转偏移公式 `offset = target_pc - current_pc - 1`（因 dispatch loop 先 `pc++` 再 switch）
- 迭代 Fibonacci 对小 n 值执行太快（<1μs），需更大计算量才能体现 interp/native 比值
