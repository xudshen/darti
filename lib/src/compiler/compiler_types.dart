part of 'compiler.dart';

/// Type classification, inference, and operator lookup tables
/// for [DarticCompiler].
extension on DarticCompiler {
  // ── Type classification ──

  /// Infers the static DartType of an expression without StaticTypeContext.
  ///
  /// Handles common cases needed for Phase 1 int arithmetic specialization.
  ir.DartType? _inferExprType(ir.Expression expr) =>
      expr.accept(_typeInferVisitor);

  /// Infers the return type of an [ir.InstanceInvocation].
  ///
  /// For chained operations like (a + b) - c, propagates the receiver's
  /// specific type rather than using the generic `num` return type.
  ir.DartType? _inferInstanceInvocationType(ir.InstanceInvocation expr) {
    final targetClass = expr.interfaceTarget.enclosingClass;
    final invName = expr.name.text;

    // Comparison operators always return bool, regardless of receiver type.
    if (_isCompareOp(invName)) {
      return _coreTypes.boolNonNullableRawType;
    }

    if (targetClass == _coreTypes.numClass ||
        targetClass == _coreTypes.intClass) {
      final receiverType = _inferExprType(expr.receiver);
      if (receiverType != null && _isIntType(receiverType)) {
        // int `/` returns double; toDouble() returns double.
        if (invName == '/' || invName == 'toDouble') {
          return _coreTypes.doubleNonNullableRawType;
        }
        return _coreTypes.intNonNullableRawType;
      }
      if (receiverType != null && _isDoubleType(receiverType)) {
        if (invName == 'toInt') {
          return _coreTypes.intNonNullableRawType;
        }
        return _coreTypes.doubleNonNullableRawType;
      }
    }

    if (targetClass == _coreTypes.doubleClass) {
      if (invName == 'toInt') {
        return _coreTypes.intNonNullableRawType;
      }
      return _coreTypes.doubleNonNullableRawType;
    }

    // Use Kernel's substituted functionType rather than the raw declaration
    // returnType, so generic method return types are resolved (e.g., `T`
    // becomes `int` for `Box<int>.getValue()`).
    return expr.functionType.returnType;
  }

  bool _isIntType(ir.DartType type) =>
      type is ir.InterfaceType && type.classNode == _coreTypes.intClass;

  bool _isDoubleType(ir.DartType type) =>
      type is ir.InterfaceType && type.classNode == _coreTypes.doubleClass;

  bool _isBoolType(ir.DartType type) =>
      type is ir.InterfaceType && type.classNode == _coreTypes.boolClass;

  ir.DartType? _inferConstantType(ir.Constant constant) => switch (constant) {
        ir.IntConstant() => _coreTypes.intNonNullableRawType,
        ir.DoubleConstant() => _coreTypes.doubleNonNullableRawType,
        ir.BoolConstant() => _coreTypes.boolNonNullableRawType,
        ir.StringConstant() => _coreTypes.stringNonNullableRawType,
        ir.NullConstant() => const ir.NullType(),
        ir.InstanceConstant(:final classNode, :final typeArguments) =>
          ir.InterfaceType(
            classNode,
            ir.Nullability.nonNullable,
            typeArguments,
          ),
        ir.TypeLiteralConstant() =>
          _coreTypes.typeRawType(ir.Nullability.nonNullable),
        ir.InstantiationConstant(:final tearOffConstant) =>
          _inferConstantType(tearOffConstant),
        _ => null,
      };

  /// Classifies a DartType for expression result location (value or ref).
  ///
  /// Derived from [_classifyStackKind] to avoid duplicating the type-to-stack
  /// classification logic.
  ResultLoc _classifyType(ir.DartType type) =>
      _classifyStackKind(type).isValue ? ResultLoc.value : ResultLoc.ref;

  /// Classifies a DartType for scope-level register allocation.
  ///
  /// Canonical type classification: int/bool -> intVal (value stack intView),
  /// double -> doubleVal (value stack doubleView),
  /// everything else -> ref (ref stack).
  StackKind _classifyStackKind(ir.DartType type) {
    if (type is ir.InterfaceType) {
      // Nullable value types (int?, bool?, double?) must go on the ref stack
      // because only ref registers can represent null.
      if (type.nullability == ir.Nullability.nullable) return StackKind.ref;
      final cls = type.classNode;
      if (cls == _coreTypes.intClass) return StackKind.intVal;
      if (cls == _coreTypes.boolClass) return StackKind.intVal;
      if (cls == _coreTypes.doubleClass) return StackKind.doubleVal;
    }
    return StackKind.ref;
  }

