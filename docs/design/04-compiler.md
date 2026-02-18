# Chapter 4: 编译器

## 模块定位

dartic 编译器是一个**离线 CLI 工具**，运行在开发机或 CI 环境，不在目标设备上运行。输入为 CFE 生成的 linked-platform `.dill` 文件（Kernel AST），输出为 `.darticb` 字节码文件。编译器依赖 `package:kernel`（SDK 级别），作为独立 package 发布，与运行时 package 解耦。

## 与其他模块的关系

| 方向 | 模块 | 接口 |
|------|------|------|
| 输入 | CFE（Dart SDK 工具链） | linked-platform `.dill`：所有 `Reference` 已解析，类型信息完整 |
| 输入 | Ch3 Bridge 预生成库 | Bridge 注册表元数据：已知绑定符号名集合 |
| 输出目标 | Ch1 ISA | 生成符合 Ch1 编码格式的 `Uint32List` 字节码 |
| 输出产物 | Ch2 运行时 | `.darticb` 文件，包含字节码、常量池、类表、绑定名称表 |
| 类型系统 | Ch5 泛型 | 编译器传递 ITA/FTA 描述符，运行时按需实化 |
| 异步编译 | Ch6 异步 | 编译器标记 async 函数，生成帧快照所需的寄存器元数据 |
| 安全验证 | Ch7 沙箱 | `.darticb` 结构需通过加载时验证（操作码合法性、操作数范围） |

## 设计决策

| 决策项 | 选择 | 备选方案与拒绝理由 | 理由 |
|--------|------|-------------------|------|
| 编译器形态 | 独立 CLI 工具（独立 package） | 嵌入运行时 package：引入 `package:kernel` 的 SDK 级依赖，设备端不需要 | 编译器与运行时解耦，设备端零编译依赖 |
| Kernel 加载 | `package:kernel` BinaryBuilder | 自写解析器：Kernel 二进制格式随 SDK 版本变化 | 正确性有保障，跟随 SDK 升级 |
| 寄存器分配 | 作用域级回收（Phase 1） | LSRA：需先构建 CFG + 活跃区间，Phase 1 复杂度不值得 | 以极低复杂度覆盖主要场景；Dart 函数通常局部变量 <50，8 位寄存器上限 256 |
| Bridge 生成 | 预生成库（独立 package） | 运行时反射生成：Dart 无法运行时创建类 | 常用框架类通过 build_runner 预生成，作为 package 发布 |
| 优化遍 | Phase 2 实施 | Phase 1 全量开启：无 profiling 数据指导 | 各优化遍根据 profiling 数据确定优先级 |
| .darticb 符号解析 | 加载时按名称解析 | 编译时绑定固定 ID：编译产物与 Bridge 库版本耦合 | 只要符号名存在，ID 如何分配无关紧要 |

## 核心概念

### 编译管线总览

```
dartic_compiler CLI
  │
  ├── Kernel 加载层
  │   └── package:kernel BinaryBuilder 解析 .dill → Component AST
  │
  ├── 分析阶段
  │   ├── 作用域分析（变量绑定：local / upvalue / global）
  │   ├── 类型流分析（StackKind 决策：value / ref）
  │   └── 依赖分析（Bridge 绑定集合收集）
  │
  ├── 代码生成阶段
  │   ├── 作用域级寄存器分配
  │   ├── 字节码发射
  │   └── 常量池构建
  │
  ├── 优化阶段（Phase 2）
  │   ├── 常量折叠
  │   ├── 窥孔优化
  │   └── 死代码消除
  │
  └── 序列化输出 → .darticb 文件
```

编译管线数据流：

```
.dill ──► Kernel 加载 ──► Component AST
                              │
                    ┌─────────┼──────────┐
                    ▼         ▼          ▼
              作用域分析  类型流分析  依赖分析
                    │         │          │
                    └─────────┼──────────┘
                              ▼
               Annotated AST + Binding Table
                              │
                    ┌─────────┼──────────┐
                    ▼         ▼          ▼
              寄存器分配  字节码发射  常量池构建
                    │         │          │
                    └─────────┼──────────┘
                              ▼
                       .darticb 序列化
```

### Kernel 加载

编译器输入为 **linked-platform `.dill`**（`dart compile kernel` 默认输出，不使用 `--no-link-platform`）。平台库的 AST 节点完整链接，所有 `Reference`（如 `interfaceTarget`、`target`）均可直接解析。编译器通过 `interfaceTarget.enclosingClass` 等属性识别平台类型，映射到 Bridge 绑定标识。

### 分析阶段

编译器在代码生成前执行三项分析：

#### 1. 作用域分析

编译器维护作用域帧栈，将每个变量引用解析为三种绑定之一：

| 绑定类型 | 含义 | 生成的指令 |
|----------|------|-----------|
| local | 当前函数的局部变量 | 直接寄存器访问 |
| upvalue | 被闭包捕获的外层变量 | `GET_UPVALUE` / `SET_UPVALUE` |
| global | 全局变量或静态字段 | `LOAD_GLOBAL` / `STORE_GLOBAL` |

每个绑定记录：寄存器槽位（或上值/全局索引）、是否可变、是否被捕获、StackKind。

#### 2. 类型流分析

