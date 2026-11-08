/// The `user` object returned by `POST /api/auth/login/` and `GET /api/auth/me/`.
class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.isAdmin,
    required this.isRider,
    required this.isCustomer,
    required this.role,
  });

  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String phone;

  final bool isAdmin;
  final bool isRider;
  final bool isCustomer;

  /// "admin" | "rider" | "customer", computed server-side.
  final String role;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? username : full;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] ?? 0) as int,
        username: (json['username'] ?? '') as String,
        email: (json['email'] ?? '') as String,
        firstName: (json['first_name'] ?? '') as String,
        lastName: (json['last_name'] ?? '') as String,
        phone: (json['phone'] ?? '') as String,
        isAdmin: (json['is_admin'] ?? false) as bool,
        isRider: (json['is_rider'] ?? false) as bool,
        isCustomer: (json['is_customer'] ?? false) as bool,
        role: (json['role'] ?? 'customer') as String,
      );
}
