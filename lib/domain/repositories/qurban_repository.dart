import 'package:masjid_app/domain/entities/qurban.dart';

abstract class QurbanRepository {
  Stream<List<QurbanPackage>> watchPackages();
  Stream<List<QurbanParticipantProgress>> watchParticipantProgress();
  Stream<List<QurbanPayment>> watchPaymentsForParticipant(int participantId);

  Future<List<QurbanPackage>> getPackages();
  Future<List<QurbanParticipantProgress>> getParticipantProgress();
  Future<List<QurbanPayment>> getPaymentsForParticipant(int participantId);

  Future<void> addPackage(QurbanPackage package);
  Future<void> updatePackage(QurbanPackage package);
  Future<void> deletePackage(int id);

  Future<void> addParticipant(QurbanParticipant participant);
  Future<void> updateParticipant(QurbanParticipant participant);
  Future<void> deleteParticipant(int id);

  Future<void> addPayment(QurbanPayment payment);
  Future<void> updatePayment(QurbanPayment payment);
  Future<void> deletePayment(int id);
}
