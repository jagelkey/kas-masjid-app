import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';

void main() {
  group('UserRole Permissions', () {
    test('Admin has full access', () {
      const role = UserRole.admin;
      expect(role.canManageTransactions, isTrue);
      expect(role.canManageActivities, isTrue);
      expect(role.canManageSettings, isTrue);
      expect(role.canManageQurban, isTrue);
    });

    test('Ketua has specific access', () {
      const role = UserRole.ketua;
      // Ketua: Dashboard (Yes), Kas (View), Kegiatan (View), Settings (Full)
      expect(role.canManageTransactions, isFalse); // Only View
      expect(role.canManageActivities, isFalse); // Only View
      expect(role.canManageSettings, isTrue); // Full Access
      expect(role.canManageQurban, isTrue);
    });

    test('Bendahara has specific access', () {
      const role = UserRole.bendahara;
      // Bendahara: Dashboard (Yes), Kas (CRUD), Kegiatan (View), Settings (View)
      expect(role.canManageTransactions, isTrue); // CRUD
      expect(role.canManageActivities, isFalse); // Only View
      expect(role.canManageSettings, isFalse); // Only View
      expect(role.canManageQurban, isTrue);
    });

    test('Sekretaris has specific access', () {
      const role = UserRole.sekretaris;
      // Sekretaris: Dashboard (Yes), Kas (View), Kegiatan (CRUD), Settings (View)
      expect(role.canManageTransactions, isFalse); // Only View
      expect(role.canManageActivities, isTrue); // CRUD
      expect(role.canManageSettings, isFalse); // Only View
      expect(role.canManageQurban, isFalse);
    });

    test('Viewer has read-only access', () {
      const role = UserRole.viewer;
      // Viewer: Dashboard (Yes), Kas (View), Kegiatan (View), Settings (View)
      expect(role.canManageTransactions, isFalse);
      expect(role.canManageActivities, isFalse);
      expect(role.canManageSettings, isFalse);
      expect(role.canManageQurban, isFalse);
    });
  });
}