CFE 已在 Kernel AST 中填入完整类型信息。编译器根据变量的静态类型决定 StackKind，决定存入值栈还是引用栈（详见 Ch1 双视图安全约束、Ch2 双视图值栈）：

| 静态类型 | StackKind | 栈 | 理由 |
|----------|-----------|-----|------|
| `int` | value | 值栈 intView | 64 位精度，零装箱 |
| `double` | value | 值栈 doubleView | 零装箱 |
| `bool` | value | 值栈 intView | 存为 0/1 |
| 其他所有类型 | ref | 引用栈 | 需要 GC 追踪 |
| `dynamic`、`Object?`、`num` | ref | 引用栈 | 无法静态确定，走装箱路径 |

**特殊情况**：当 `int`/`double`/`bool` 变量被闭包捕获（`isCaptured = true`）时，StackKind 强制设为 `ref`。这是正确性约束——值栈数据无法被 `CLOSE_UPVALUE` 的 `Object?` 语义处理。被捕获的原始类型变量额外承受一次装箱/拆箱，但 Dart 代码中此场景较少（循环变量和计数器通常不被捕获）。

**DartType 完整分类**：编译器在 StackKind 决策和 TypeTemplate 生成两个场景处理 Kernel 的 DartType。以下列出所有 DartType 子类的处理方式：

| DartType | StackKind | TypeTemplate 生成（用于 `is`/`as`、泛型实例化） |
|----------|-----------|-----------------------------------------------|
| `InterfaceType` | int/double/bool → value，其他 → ref | TypeTemplate(classId, [typeArg...])。Nullability 影响 `is`/`as` 检查 |
| `FunctionType` | ref | TypeTemplate(FUNCTION, [paramTypes..., returnType, typeParams...]) |
| `TypeParameterType` | ref（无法静态确定） | TypeTemplate(TYPE_PARAM, paramIndex)，运行时从 ITA/FTA 解析 |
| `StructuralParameterType` | ref | 同 TypeParameterType，用于 `FunctionType` 内部的类型参数 |
| `RecordType` | ref | TypeTemplate(RECORD, [fieldTypes..., fieldNames...]) |
| `FutureOrType` | ref | TypeTemplate(FUTURE_OR, [typeArg])，运行时特殊处理 `is`/`as`（详见 Ch5） |
| `IntersectionType` | ref | 使用 promoted type（`right`）生成 TypeTemplate——IntersectionType 是 CFE 类型提升产物 |
| `DynamicType` | ref | TypeTemplate(DYNAMIC)。`is` 检查始终为 true，`as` 无操作 |
| `VoidType` | ref | TypeTemplate(VOID)。语义与 dynamic 类似，仅在静态分析中区分 |
| `NeverType` | ref（理论上不可达） | TypeTemplate(NEVER)。`is` 检查始终为 false（底类型） |
| `NullType` | ref | TypeTemplate(NULL)。仅 `null` 值满足 `is` 检查 |
| `InvalidType` | — | 编译器报错（CFE 产生的错误类型不应进入代码生成阶段） |
| `ExtensionType` | 取决于表示类型 | CFE 已擦除为底层表示类型（详见 CFE 脱糖与语言特性处理） |
| `TypedefType` | 取决于底层类型 | CFE 已展开为底层类型引用 |

#### 3. 依赖分析

编译器遍历 Kernel AST 中所有对宿主类型的引用，通过 `interfaceTarget.enclosingClass` 识别宿主类，查找 Bridge 注册表确认绑定存在。对每个引用分配**本地绑定索引**（包含符号名和参数数量），最终输出绑定名称表写入 `.darticb`。如果引用的类未在 Bridge 注册表中，编译器报错。

**Bridge 注册表**从预生成库元数据加载已知绑定符号名集合。编译器遇到对 `dart:core::List.add` 等的引用时，以 `"库URI::类名::方法名#参数数量"` 为键分配本地索引。同一方法不同参数数量生成不同条目。编译器生成 `CALL_HOST A, Bx`（A=baseReg, Bx=本地绑定索引）。详见 Ch3 宿主函数注册表。

### 寄存器分配

**Phase 1：作用域级回收**。编译器为值栈和引用栈各维护独立的寄存器池。分配采用递增计数 + 空闲池回收：请求寄存器时优先从空闲池取，否则递增分配新编号；变量离开作用域时批量归还。

**设计取舍**：此方案无需 CFG 或活跃区间分析，以极低复杂度覆盖主要复用场景（if/else 分支、for 循环体、块级临时变量）。Dart 函数通常局部变量不多（<50），8 位寄存器编码上限 256，作用域回收足以满足需求。

> **Phase 2**：LSRA 线性扫描寄存器分配。需先将 Kernel AST 转换为线性 IR 并构建 CFG，从基本块边界（`IfStatement`、循环、`TryCatch`、`SwitchStatement`）划分，计算活跃区间 [start, end)，按起始位置排序后线性扫描分配。溢出时选活跃区间最长的变量溢出到栈帧溢出区。触发条件：async 帧快照大小成为瓶颈，或 profiling 显示帧尺寸影响缓存局部性。

### 常量池类型映射

Kernel 的 `Constant` 子类映射到常量池四分区（refs/ints/doubles/names）：

