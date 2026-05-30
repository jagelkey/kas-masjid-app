import 'package:masjid_app/domain/entities/user.dart';

abstract class UserRepository {
  Stream<List<UserEntity>> watchUsers();
  Future<List<UserEntity>> getUsers();
  Future<void> addUser(UserEntity user);
  Future<void> updateUser(UserEntity user);
  Future<void> deleteUser(int id);
  Future<UserEntity?> getUserByRemoteId(String remoteId);
  Future<UserEntity?> getUserByUsername(String username);
  Future<UserEntity?> getUserByEmail(String email);
  Future<UserEntity?> getUserById(int id);
}
