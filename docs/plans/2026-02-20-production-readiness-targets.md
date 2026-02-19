# 生产就绪目标分析 — co19 通过率与 Flutter 热更新

**日期：** 2026-02-20
**状态：** 待审阅

## 背景

dartic 的核心目标是**生产级 Flutter 热更新**。本文分析达到该目标所需的 co19 通过率，识别当前差距，并提出路线图调整建议。

## 当前状态（Phase 4 结束）

| 类别 | 测试数 | 通过 | 通过率 |
|------|--------|------|--------|
| Variables | 111 | 73 | 65.8% |
| Expressions | 1,933 | 1,032 | 53.4% |
| Statements | 537 | 268 | 49.9% |
| Functions | 187 | 135 | 72.2% |
| Classes | 845 | 649 | 76.8% |
| Reference | 554 | 451 | 81.4% |
| Generics | 195 | 143 | 73.3% |
| Mixins | 143 | 99 | 69.2% |
| Interfaces | 100 | 80 | 80.0% |
| TypeSystem/subtyping | 2,721 | 1,345 | 49.4% |
| Class-modifiers | 267 | 167 | 62.5% |
| **累计** | **7,593** | **4,566** | **60.1%** |

**适用测试基数**：co19 总计 ~24,350 测试，扣除 dart:io/isolate/ffi/mirrors/html 等不支持库（~8,500），适用测试 ~15,800。当前 4,566 pass = **28.9% 适用测试**。

**Phase 4 失败原因分布**（基于 Batch 4.4 数据）：

| 失败类型 | 占比 | 说明 |
|---------|------|------|
| 缺少 Bridge | 42.1% | Duration/print/Object 等未桥接 |
| Phase 5+ 特性缺失 | 19.7% | 集合字面量、字符串插值、for-in 等 |
| 编译器/解释器 bug | 33.2% | 已有代码路径的 bug |
| 其他 | 5.0% | |

## co19 与生产就绪的关系

**co19 是合规性测试集，不直接等于生产就绪指标。** co19 覆盖大量边界情况（泛型协变嵌套、nullable FutureOr 特殊规则、pattern exhaustiveness 等），生产级 Flutter 热更新脚本极少触碰这些。

**真正关键的是：常用模式的正确性 × 覆盖率。** 因此按类别设定目标比追求整体数字更有意义。

## 生产就绪三层定义

### 层级 1：可演示 MVP

**场景**：公司内部展示、技术博客 demo、概念验证

**能力要求**：
- 简单 Widget 树构建（StatelessWidget.build）
- 基本 String/int/List 操作
- 简单条件逻辑、循环
- 不需要 async，不需要复杂泛型

**co19 目标**：

| 类别 | 目标 |
|------|------|
| Classes / Functions / Reference | >80% |
| Variables / Expressions / Statements | >70% |
| Generics / Mixins / Interfaces | >70% |
| LibTest/core | >30% |
| **整体适用测试** | **~55-60%** |

**绝对数字**：~8,700-9,500 / 15,800

**预计达成时间**：Phase 5 结束

### 层级 2：受限生产级（推荐目标）

**场景**：生产环境使用，配合**脚本编写指南**——告知开发者可用/应避免的 Dart 模式

**Flutter 热更新脚本的典型代码模式**：

```dart
// 必须 100% 正确的核心模式：
class HomeScreen extends ScreenBuilder {         // 类继承 + 方法重写
  @override
  Widget build(BuildContext context) {
    final items = ['A', 'B', 'C'];              // 集合字面量
    final title = 'Hello ${user.name}';          // 字符串插值
    return Scaffold(                             // 多层构造器嵌套
      appBar: AppBar(title: Text(title)),        // 命名参数
      body: items.isEmpty                        // getter + 条件表达式
        ? Center(child: Text('No items'))
        : ListView.builder(
            itemCount: items.length,
            itemBuilder: (ctx, i) => ListTile(   // 闭包 + 索引访问
              title: Text(items[i]),
              onTap: () => onItemTap(items[i]),   // 回调
            ),
          ),
    );
  }
}

// async 数据加载
Future<List<Item>> fetchItems() async {
  final response = await apiClient.get('/items'); // async/await
  final list = response.data as List;             // 类型转换
  return list.map((e) => Item.fromJson(e)).toList(); // 高阶方法
}
```

