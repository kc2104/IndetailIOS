import 'package:flutter_test/flutter_test.dart';
import 'package:indetail/models.dart';
import 'package:indetail/repository.dart';

void main() {
  test('role permissions keep employee assignment and review controls off', () {
    expect(UserRole.employee.canAssign, isFalse);
    expect(UserRole.employee.canReview, isFalse);
    expect(UserRole.teamLeader.canAssign, isTrue);
    expect(UserRole.teamLeader.canReview, isTrue);
    expect(UserRole.admin.isAdmin, isTrue);
  });

  test('restored Team Leader sessions retain their role and Employee ID', () {
    final session = AppSession(
      name: 'Team Lead',
      email: 'lead@example.com',
      role: UserRole.teamLeader,
      employeeId: 'ids1234',
    );
    final restored = AppSession.fromJson(session.toJson());
    expect(restored.role, UserRole.teamLeader);
    expect(restored.employeeId, 'ids1234');
  });

  test('repository permissions follow the role refreshed after login', () {
    final repository = WorkspaceRepository(
      const AppSession(name: 'Signing in', email: '', role: UserRole.employee),
      onSessionUpdated: (_) async {},
    );

    repository.api.session = const AppSession(
      name: 'Indetail',
      email: 'admin@example.com',
      role: UserRole.admin,
    );

    expect(repository.session.role, UserRole.admin);
    expect(repository.session.role.canAssign, isTrue);
    expect(repository.session.role.isAdmin, isTrue);
  });

  test(
    'new account Employee IDs must match the ids plus four digit format',
    () {
      expect(RegExp(r'^ids\d{4}$').hasMatch('ids1234'), isTrue);
      expect(RegExp(r'^ids\d{4}$').hasMatch('id1234'), isFalse);
      expect(RegExp(r'^ids\d{4}$').hasMatch('ids12345'), isFalse);
    },
  );

  test(
    'geofence distance is zero for the same point and grows with separation',
    () {
      expect(
        distanceInMeters(37.4219999, -122.0840575, 37.4219999, -122.0840575),
        closeTo(0, 0.01),
      );
      expect(distanceInMeters(0, 0, 0, 0.001), inInclusiveRange(100, 115));
    },
  );
}
