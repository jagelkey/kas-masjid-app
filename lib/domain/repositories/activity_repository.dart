import 'package:masjid_app/domain/entities/activity.dart';

abstract class ActivityRepository {
  Stream<List<Activity>> watchActivities();
  Future<List<Activity>> getActivities();
  Future<void> addActivity(Activity activity);
  Future<void> updateActivity(Activity activity);
  Future<void> deleteActivity(int id);
}