| Constant 类型 | 目标分区 | 编码方式 |
|--------------|---------|---------|
| `NullConstant` | refs | 存储 `null` 引用 |
| `BoolConstant` | ints | 存储 0（false）或 1（true） |
| `IntConstant` | ints | 直接存储 64 位整数 |
| `DoubleConstant` | doubles | 直接存储 64 位浮点数 |
| `StringConstant` | refs | 存储 Dart String 对象 |
| `SymbolConstant` | refs | 存储 Symbol 对象（名称 + 库 URI） |
| `ListConstant` | refs | 递归编译元素 → 创建不可变 List 对象 |
| `SetConstant` | refs | 递归编译元素 → 创建不可变 Set 对象 |
| `MapConstant` | refs | 递归编译键值对 → 创建不可变 Map 对象 |
| `RecordConstant` | refs | 递归编译字段 → 创建不可变 Record 对象 |
| `InstanceConstant` | refs | 递归编译字段值 → 创建不可变实例（classId + 字段快照） |
| `InstantiationConstant` | refs | 编译 tearOff + typeArgs → 创建实例化闭包常量 |
| `TypeLiteralConstant` | refs | 编译 `type` 为 TypeTemplate → 存储类型描述符 |
| `UnevaluatedConstant` | — | CFE 应已求值（linked `.dill` 中不应出现）；若出现则编译器报错 |
| `StaticTearOffConstant` | refs | 编译为 FuncProto 引用（静态方法闭包） |
| `ConstructorTearOffConstant` | refs | 编译为构造函数 thunk 闭包 |
| `RedirectingFactoryTearOffConstant` | refs | 解析最终目标后编译为 thunk 闭包 |
| `TypedefTearOffConstant` | refs | 解析底层类型后编译为 thunk 闭包 |

去重不变式：常量池中相同结构的 Constant 只保留一个条目。去重顺序为先叶后根——子常量先入池并获得索引，父常量基于子常量索引进行结构相等性比较。

## 工作流程

以下按编译管线的处理顺序组织：语句级遍历 → 表达式级编译 → 类与构造函数 → 函数对象 → 特殊变量语义 → 常量处理 → 异步/生成器。各小节采用"Kernel 节点 → 编译策略"映射表，每个编译策略用 `→` 符号标记步骤顺序，复杂流程另附编号步骤说明。

### 控制流编译

编译器将 Kernel AST 的控制流节点编译为跳转指令序列。所有 `compileXxx` 方法遵循统一模式：发射条件/无条件跳转 → 编译子节点 → 回填跳转目标。

| 语法结构 | 编译模式 | 关键要点 |
|----------|----------|----------|
| `if`/`else` | 条件跳转 + 回填 | 编译条件 → `JUMP_IF_FALSE` 到 else → 编译 then → `JUMP` 到 end → 回填 else → 编译 else → 回填 end |
| `for` | 向后跳转 | 进入作用域 → 编译初始化 → 记录循环起点 → 编译条件 → `JUMP_IF_FALSE` 出循环 → 编译循环体 → 编译更新 → `JUMP` 回起点 → 回填出口 |
| `while` | 向后跳转 | 与 `for` 类似，无初始化和更新步骤 |
| `do-while` | 先执行后判断 | 记录循环起点 → 编译循环体 → 编译条件 → `JUMP_IF_TRUE` 回起点 |
| `for-in` | 迭代器协议 | 同步（`ForInStatement.isAsync == false`）：编译 `iterable.iterator` → 循环调用 `moveNext()` + `current` getter → 绑定循环变量。异步（`isAsync == true`，即 `await for`）：编译为 `stream.listen` + `AWAIT_STREAM_NEXT` 序列（详见 Ch6 async\* 生成器） |
| `switch` | 跳转表 / 二分查找 | 密集整数 case → 跳转表指令；稀疏 case → 二分查找跳转链。Pattern matching 在 Kernel 中已由 CFE 脱糖为 if-else 链 |
| `try`/`catch` | 异常处理器表 | 不使用内联跳转。生成 `(startPC, endPC, handlerPC, catchType, valueStackDepth, refStackDepth)` 元组。嵌套 try 按范围从小到大排序，运行时顺序扫描首个匹配。详见 Ch2 异常分发 |
| `try`/`finally` | 处理器表 + finally 块 | finally 块在正常路径和异常路径各编译一份 |
| `labeled break`/`continue` | 标签→跳转目标映射 | 编译器维护标签映射表，`BreakStatement` 发射 `JUMP` 并记录待回填，标签语句结束时批量回填所有 break 跳转 |
| `assert` | 条件省略 | `--no-enable-asserts` 时完全不生成代码。否则：编译条件 → `JUMP_IF_TRUE` 跳过 → `ASSERT` 指令（携带消息常量池索引） |
| 条件表达式 `a ? b : c` | `JUMP_IF_FALSE` + `JUMP` | 与 if/else 模式相同，已由 CFE 表示为 `ConditionalExpression` |

### 语句编译补充

控制流编译小节覆盖了大部分语句节点（if/for/while/do/for-in/switch/try-catch/try-finally/labeled break/assert）。以下补充其余 Statement 子类：

