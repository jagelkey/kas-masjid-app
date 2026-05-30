import 'package:masjid_app/domain/entities/audit_log.dart';

abstract class AuditLogRepository {
  Future<void> logActivity({
    required String action,
    String? targetTable,
    String? recordId,
    String? description,
  });

  Stream<List<AuditLog>> watchLogs(); // For admin view
}