  /// Walks the supertype chain of [from] to find [target], returning
  /// the type arguments that [from] passes to [target].
  /// Performs transitive substitution through intermediate classes.
  /// Returns null if [target] is not found in the supertype chain.
  List<ir.DartType>? _findSuperTypeArgs(ir.Class from, ir.Class target) {
    ir.Supertype? current = from.supertype;
    while (current != null) {
      if (current.classNode == target) {
        return current.typeArguments;
      }
      final nextSuper = current.classNode.supertype;
      if (nextSuper == null) return null;
      // Substitute accumulated type args into the next level's type args.
      if (current.classNode.typeParameters.isNotEmpty &&
          current.typeArguments.isNotEmpty) {
        final sub = type_algebra.Substitution.fromPairs(
          current.classNode.typeParameters,
          current.typeArguments,
        );
        current = ir.Supertype(
          nextSuper.classNode,
          nextSuper.typeArguments.map(sub.substituteType).toList(),
        );
      } else {
        current = nextSuper;
      }
    }
    return null;
  }
}

/// Visitor that infers the static [ir.DartType] of an expression.
///
/// Unlike the compilation visitor, `defaultExpression` returns `null`
/// (unknown type) rather than throwing — callers handle null gracefully.
class _ExprTypeInferVisitor
    with ir.ExpressionVisitorDefaultMixin<ir.DartType?> {
  _ExprTypeInferVisitor(this._compiler);
  final DarticCompiler _compiler;

  @override
  ir.DartType? defaultExpression(ir.Expression node) => null;

  @override
  ir.DartType? visitVariableGet(ir.VariableGet node) =>
      node.promotedType ?? node.variable.type;
  @override
  ir.DartType? visitIntLiteral(ir.IntLiteral node) =>
      _compiler._coreTypes.intNonNullableRawType;
  @override
  ir.DartType? visitDoubleLiteral(ir.DoubleLiteral node) =>
      _compiler._coreTypes.doubleNonNullableRawType;
  @override
  ir.DartType? visitBoolLiteral(ir.BoolLiteral node) =>
      _compiler._coreTypes.boolNonNullableRawType;
  @override
  ir.DartType? visitStringLiteral(ir.StringLiteral node) =>
      _compiler._coreTypes.stringNonNullableRawType;
  @override
  ir.DartType? visitNullLiteral(ir.NullLiteral node) =>
      const ir.NullType();
  @override
  ir.DartType? visitConstantExpression(ir.ConstantExpression node) =>
      _compiler._inferConstantType(node.constant);
  @override
  ir.DartType? visitNot(ir.Not node) =>
      _compiler._coreTypes.boolNonNullableRawType;
  @override
  ir.DartType? visitLogicalExpression(ir.LogicalExpression node) =>
      _compiler._coreTypes.boolNonNullableRawType;
  @override
  ir.DartType? visitEqualsNull(ir.EqualsNull node) =>
      _compiler._coreTypes.boolNonNullableRawType;
  @override
  ir.DartType? visitEqualsCall(ir.EqualsCall node) =>
      _compiler._coreTypes.boolNonNullableRawType;
  @override
  ir.DartType? visitConditionalExpression(ir.ConditionalExpression node) =>
      node.staticType;
  @override
  ir.DartType? visitLet(ir.Let node) =>
      _compiler._inferExprType(node.body);
  @override
  ir.DartType? visitBlockExpression(ir.BlockExpression node) =>
      _compiler._inferExprType(node.value);
  @override
  ir.DartType? visitNullCheck(ir.NullCheck node) {
    final operandType = _compiler._inferExprType(node.operand);
    if (operandType is ir.InterfaceType &&
        operandType.nullability == ir.Nullability.nullable) {
      return operandType.withDeclaredNullability(ir.Nullability.nonNullable);
    }
    return operandType;
  }

  @override
  ir.DartType? visitStaticGet(ir.StaticGet node) {
    final target = node.targetReference.asMember;
    if (target is ir.Field) return target.type;
    if (target is ir.Procedure) return target.function.returnType;
    return null;
  }

  @override
  ir.DartType? visitIsExpression(ir.IsExpression node) =>
      _compiler._coreTypes.boolNonNullableRawType;
  @override
  ir.DartType? visitAsExpression(ir.AsExpression node) => node.type;
  @override
  ir.DartType? visitStaticInvocation(ir.StaticInvocation node) {
    final retType = node.target.function.returnType;
    final typeParams = node.target.function.typeParameters;
    if (typeParams.isNotEmpty && node.arguments.types.isNotEmpty) {
      return type_algebra.Substitution.fromPairs(
        typeParams, node.arguments.types,
      ).substituteType(retType);
    }
    return retType;
  }

  @override
  ir.DartType? visitInstanceInvocation(ir.InstanceInvocation node) =>
      _compiler._inferInstanceInvocationType(node);
  @override
  ir.DartType? visitConstructorInvocation(ir.ConstructorInvocation node) =>
      ir.InterfaceType(
        node.target.enclosingClass,
        ir.Nullability.nonNullable,
        node.arguments.types,
      );
  @override
  ir.DartType? visitThisExpression(ir.ThisExpression node) => null;
  @override
  ir.DartType? visitInstanceGet(ir.InstanceGet node) => node.resultType;
  @override
  ir.DartType? visitInstanceSet(ir.InstanceSet node) =>
      _compiler._inferExprType(node.value);
  @override
  ir.DartType? visitSuperMethodInvocation(ir.SuperMethodInvocation node) {
    var retType = node.interfaceTarget.function.returnType;
    final targetClass = node.interfaceTarget.enclosingClass!;
    if (_compiler._currentEnclosingClass != null &&
        targetClass.typeParameters.isNotEmpty) {
      final typeArgs = _compiler._findSuperTypeArgs(
          _compiler._currentEnclosingClass!, targetClass);
      if (typeArgs != null && typeArgs.isNotEmpty) {
        retType = type_algebra.Substitution.fromPairs(
          targetClass.typeParameters, typeArgs,
        ).substituteType(retType);
      }
    }
    final funcTypeParams = node.interfaceTarget.function.typeParameters;
    if (funcTypeParams.isNotEmpty && node.arguments.types.isNotEmpty) {
      retType = type_algebra.Substitution.fromPairs(
        funcTypeParams, node.arguments.types,
      ).substituteType(retType);
    }
    return retType;
  }

  @override
  ir.DartType? visitSuperPropertyGet(ir.SuperPropertyGet node) {
    final target = node.interfaceTarget;
    ir.DartType rawType;
    if (target is ir.Field) {
      rawType = target.type;
    } else if (target is ir.Procedure) {
      rawType = target.function.returnType;
    } else {
      return null;
    }
    final targetClass = target.enclosingClass;
    if (_compiler._currentEnclosingClass != null &&
        targetClass != null &&
        targetClass.typeParameters.isNotEmpty) {
      final typeArgs = _compiler._findSuperTypeArgs(
          _compiler._currentEnclosingClass!, targetClass);
      if (typeArgs != null && typeArgs.isNotEmpty) {
        return type_algebra.Substitution.fromPairs(
          targetClass.typeParameters, typeArgs,
        ).substituteType(rawType);
      }
    }
    return rawType;
  }

  @override
  ir.DartType? visitSuperPropertySet(ir.SuperPropertySet node) =>
      _compiler._inferExprType(node.value);
  @override
  ir.DartType? visitLocalFunctionInvocation(
          ir.LocalFunctionInvocation node) =>
      node.functionType.returnType;
  @override
  ir.DartType? visitFunctionInvocation(ir.FunctionInvocation node) =>
      node.functionType?.returnType;
  @override
  ir.DartType? visitVariableSet(ir.VariableSet node) =>
      _compiler._inferExprType(node.value);
  @override
  ir.DartType? visitStaticSet(ir.StaticSet node) =>
      _compiler._inferExprType(node.value);
  @override
  ir.DartType? visitThrow(ir.Throw node) =>
      const ir.NeverType.nonNullable();

  // Phase 4 additions
  @override
  ir.DartType? visitTypeLiteral(ir.TypeLiteral node) =>
      _compiler._coreTypes.typeRawType(ir.Nullability.nonNullable);
  @override
  ir.DartType? visitInstantiation(ir.Instantiation node) {
    // The result type is the instantiated function type.
    final innerType = _compiler._inferExprType(node.expression);
    if (innerType is ir.FunctionType && node.typeArguments.isNotEmpty) {
      return type_algebra.FunctionTypeInstantiator.instantiate(
          innerType, node.typeArguments);
    }
    return innerType;
  }
}

/// Maps int binary operator names to opcodes (arithmetic + comparison).
int? _intBinaryOp(String name) => switch (name) {
      '+' => Op.addInt,
      '-' => Op.subInt,
      '*' => Op.mulInt,
      '~/' => Op.divInt,
      '%' => Op.modInt,
      '&' => Op.bitAnd,
      '|' => Op.bitOr,
      '^' => Op.bitXor,
      '<<' => Op.shl,
      '>>' => Op.shr,
      '>>>' => Op.ushr,
      '<' => Op.ltInt,
      '<=' => Op.leInt,
      '>' => Op.gtInt,
      '>=' => Op.geInt,
      _ => null,
    };

/// Maps double binary operator names to opcodes (arithmetic + comparison).
int? _doubleBinaryOp(String name) => switch (name) {
      '+' => Op.addDbl,
      '-' => Op.subDbl,
      '*' => Op.mulDbl,
      '/' => Op.divDbl,
      '<' => Op.ltDbl,
      '<=' => Op.leDbl,
      '>' => Op.gtDbl,
      '>=' => Op.geDbl,
      _ => null,
    };

/// Returns true if the operator name is a comparison operator.
bool _isCompareOp(String name) =>
    name == '<' || name == '<=' || name == '>' || name == '>=';
