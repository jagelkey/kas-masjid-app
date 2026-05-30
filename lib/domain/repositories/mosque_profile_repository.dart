import 'package:masjid_app/domain/entities/mosque_profile.dart';

abstract class MosqueProfileRepository {
  Future<MosqueProfile?> getProfile();
  Future<void> saveProfile(MosqueProfile profile);
}