**co19 目标**：

| 类别 | 目标 | 当前 | 差距 | 说明 |
|------|------|------|------|------|
| Classes | >90% | 76.8% | +13% | OOP 是 Flutter 核心 |
| Functions | >90% | 72.2% | +18% | 闭包/回调无处不在 |
| Reference | >90% | 81.4% | +9% | 名称解析必须正确 |
| Variables | >90% | 65.8% | +24% | 基础功能 |
| Expressions | >80% | 53.4% | +27% | 运算符/类型测试 |
| Statements | >80% | 49.9% | +30% | 控制流必须可靠 |
| Generics | >80% | 73.3% | +7% | List\<Widget\> 等泛型集合 |
| Mixins | >75% | 69.2% | +6% | Flutter 常用 mixin 模式 |
| Interfaces | >85% | 80.0% | +5% | 接口契约 |
| TypeSystem/subtyping | >65% | 49.4% | +16% | 类型安全 |
| Class-modifiers | >80% | 62.5% | +18% | 全部被 print 阻塞，Bridge 后预计 >90% |
| LibTest/core | >55% | 0% | 新增 | int/String/List/Map 方法覆盖 |
| LibTest/async | >45% | 0% | 新增 | Future/async/await |
| LanguageFeatures 合计 | >55% | 0% | 新增 | Extension methods 最重要 |
| **整体适用测试** | **~70%** | **28.9%** | +41% | |

**绝对数字**：~11,000 / 15,800

**预计达成时间**：Phase 6 结束 + 加固

### 层级 3：无限制生产级

**场景**：开发者可以写任意 Dart 代码，无需脚本编写指南

**co19 目标**：

| 类别 | 目标 |
|------|------|
| 所有 Language 类别 | >95% |
| LibTest/core | >75% |
| LibTest/async | >65% |
| TypeSystem | >80% |
| LanguageFeatures 各子类别 | >75% |
| **整体适用测试** | **>80%** |

**绝对数字**：>12,600 / 15,800

**预计达成时间**：Phase 7 之后需要完整加固阶段

## 路线图预估 vs 生产目标差距

### 路线图现有预估

| Phase | 累计通过（乐观） | 累计通过（保守） | 适用测试通过率 |
|-------|----------------|----------------|---------------|
| Phase 4（当前） | 4,566 | 4,566 | 28.9% |
| Phase 5 | ~5,500 | ~4,500 | 28.5-34.8% |
| Phase 6 | ~7,500 | ~5,500 | 34.8-47.5% |
| Phase 7 | ~7,600 | ~5,600 | 35.4-48.1% |

### 与层级 2 目标的差距

| | 路线图乐观 | 生产目标 | 差距 |
|--|----------|---------|------|
| Phase 6 结束 | ~7,500 (47%) | ~11,000 (70%) | **~3,500** |
| Phase 7 结束 | ~7,600 (48%) | ~11,000 (70%) | **~3,400** |

### 差距来源分析

| 差距来源 | 估算缺口 | 说明 |
|---------|---------|------|
| 编译器/解释器 bug | ~1,000 | Phase 4 数据显示 33.2% 失败是 bug，分布在所有历史类别 |
| Expressions/Statements 边界 | ~800 | dynamic dispatch、tear-off、更多运算符边界 |
| LanguageFeatures 深度 | ~800 | Patterns 复杂度高，初始通过率可能偏低 |
| LibTest/core 深度 | ~500 | 标准库方法覆盖面超出基础子集 |
| TypeSystem dynamic | ~400 | Duration bridge + 运行时类型检查完善 |

## 路线图调整建议

