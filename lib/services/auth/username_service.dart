class UsernameService {
  UsernameService._();
  static final instance = UsernameService._();

  // In a real app, this would make a network request to a backend.
  // For this example, we'll just simulate it.
  final _takenUsernames = ['admin', 'root', 'user', 'test'];

  Future<bool> isUsernameAvailable(String username) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    return !_takenUsernames.contains(username.toLowerCase());
  }
}
