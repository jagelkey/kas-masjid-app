import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:masjid_app/domain/entities/activity.dart';
import 'package:masjid_app/presentation/pages/main_page.dart';
import 'package:masjid_app/presentation/pages/dashboard_page.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/pages/transaction_form_page.dart';
import 'package:masjid_app/presentation/pages/transaction_list_page.dart';
import 'package:masjid_app/presentation/pages/login_page.dart';
import 'package:masjid_app/presentation/pages/register_page.dart';
import 'package:masjid_app/presentation/pages/register_mosque_page.dart';
import 'package:masjid_app/core/constants/env.dart';

import 'package:masjid_app/presentation/pages/user_list_page.dart';
import 'package:masjid_app/presentation/pages/activity_list_page.dart';
import 'package:masjid_app/presentation/pages/activity_form_page.dart';

import 'package:masjid_app/presentation/pages/settings_page.dart';
import 'package:masjid_app/presentation/pages/sync_center_page.dart';
import 'package:masjid_app/presentation/pages/audit_log_page.dart';
import 'package:masjid_app/presentation/pages/edit_profile_page.dart';
import 'package:masjid_app/domain/entities/qurban.dart';
import 'package:masjid_app/presentation/pages/qurban_page.dart';
import 'package:masjid_app/presentation/pages/qurban_package_settings_page.dart';
import 'package:masjid_app/presentation/pages/qurban_participant_form_page.dart';
import 'package:masjid_app/presentation/pages/qurban_payment_form_page.dart';

class GlobalAuthNotifier extends ChangeNotifier {
  bool _isOffline = false;
  bool get isOffline => _isOffline;

  void setOffline(bool value) {
    _isOffline = value;
    notifyListeners();
  }
}

final globalAuthNotifier = GlobalAuthNotifier();

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  refreshListenable: globalAuthNotifier,
  initialLocation: '/',
  redirect: (context, state) {
    if (globalAuthNotifier.isOffline) {
      if (state.uri.toString() == '/login' ||
          state.uri.toString() == '/register' ||
          state.uri.toString() == '/register-mosque') {
        return '/';
      }
      return null;
    }

    // Check if Supabase is initialized before accessing instance
    if (!Env.hasValidConfig) {
      // If no config, maybe force login or offline?
      // For now, let's assume offline if no config
      return null;
    }

    Session? session;
    try {
      // Check if Supabase.instance is actually initialized
      // There is no public property to check initialization state directly in this version easily
      // but accessing .client might throw if not initialized?
      // Actually Supabase.instance throws if not initialized.
      session = Supabase.instance.client.auth.currentSession;
    } catch (_) {
      // If instance not initialized or other error
      session = null;
    }

    final isLoggingIn = state.uri.toString() == '/login';
    final isRegistering = state.uri.toString() == '/register';
    final isRegisteringMosque = state.uri.toString() == '/register-mosque';

    if (session == null &&
        !isLoggingIn &&
        !isRegistering &&
        !isRegisteringMosque) {
      return '/login';
    }

    if (session != null &&
        (isLoggingIn || isRegistering || isRegisteringMosque)) {
      return '/';
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/register-mosque',
      name: 'register-mosque',
      builder: (context, state) => const RegisterMosquePage(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainPage(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          name: 'dashboard',
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: '/transactions',
          name: 'transactions',
          builder: (context, state) => const TransactionListPage(),
          routes: [
            GoRoute(
              path: 'add',
              parentNavigatorKey: _rootNavigatorKey, // Full screen
              builder: (context, state) => const TransactionFormPage(),
            ),
            GoRoute(
              path: 'edit',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final transaction = state.extra as Transaction;
                return TransactionFormPage(transaction: transaction);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/activities',
          name: 'activities',
          builder: (context, state) => const ActivityListPage(),
          routes: [
            GoRoute(
              path: 'add',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const ActivityFormPage(),
            ),
            GoRoute(
              path: 'edit',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final activity = state.extra as Activity;
                return ActivityFormPage(activity: activity);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/qurban',
          name: 'qurban',
          builder: (context, state) => const QurbanPage(),
          routes: [
            GoRoute(
              path: 'packages',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const QurbanPackageSettingsPage(),
            ),
            GoRoute(
              path: 'participant/add',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const QurbanParticipantFormPage(),
            ),
            GoRoute(
              path: 'participant/edit',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final participant = state.extra as QurbanParticipant;
                return QurbanParticipantFormPage(participant: participant);
              },
            ),
            GoRoute(
              path: 'participant/detail',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final progress = state.extra as QurbanParticipantProgress;
                return QurbanParticipantDetailPage(progress: progress);
              },
            ),
            GoRoute(
              path: 'payment/add',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final participant = state.extra as QurbanParticipant;
                return QurbanPaymentFormPage(participant: participant);
              },
            ),
            GoRoute(
              path: 'payment/edit',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) {
                final args = state.extra as QurbanPaymentFormArgs;
                return QurbanPaymentFormPage(
                  participant: args.participant,
                  payment: args.payment,
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsPage(),
          routes: [
            GoRoute(
              path: 'edit-profile',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const EditProfilePage(),
            ),
            GoRoute(
              path: 'users',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const UserListPage(),
            ),
            GoRoute(
              path: 'audit-logs',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const AuditLogPage(),
            ),
            GoRoute(
              path: 'sync',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const SyncCenterPage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