| Kernel 节点 | 编译策略 |
|------------|----------|
| `Block` | 进入新作用域 → 逐条编译子 Statement → 退出作用域（批量释放寄存器） |
| `ExpressionStatement` | 编译 expression → 若结果占用临时寄存器则释放（不保留结果值） |
| `EmptyStatement` | 不生成任何指令 |
| `ReturnStatement` | 同步函数：编译 expression → 根据返回类型 `RETURN_REF` / `RETURN_VAL` / `RETURN_NULL`。async 函数：`ASYNC_RETURN`（详见 Ch6）。async\* 函数：`controller.close()` + 帧结束（详见 Ch6）。sync\* 函数：标记 iterator done + 帧结束（详见 Ch6） |
| `YieldStatement` | 编译 expression → `YIELD A, Bx`（`isYieldStar` 时用 `YIELD_STAR`）。Bx 编码恢复点 IP（详见 Generator 编译） |
| `AssertBlock` | 与 `AssertStatement` 相同处理，`--no-enable-asserts` 时完全不生成代码 |
| `FunctionDeclaration` | 详见闭包编译 |
| `VariableDeclaration` | 详见作用域分析（分配寄存器 + 编译初始化器）。`isLate` 时详见 Late 变量编译 |
| `ContinueSwitchStatement` | 与 `BreakStatement` 类似，发射 `JUMP` 到目标 case 标签，编译器维护 case 标签映射表 |
| `PatternVariableDeclaration` | CFE 应已脱糖为普通变量声明（待验证） |
| `IfCaseStatement` | CFE 应已脱糖为 if-else 链（待验证） |
| `PatternSwitchStatement` | CFE 应已脱糖为 if-else 链（待验证） |

### 属性访问编译

Kernel 中属性访问统一为 `InstanceGet` / `InstanceSet` 节点。编译器根据 `interfaceTarget` 分发：

| 目标类型 | 生成指令 | 说明 |
|----------|----------|------|
| 解释器类的真实字段 | `GET_FIELD_REF` / `GET_FIELD_VAL` / `SET_FIELD_REF` / `SET_FIELD_VAL` | 直接字段访问 |
| getter/setter `Procedure` | `CALL_VIRTUAL` | 调用 getter/setter 方法 |
| 宿主类属性 | `GET_FIELD_DYN` / `SET_FIELD_DYN` | 走 HostClassWrapper 路由（详见 Ch3） |

### 表达式编译

编译器将 Kernel AST 的 Expression 节点编译为字节码序列。控制流表达式详见"控制流编译"，属性访问详见"属性访问编译"，闭包/Tear-off 详见对应小节。本节覆盖其余所有 Expression 子类。

#### 变量与静态访问

| Kernel 节点 | 编译策略 |
|------------|----------|
| `VariableGet` | 根据作用域分析绑定类型：local → 寄存器读取，upvalue → `GET_UPVALUE`，global → `LOAD_GLOBAL` |
| `VariableSet` | local → 寄存器写入，upvalue → `SET_UPVALUE`，global → `STORE_GLOBAL` |
| `StaticGet` | 静态字段/顶层变量 → `LOAD_GLOBAL`（详见静态字段与顶层变量）。静态方法引用 → 等价于 `StaticTearOff` |
| `StaticSet` | 静态字段/顶层变量 → `STORE_GLOBAL` |

#### 调用表达式

| Kernel 节点 | 编译策略 |
|------------|----------|
| `StaticInvocation` | 编译参数 → `CALL_STATIC`（解释器函数）或 `CALL_HOST`（Bridge 绑定） |
| `InstanceInvocation` | 编译 receiver + 参数 → `CALL_VIRTUAL`（IC 快路径） |
| `ConstructorInvocation` | `NEW_INSTANCE` → 编译参数 → `CALL_STATIC`（详见构造函数编译） |
| `LocalFunctionInvocation` | 局部函数引用已在寄存器中 → `CALL_REF` |
| `FunctionInvocation` | 函数类型 `call()` → `CALL_REF` |
| `InstanceGetterInvocation` | `CALL_VIRTUAL`（getter）→ 结果存入临时寄存器 → `CALL_REF`（调用返回值） |
| `EqualsNull` | `JUMP_IF_NULL` / `JUMP_IF_NNULL`（CFE 优化节点，避免 `==` 虚分发） |
| `EqualsCall` | 编译左右操作数 → `CALL_VIRTUAL`（调用 `==` 方法） |

#### 类型操作

| Kernel 节点 | 编译策略 |
|------------|----------|
| `IsExpression` | 编译操作数 → 将 `type` 编译为 TypeTemplate 写入常量池 → `INSTANCEOF A, B, Cx` |
| `AsExpression` | 编译操作数 → 将 `type` 编译为 TypeTemplate 写入常量池 → `CAST A, B, Cx`（失败抛 `TypeError`） |

TypeTemplate 生成：编译器将 Kernel `DartType` 递归转换为 Ch5 定义的 TypeTemplate 描述符。对于参数化类型（如 `List<int>`），TypeTemplate 包含 classId + typeArgs 引用。运行时 `INSTANCEOF`/`CAST` 通过 `resolveType()` 实化 TypeTemplate 后调用 `isSubtypeOf()` 判定（详见 Ch5 泛型数据流）。

#### Dynamic 调度

| Kernel 节点 | 编译策略 |
|------------|----------|
| `DynamicGet` | 编译 receiver → `GET_FIELD_DYN A, B, Cx`（Cx = names 常量池中的属性名索引） |
| `DynamicSet` | 编译 receiver + value → `SET_FIELD_DYN A, B, Cx` |
| `DynamicInvocation` | 编译 receiver + 参数 → `INVOKE_DYN A, B, C`（运行时按名查方法，找不到转 `noSuchMethod`） |

