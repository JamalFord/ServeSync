class Employee {
  final String id;
  final String name;
  final String role; // "Administrator", "Manager", "FOH Staff"
  final String pin;
  final double hourlyRate;
  bool isClockedIn;
  DateTime? clockInTime;

  Employee({
    required this.id,
    required this.name,
    required this.role,
    required this.pin,
    required this.hourlyRate,
    this.isClockedIn = false,
    this.clockInTime,
  });

  bool get isAdmin => role == 'Administrator';
  bool get isManager => role == 'Manager' || isAdmin;
  bool get isStaff => role == 'FOH Staff';

  factory Employee.fromMap(Map<String, dynamic> data, String id) {
    return Employee(
      id: id,
      name: data['full_name'] ?? 'Unknown Employee',
      role: data['role'] ?? 'FOH Staff',
      pin: data['pin'] ?? '1234',
      hourlyRate: (data['hourly_rate'] ?? 16.50).toDouble(),
      isClockedIn: data['is_clocked_in'] ?? false,
      clockInTime: data['clock_in_time'] != null
          ? DateTime.tryParse(data['clock_in_time'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'full_name': name,
      'role': role,
      'pin': pin,
      'hourly_rate': hourlyRate,
      'is_clocked_in': isClockedIn,
      'clock_in_time': clockInTime?.toIso8601String(),
    };
  }
}
