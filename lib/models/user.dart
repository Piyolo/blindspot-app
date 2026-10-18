/// A user profile as returned by the API (`/auth/*`, `/me`) and persisted
/// locally by the session repository.
///
/// Field names mirror the backend's `UserOut` schema exactly:
/// `id`, `name`, `email`, `contact_number`, `created_at`.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.contactNumber,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String email;
  final String contactNumber;

  /// Account creation time parsed from the API's ISO-8601 `created_at`.
  final DateTime createdAt;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        contactNumber: json['contact_number'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// Persistable shape: identical key names to [fromJson] so a stored user
  /// round-trips back through it unchanged.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'email': email,
        'contact_number': contactNumber,
        'created_at': createdAt.toIso8601String(),
      };
}