编译器检查节点的 `DynamicAccessKind`——`Dynamic` 和 `Unresolved` 生成动态调度指令；`Never` 可优化为直接 `THROW`（不可达代码）；`Invalid` 编译时报错。

#### Super 访问

| Kernel 节点 | 编译策略 |
|------------|----------|
| `SuperPropertyGet` | `CALL_SUPER A, Bx`（Bx = 方法表中 getter 的索引） |
| `SuperPropertySet` | 编译 value → `CALL_SUPER A, Bx`（Bx = 方法表中 setter 的索引） |
| `SuperMethodInvocation` | 编译参数 → `CALL_SUPER A, Bx`（Bx = 方法表中方法的索引） |
| `AbstractSuperPropertyGet/Set` | 不应在 linked `.dill` 中出现（CFE 已解析为具体目标）；若出现则编译器报错 |
| `AbstractSuperMethodInvocation` | 同上 |

Super 分发通过 `interfaceTarget` 确定目标方法在父类方法表中的索引。`CALL_SUPER` 直接使用编译期确定的方法索引，不走 IC 虚分发——super 调用的目标在编译期已完全确定。

#### 逻辑与空安全

| Kernel 节点 | 编译策略 |
|------------|----------|
| `Not` | 编译操作数 → `BIT_XOR A, B, #1`（Ch1：无专用 NOT 指令，Phase 2 可添加） |
| `NullCheck` | 编译操作数 → `NULL_CHECK A`（若 `refStack[A] == null` 则抛 TypeError，否则 fall-through） |
| `LogicalExpression` | 短路求值。`&&`：编译左 → `JUMP_IF_FALSE` 到 end（结果 = false）→ 编译右 → end。`||`：编译左 → `JUMP_IF_TRUE` 到 end（结果 = true）→ 编译右 → end |
| `Throw` | 编译操作数 → `THROW A`。Dart 中 throw 是表达式（类型 Never），在条件表达式中可直接使用 |
| `Rethrow` | `RETHROW A, B`（A = 异常对象, B = stackTrace）。仅在 catch 块内有效 |

#### 字面量

| Kernel 节点 | 编译策略 |
|------------|----------|
| `IntLiteral` | `LOAD_CONST_INT A, Bx`（值栈 intView） |
| `DoubleLiteral` | `LOAD_CONST_DOUBLE A, Bx`（值栈 doubleView） |
| `BoolLiteral` | `LOAD_INT A, Bx`（0 或 1，值栈 intView） |
| `NullLiteral` | `LOAD_NULL A`（引用栈） |
| `StringLiteral` | `LOAD_CONST_REF A, Bx`（字符串常量池索引） |
| `SymbolLiteral` | `LOAD_CONST_REF A, Bx`（Symbol 常量池索引） |
| `TypeLiteral` | `LOAD_CONST_REF A, Bx`（TypeTemplate 常量池索引） |
| `ThisExpression` | 引用栈 R(0)——this 始终在第一个引用栈寄存器 |
| `ConstantExpression` | `LOAD_CONST_REF A, Bx`（详见 Const 对象规范化） |

#### 集合字面量

| Kernel 节点 | 编译策略 |
|------------|----------|
| `ListLiteral` | 非 const：`CALL_HOST`（List 构造）→ 逐元素编译 → `CALL_HOST`（add）。const → 常量池 |
| `SetLiteral` | 非 const：`CALL_HOST`（Set 构造）→ 逐元素 `CALL_HOST`（add）。const → 常量池 |
| `MapLiteral` | 非 const：`CALL_HOST`（Map 构造）→ 逐键值对 `CALL_HOST`（`[]=`）。const → 常量池 |
| `StringConcatenation` | 逐部分编译求值 → `CALL_HOST`（字符串拼接） |

#### Record 操作

| Kernel 节点 | 编译策略 |
|------------|----------|
| `RecordLiteral` | 编译各字段表达式 → `CALL_HOST`（Record 构造，携带字段名元数据） |
| `RecordIndexGet` | 编译 receiver → `GET_FIELD_REF`/`GET_FIELD_VAL`（按位置索引访问 Record 字段） |
| `RecordNameGet` | 编译 receiver → `GET_FIELD_DYN`（按名称查找 Record 字段） |

#### 其他表达式

| Kernel 节点 | 编译策略 |
|------------|----------|
| `FunctionExpression` | 与闭包编译策略相同 → `CLOSURE A, Bx` |
| `BlockExpression` | 编译 body（Statement 列表）→ 编译 value（Expression），结果为 value 的值 |
| `Instantiation` | 编译函数操作数 → 将类型参数编译为 TypeTemplate → 生成实例化包装闭包（详见 Ch5） |
| `InstanceCreation` | const 上下文对象创建 → `LOAD_CONST_REF`（常量池中的 InstanceConstant） |
| `Let` | 编译 variable 赋值 → 编译 body 表达式，结果为 body 的值 |
| `AwaitExpression` | 详见 Ch6 异步 |
| `InvalidExpression` | 编译为 `THROW`（CFE 编译错误占位，正常代码中不应出现） |
| `FileUriExpression` | 透传包装器，编译内部 expression |
| `SwitchExpression` | CFE 应已脱糖（待验证，同 Pattern 脱糖验证） |
| `PatternAssignment` | CFE 应已脱糖（待验证） |
| `ListConcatenation`/`SetConcatenation`/`MapConcatenation` | const 上下文中在常量池内完成拼接 |
| `LoadLibrary`/`CheckLibraryIsLoaded` | dartic 不支持延迟加载，编译器报错 |

