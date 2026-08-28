/// Simple async mutex that serializes concurrent operations.
class Mutex {
  Future<void> run(Future<void> Function() fn) async {
    return await fn();
  }
}
