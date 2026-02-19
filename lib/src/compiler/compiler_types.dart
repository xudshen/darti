part of 'compiler.dart';

/// Type classification, inference, and operator lookup tables
/// for [DarticCompiler].
extension on DarticCompiler {
  // ── Type classification ──

  /// Infers the static DartType of an expression without StaticTypeContext.
  ///
  /// Handles common cases needed for Phase 1 int arithmetic specialization.
  ir.DartType? _inferExprType(ir.Expression expr) {
    if (expr is ir.VariableGet) return expr.promotedType ?? expr.variable.type;
    if (expr is ir.IntLiteral) return _coreTypes.intNonNullableRawType;
    if (expr is ir.DoubleLiteral) return _coreTypes.doubleNonNullableRawType;
    if (expr is ir.BoolLiteral) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.StringLiteral) return _coreTypes.stringNonNullableRawType;
    if (expr is ir.NullLiteral) return const ir.NullType();
    if (expr is ir.ConstantExpression) return _inferConstantType(expr.constant);
    if (expr is ir.Not) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.LogicalExpression) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.EqualsNull) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.EqualsCall) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.ConditionalExpression) return expr.staticType;
    if (expr is ir.Let) return _inferExprType(expr.body);
    if (expr is ir.BlockExpression) return _inferExprType(expr.value);
    if (expr is ir.NullCheck) {
      final operandType = _inferExprType(expr.operand);
      // NullCheck produces the non-nullable version of the operand type.
      if (operandType is ir.InterfaceType &&
          operandType.nullability == ir.Nullability.nullable) {
        return operandType.withDeclaredNullability(ir.Nullability.nonNullable);
      }
      return operandType;
    }
    if (expr is ir.StaticGet) {
      final target = expr.targetReference.asMember;
      if (target is ir.Field) return target.type;
      if (target is ir.Procedure) return target.function.returnType;
    }
    if (expr is ir.IsExpression) return _coreTypes.boolNonNullableRawType;
    if (expr is ir.AsExpression) return expr.type;
    if (expr is ir.StaticInvocation) {
      final retType = expr.target.function.returnType;
      final typeParams = expr.target.function.typeParameters;
      if (typeParams.isNotEmpty && expr.arguments.types.isNotEmpty) {
        return type_algebra.Substitution.fromPairs(
          typeParams, expr.arguments.types,
        ).substituteType(retType);
      }
      return retType;
    }
    if (expr is ir.InstanceInvocation) {
      return _inferInstanceInvocationType(expr);
    }
    if (expr is ir.ConstructorInvocation) {
      return ir.InterfaceType(
        expr.target.enclosingClass,
        ir.Nullability.nonNullable,
      );
    }
    if (expr is ir.ThisExpression) {
      // ThisExpression type is the enclosing class. We can't determine it
      // statically here, but it's always a ref type.
      return null;
    }
    if (expr is ir.InstanceGet) {
      // Use Kernel's pre-computed resultType which has type parameter
      // substitutions applied (e.g., returns `int` instead of `T` for
      // a field access on `Box<int>`).
      return expr.resultType;
    }
    if (expr is ir.InstanceSet) return _inferExprType(expr.value);
    if (expr is ir.SuperMethodInvocation) {
      var retType = expr.interfaceTarget.function.returnType;
      // Step 1: Substitute class-level type params from the subclass context.
      final targetClass = expr.interfaceTarget.enclosingClass!;
      if (_currentEnclosingClass != null &&
          targetClass.typeParameters.isNotEmpty) {
        final typeArgs =
            _findSuperTypeArgs(_currentEnclosingClass!, targetClass);
        if (typeArgs != null && typeArgs.isNotEmpty) {
          retType = type_algebra.Substitution.fromPairs(
            targetClass.typeParameters,
            typeArgs,
          ).substituteType(retType);
        }
      }
      // Step 2: Substitute function-level type params if generic method.
      final funcTypeParams = expr.interfaceTarget.function.typeParameters;
      if (funcTypeParams.isNotEmpty && expr.arguments.types.isNotEmpty) {
        retType = type_algebra.Substitution.fromPairs(
          funcTypeParams,
          expr.arguments.types,
        ).substituteType(retType);
      }
      return retType;
    }
    if (expr is ir.SuperPropertyGet) {
      final target = expr.interfaceTarget;
      ir.DartType rawType;
      if (target is ir.Field) {
        rawType = target.type;
      } else if (target is ir.Procedure) {
        rawType = target.function.returnType;
      } else {
        return null;
      }
      final targetClass = target.enclosingClass;
      if (_currentEnclosingClass != null &&
          targetClass != null &&
          targetClass.typeParameters.isNotEmpty) {
        final typeArgs =
            _findSuperTypeArgs(_currentEnclosingClass!, targetClass);
        if (typeArgs != null && typeArgs.isNotEmpty) {
          return type_algebra.Substitution.fromPairs(
            targetClass.typeParameters,
            typeArgs,
          ).substituteType(rawType);
        }
      }
      return rawType;
    }
    if (expr is ir.SuperPropertySet) return _inferExprType(expr.value);
    return null;
  }

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