### 构造函数编译

构造函数在 Kernel 中表示为 `Constructor` 节点，包含 `initializers` 列表和 `function` 体。编译顺序遵循 Dart 语义：

1. **无效初始化器**（`InvalidInitializer`）：CFE 编译错误占位，正常 `.dill` 中不应出现；若出现则编译器报错
2. **字段初始化器**（`FieldInitializer`）：按声明顺序编译 `value` 表达式，生成 `SET_FIELD_REF` / `SET_FIELD_VAL` 写入对应字段
3. **局部初始化器**（`LocalInitializer`）：在初始化列表中引入临时变量，编译为寄存器赋值
4. **断言初始化器**（`AssertInitializer`）：编译为 `ASSERT` 指令（`--no-enable-asserts` 时省略）
5. **Super 初始化器**（`SuperInitializer`）：编译参数 → `CALL_SUPER`，每个构造函数最多一个
6. **重定向初始化器**（`RedirectingInitializer`）：编译参数 → `CALL_STATIC` 到目标构造函数，排斥其他初始化器
7. **构造函数体**（`function.body`）：正常编译函数体语句

调用端编译：`ConstructorInvocation` 编译为 `NEW_INSTANCE A, Bx`（分配对象）→ 编译参数 → `CALL_STATIC`（调用构造函数，传入新对象作为 receiver）。

### 闭包编译

编译器遍历变量引用，标记被内层函数捕获的变量为 `isCaptured`。上值描述符记录来源：是直接捕获外层局部变量（`isLocal = true`，记录外层寄存器索引），还是间接通过外层上值链传递（`isLocal = false`，记录外层上值索引）。

`CLOSURE A, Bx` 指令在运行时根据 `funcProto[Bx]` 的上值描述符列表，从当前帧的寄存器或上值表中收集上值，创建闭包对象。

当变量离开作用域且被捕获时，编译器在作用域退出前插入 `CLOSE_UPVALUE A`，运行时将所有指向 >= A 槽位的开放上值关闭（值从栈复制到上值对象内部）。

### Tear-off 编译

Kernel 中有五种 tear-off 表达式节点，均需编译为闭包创建：

| Kernel 节点 | 编译策略 |
|------------|----------|
| `InstanceTearOff` | 生成 thunk `DarticFuncProto`，捕获 receiver 为 upvalue，体为 `CALL_VIRTUAL` 转发 |
| `StaticTearOff` | 生成 thunk `DarticFuncProto`，体为 `CALL_STATIC` 转发，无需捕获 |
| `FunctionTearOff` | 直接 `MOVE_REF`（函数值本身已是闭包对象） |
| `ConstructorTearOff` | 生成 thunk `DarticFuncProto`，体为 `NEW_INSTANCE` + 字段初始化 + 返回 |
| `RedirectingFactoryTearOff` / `TypedefTearOff` | 同 `ConstructorTearOff`，解析最终目标后生成 thunk |

所有 thunk 通过 `CLOSURE A, Bx` 指令创建，复用闭包编译的上值捕获机制。编译器为每个 tear-off 站点在函数表中生成一个独立的 `DarticFuncProto`（参数签名与目标方法一致）。

### Late 变量编译

Kernel 的 `VariableDeclaration` 携带 `isLate` 标志。编译策略：

| 类型 | 编译方式 |
|------|----------|
| 无初始化器的 `late` | 声明时存入哨兵值，读取时检查哨兵，未初始化则抛出 `LateInitializationError` |
| 有初始化器的 `late` | 声明时存哨兵，首次读取时执行初始化器、缓存结果、返回值 |
| `late final` | 首次写入后标记为已初始化，再次写入抛出错误 |

### 静态字段与顶层变量

编译器为每个静态字段和顶层变量分配全局索引，生成 `LOAD_GLOBAL` / `STORE_GLOBAL`。初始化器编译为独立的 `DarticFuncProto`，在 `LOAD_GLOBAL` 首次访问时由运行时惰性调用（详见 Ch2 惰性初始化流程）。

### Const 对象规范化

Kernel 的 `ConstantExpression` 引用 `Constant` 节点（`InstanceConstant`、`ListConstant` 等）。编译器在常量池构建阶段递归去重：子常量先去重，父常量再基于子常量的 identity 去重。相同结构的 `InstanceConstant` 共享常量池条目，`LOAD_CONST` 加载后 `identical()` 保证成立。

### Generator 编译

编译器通过 `FunctionNode.dartAsyncMarker` 识别 async/generator 函数（详见 Ch6 asyncMarker 字段决策）。Kernel 的 `FunctionNode` 有两个异步标记字段：`asyncMarker`（运行时标记，可能被 Kernel 脱糖变换修改为 Sync）和 `dartAsyncMarker`（源码标记，始终不变）。dartic 不做 Kernel 层脱糖，两字段实际相同，但编译器统一读取 `dartAsyncMarker`。