### 方案 A：各 Phase 主动修 bug（推荐）

在现有 Phase 5-6 中增加**主动 bug 修复任务**，而非仅"碰到再修"：

- **Phase 5**：利用 Batch 4.4 的 Top 10 失败原因数据，在实现 Bridge 的同时修复已知编译器 bug
  - 预计额外收益：+500-800 pass（从 33.2% bug 池中恢复）
  - 具体：RangeError 寄存器溢出 (126)、Null check 失败 (90) 等可在 Bridge 之前修复

- **Phase 6**：LanguageFeatures 各子类别初始通过率目标上调
  - Extension methods: >70%（Flutter 生态广泛使用）
  - Patterns: >50%（而非 20-30%）
  - Records: >60%

- **收益预估**：路线图乐观从 7,600 提升到 ~9,000-9,500

### 方案 B：增加 Phase 8 加固期

Phase 7 之后增加专门的加固阶段：

| Batch | 内容 | 预计收益 |
|-------|------|---------|
| 8.1 | co19 失败分析 → top N bug 批量修复 | +800-1,000 |
| 8.2 | 标准库方法覆盖率提升（补全 String/List/Map 次常用方法） | +300-500 |
| 8.3 | Dynamic dispatch / tear-off / 剩余边界补全 | +200-400 |
| 8.4 | 生产冒烟测试集（模拟 20 个真实 Flutter 热更新脚本） | 验收 |

**收益预估**：+1,300-1,900 pass

### 综合推荐：A + B 混合

1. Phase 5-6 中主动修 bug → 到 ~9,000-9,500 pass（~57-60% 适用）
2. Phase 7 正常执行 → API 封装
3. 根据 Phase 6 结束时的实际数字决定 Phase 8 规模：
   - 如果 >10,000 → 轻量加固（1-2 batch）
   - 如果 8,000-10,000 → 标准加固（4 batch）
   - 如果 <8,000 → 重新评估路线

## 核心指标仪表盘

建议每个 Phase 结束时追踪以下指标，判断是否在通往生产级的正确路径上：

| 指标 | Phase 5 目标 | Phase 6 目标 | 生产目标 |
|------|------------|------------|---------|
| Classes 通过率 | >85% | >90% | >90% |
| Functions 通过率 | >85% | >90% | >90% |
| Expressions 通过率 | >65% | >80% | >80% |
| Statements 通过率 | >65% | >80% | >80% |
| LibTest/core 通过率 | >35% | >55% | >55% |
| LibTest/async 通过率 | — | >45% | >45% |
| 累计适用通过率 | >38% | >57% | >70% |
| 累计绝对通过数 | >6,000 | >9,000 | >11,000 |
| 历史回归 | 0 | 0 | 0 |

## 与竞品对比

| 引擎 | 目标语言 | 合规性 | 生产使用情况 |
|------|---------|--------|-------------|
| dart_eval | Dart 子集 | 无 co19 数据 | 少量生产使用，语言特性覆盖有限 |
| Lua (PUC-Rio) | Lua | 完整合规 | 广泛生产使用（游戏、嵌入式） |
| QuickJS | JavaScript | 通过 test262 ~95% | 生产使用（IoT、嵌入式） |
| hermes (Meta) | JavaScript | 通过 test262 ~94% | React Native 生产引擎 |

**参考**：QuickJS 和 hermes 在各自的合规性测试集上达到 ~94-95% 后被视为生产就绪。dartic 在适用测试上达到 ~70% 可以配合脚本指南生产使用，达到 ~80% 可以无限制使用。

## 结论

- **生产级 Flutter 热更新 = 层级 2（受限生产）**，目标 **co19 适用测试 ~70%（~11,000 pass）**
- **核心语言类别 >90%** 比整体数字更重要
- 当前路线图乐观到 ~48%，需要在 Phase 5-6 中更主动修 bug + 可能的 Phase 8 加固
- 每个 Phase 结束时用仪表盘指标判断进度
