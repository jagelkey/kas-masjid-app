import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/domain/entities/mosque_profile.dart' as domain;
import 'package:masjid_app/domain/entities/transaction.dart' as domain_status;
import 'package:masjid_app/domain/repositories/mosque_profile_repository.dart';

import 'package:masjid_app/domain/repositories/audit_log_repository.dart';

@LazySingleton(as: MosqueProfileRepository)
class MosqueProfileRepositoryImpl implements MosqueProfileRepository {
  final AppDatabase _db;
  final AuditLogRepository _auditLogRepository;

  MosqueProfileRepositoryImpl(this._db, this._auditLogRepository);

  @override
  Future<domain.MosqueProfile?> getProfile() async {
    final row = await _db.select(_db.mosqueProfiles).getSingleOrNull();
    if (row == null) return null;

    // Logic to separate local path and remote URL stored in the same column
    String? localPath;
    String? remoteUrl;

    if (row.logoPath != null) {
      if (row.logoPath!.startsWith('http')) {
        remoteUrl = row.logoPath;
      } else {
        localPath = row.logoPath;
      }
    }

    return domain.MosqueProfile(
      id: row.id,
      name: row.name,
      address: row.address,
      logoPath: localPath,
      logoUrl: remoteUrl,
    );
  }

  @override
  Future<void> saveProfile(domain.MosqueProfile profile) async {
    // Upsert logic (since only 1 row)
    final existing = await _db.select(_db.mosqueProfiles).getSingleOrNull();

    // Determine what to save in logoPath column
    // If local path exists, save it (it will be uploaded later).
    // If only URL exists, save URL.
    final pathOrUrl = profile.logoPath ?? profile.logoUrl;

    if (existing != null) {
      await (_db.update(
        _db.mosqueProfiles,
      )..where((t) => t.id.equals(existing.id))).write(
        MosqueProfilesCompanion(
          name: Value(profile.name),
          address: Value(profile.address),
          logoPath: Value(pathOrUrl),
          syncStatus: Value(domain_status.SyncStatus.pendingUpdate),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _auditLogRepository.logActivity(
        action: 'UPDATE',
        targetTable: 'mosque_profiles',
        recordId: existing.id.toString(),
        description: 'Updated Profile: ${profile.name}',
      );
    } else {
      await _db
          .into(_db.mosqueProfiles)
          .insert(
            MosqueProfilesCompanion(
              name: Value(profile.name),
              address: Value(profile.address),
              logoPath: Value(pathOrUrl),
              syncStatus: Value(domain_status.SyncStatus.pendingCreate),
            ),
          );

      await _auditLogRepository.logActivity(
        action: 'CREATE',
        targetTable: 'mosque_profiles',
        description: 'Created Profile: ${profile.name}',
      );
    }
  }
}