编译器同时从 `FunctionNode.emittedValueType` 获取产出值类型（如 async 函数返回 `Future<int>` 时 `emittedValueType = int`），编译为 TypeTemplate 写入常量池，作为 INIT_ASYNC / INIT_ASYNC_STAR / INIT_SYNC_STAR 指令的 Bx 操作数（详见 Ch6 emittedValueType 与类型参数）。

| 函数类型 | dartAsyncMarker | 编译策略 |
|----------|-----------------|----------|
| async | `Async` | 函数入口发射 `INIT_ASYNC A, Bx`。`ReturnStatement` 编译为 `ASYNC_RETURN`。`AwaitExpression` 编译为 `AWAIT`（详见 Ch6） |
| sync\* | `SyncStar` | 函数入口发射 `INIT_SYNC_STAR A, Bx`。`YIELD A, Bx` 暂停执行并产出值，`moveNext()` 从 Bx 恢复。函数正常返回时迭代器标记 done |
| async\* | `AsyncStar` | 函数入口发射 `INIT_ASYNC_STAR A, Bx`。`YIELD A, Bx` 通过 StreamController 产出值。`yield*` 委托子流（详见 Ch6） |

`YieldStatement` 编译流程：

1. 编译 `expression` 到寄存器 A
2. 发射 `YIELD A, Bx`（Bx = 当前 PC+1，即恢复点）。`isYieldStar` 时发射 `YIELD_STAR A, Bx`
3. 编译器记录恢复点处的寄存器活跃状态，供运行时帧快照使用

Generator 函数的帧管理与 async 函数共享相同的帧快照/恢复机制（详见 Ch6）。

## CFE 脱糖与语言特性处理

Dart 3 的 extension type 是编译期零成本抽象，在 Kernel AST 中已被 CFE 脱糖为底层表示类型的操作。编译器无需特殊处理——extension type 的方法调用在 Kernel 中表现为普通的静态调用或实例调用。

以下 Dart 语言特性在 Kernel AST 中已被 CFE 脱糖，编译器正常处理对应的 Kernel 节点即可，无需特殊逻辑：

| 源码特性 | Kernel 表示 |
|----------|------------|
| Cascade (`..`) | 临时变量 + 顺序 `InstanceGet`/`InstanceInvocation` |
| Pattern matching | `IfStatement` 链 |
| Extension methods | `StaticInvocation` |
| Extension types | 擦除为底层表示类型 |
| Constructor tear-offs (`MyClass.new`) | `ConstructorTearOff` → 闭包 |
| Super parameters (`super.x`) | 构造函数参数转发 |
| Named arguments anywhere | 参数已重排至正确位置 |
| Spread collections (`...list`) | 命令式 `add`/`addAll` 调用 |
| List literal (`<int>[1,2,3]`) | `StaticInvocation(_GrowableList._literal3(1, 2, 3))` |
| Control flow collections (`if`/`for` in `[]`) | 命令式展开 |
| Enhanced enums | 普通 `Class` + `Procedure` |
| Wildcards (`_`) | 解析层处理，Kernel 中无痕迹 |
| ++/-- | `VariableSet(x, MethodInvocation(x, '+', 1))` |
| 复合赋值 (+=, ??= 等) | 展开为读取 + 运算 + 写入 |
| Type aliases (typedef) | 展开为底层类型引用 |
| `StringConcatenation` | 编译器直接处理：生成各部分求值 + 字符串拼接指令序列 |
| `Let` | CFE 内部绑定表达式，编译为临时变量赋值 + 体表达式求值 |
| `RecordLiteral` / `RecordType` | Dart 3 记录类型，编译为记录对象创建指令 |
| `ListConcatenation` / `SetConcatenation` / `MapConcatenation` | const 上下文中的集合合并，编译期在常量池中完成拼接 |
| `LoadLibrary` / `CheckLibraryIsLoaded` | dartic 不支持延迟加载，编译器遇到 `deferred as` 导入时报错 |

**Pattern 脱糖验证**：CFE 生成 linked-platform `.dill` 时，Dart 3 的 `PatternSwitchStatement`、`IfCaseStatement`、`PatternVariableDeclaration`、`PatternAssignment`、`SwitchExpression` 等节点应已被脱糖为基础控制流。实施前需实际验证——编译含 pattern matching 的 `.dill` 并检查 AST 中是否仍保留 Pattern 节点。若未脱糖，需补充 pattern 编译策略。

## 编译产物格式 (.darticb)

```
DarticB 文件格式
┌─────────────────────────────────┐
│ Magic: 0xDART1B00 (4 bytes)     │
│ Version: UInt32                  │
│ Checksum: UInt32 (CRC32)        │
├─────────────────────────────────┤
│ 绑定名称表                       │
│   [bindingCount]                 │
│   每个条目: (符号名, argCount)    │
│   (如 "dart:core::List::add", 2) │
│   字节码中 CALL_HOST 的 Bx 操作数  │
│   是此表的本地索引（16-bit）     │
├─────────────────────────────────┤
│ 常量池                           │
│   refs: [length, data...]        │
│   ints: [length, data...]        │
│   doubles: [length, data...]     │
│   names: [length, data...]       │
├─────────────────────────────────┤
│ 函数表                           │
│   [funcCount, DarticFuncProto...]      │
│   每个 DarticFuncProto:                │
│     name, paramCount, regCount   │
│     bytecode: Uint32[]           │
│     exceptionTable               │
│     icSlotCount                  │
│     upvalueDescs                 │
│     sourceMap (optional)         │
├─────────────────────────────────┤
│ 类表                             │
│   [classCount, DarticClassInfo...]     │
│   每个 DarticClassInfo:                │
│     name, superClassId           │
│     refFieldCount, valueFieldCount│
│     methodTable, typeParamCount  │
├─────────────────────────────────┤
│ 全局变量表                        │
│   [globalCount]                  │
│   每个 GlobalVar:                 │
│     name, initializerFuncId      │
│     (惰性初始化函数引用，-1=无)     │
├─────────────────────────────────┤
│ 入口点: funcId                   │
└─────────────────────────────────┘
```

