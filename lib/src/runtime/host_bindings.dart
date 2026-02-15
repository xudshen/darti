typedef HostFn = Object? Function(List<Object?> args);

class HostBindings {
  final List<HostFn> _functions = [];
  final Map<String, int> _nameToId = {};

  int register(String name, HostFn fn) {
    final id = _functions.length;
    _functions.add(fn);
    _nameToId[name] = id;
    return id;
  }

  int? getId(String name) => _nameToId[name];

  Object? invoke(int id, List<Object?> args) => _functions[id](args);
}