**序列化与运行时命名映射**：`.darticb` 的序列化字段名与 Ch2 运行时类的字段名存在对应关系：`methodTable` → `DarticClassInfo.methods`，`refFieldCount`/`valueFieldCount` → `DarticClassInfo.refFieldCount`/`DarticClassInfo.valueFieldCount`，`typeParamCount` → `DarticClassInfo.typeParamCount`。序列化存储紧凑形式（计数值、偏移量），运行时反序列化为结构化对象。

**编译期与运行时的解耦**：编译器不需要知道运行时 `HostBindings` 的注册顺序。`.darticb` 存储完整的绑定名称表，运行时按名称解析。这使得编译产物与 Bridge 库版本解耦——只要符号名存在，ID 如何分配无关紧要。加载时符号解析流程（校验 → 绑定名称解析 → 数据加载）和 `CALL_HOST` 运行时分发详见 Ch2 运行时加载、Ch3 宿主函数注册表。

## 关键约束与边界条件

| 约束 | 限制值 | 来源 |
|------|--------|------|
| 寄存器编号 | 0-255（8 位） | Ch1 ABC 编码格式中 A/B/C 各 8 位 |
| 本地绑定索引 | 0-65535（16 位） | Ch1 ABx 编码格式中 Bx 16 位 |
| 跳转偏移（有符号） | -32767 ~ +32768 | Ch1 AsBx 编码格式，excess-K |
| 常量池索引 | 0-65535（16 位）或 0-16777215（24 位 Ax） | 16 位用 ABx，超出用 WIDE 前缀或 Ax 格式 |
| 函数参数数量 | ≤ 255 | 8 位寄存器编码限制 |
| 异常处理器表大小 | 每函数无硬上限，但嵌套深度受寄存器数约束 | 编译器按 (startPC, endPC) 排序保证内层优先匹配 |
| 闭包上值数量 | 每闭包 ≤ 256 个上值 | 上值索引 8 位编码（WIDE 可扩展） |
| 全局变量数量 | 0-65535 | 16 位索引 |

## 已知局限与演进路径

| 局限 | 影响 | Phase 2 计划 |
|------|------|-------------|
| 作用域级寄存器分配 | 寄存器利用率低于最优，async 帧快照偏大 | LSRA 线性扫描。触发条件：profiling 显示帧尺寸影响缓存局部性 |
| 无优化遍 | 生成代码存在冗余（不可达代码、常量重复计算） | 常量折叠、窥孔优化、死代码消除、Superinstruction。触发条件：profiling 数据确定优先级 |
| 单一编译单元 | 无增量编译，每次全量编译 | 按库增量编译 + 链接。触发条件：编译时间成为开发体验瓶颈 |
| switch 优化有限 | 稀疏 case 使用二分查找而非哈希表 | 哈希表跳转。触发条件：profiling 显示 switch 分发是热点 |

> **Phase 2**：优化遍（常量折叠、窥孔优化、死代码消除、Superinstruction）。触发条件：profiling 数据指导优先级排序后实施。

## 附录：参考实现

<details>
<summary>作用域级寄存器分配器</summary>

```dart
class RegisterAllocator {
  int _next = 0, _max = 0;
  final List<int> _freePool = [];

  int alloc() {
    if (_freePool.isNotEmpty) return _freePool.removeLast();
    final r = _next++;
    if (r > _max) _max = r;
    return r;
  }

  void free(int reg) => _freePool.add(reg);
  int get maxUsed => _max;
}
```

</details>

<details>
<summary>StackKind 类型分类</summary>

```dart
StackKind classifyType(DartType type) {
  if (type is InterfaceType) {
    final cls = type.classNode;
    if (cls == coreTypes.intClass) return StackKind.value;
    if (cls == coreTypes.doubleClass) return StackKind.value;
    if (cls == coreTypes.boolClass) return StackKind.value;
  }
  return StackKind.ref;
}
```

</details>

<details>
<summary>异常处理器表结构</summary>

```dart
// 每个保护区域记录的元组字段
// startPC     — try 块起始字节码位置
// endPC       — try 块结束字节码位置
// handlerPC   — catch 处理器入口
// catchType   — 常量池中的类型索引（-1 = catch-all）
// valStackDP  — 进入 try 时的值栈深度（异常时回退）
// refStackDP  — 进入 try 时的引用栈深度（异常时回退）
//
// 排序规则：按 (startPC, endPC) 排序，内层 try 范围更小排在前面
// 运行时顺序扫描，返回第一个匹配的处理器
```

</details>
