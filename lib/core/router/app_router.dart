import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:masjid_app/domain/entities/activity.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart'
    show UserRole;
import 'package:masjid_app/presentation/pages/main_page.dart';
import 'package:masjid_app/presentation/pages/dashboard_page.dart';
import 'package:masjid_app/domain/entities/transaction.dart';
import 'package:masjid_app/presentation/pages/transaction_form_page.dart';
import 'package:masjid_app/presentation/pages/transaction_list_page.dart';
import 'package:masjid_app/presentation/pages/login_page.dart';
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

  // Mirrors the current session's role so the router's redirect (a plain
  // top-level GoRouter, not a widget) can enforce role-based access without
  // depending on BuildContext/Provider lookups. AuthBloc keeps this in sync
  // on every login/logout/registration.
  UserRole? _currentRole;
  UserRole? get currentRole => _currentRole;

  void setOffline(bool value) {
    _isOffline = value;
    notifyListeners();
  }

  void setRole(UserRole? role) {
    _currentRole = role;
    notifyListeners();
  }
}

final globalAuthNotifier = GlobalAuthNotifier();

// Routes that mutate data and must be restricted to specific roles even
// though RLS already blocks the underlying writes -- without this, a
// non-privileged user reaches the form, sees a false "success" (local
// insert), and only fails silently in the background at sync time.
bool Function(UserRole)? _permissionForPath(String path) {
  const transactionPaths = {'/transactions/add', '/transactions/edit'};
  const activityPaths = {'/activities/add', '/activities/edit'};
  const qurbanPaths = {
    '/qurban/packages',
    '/qurban/participant/add',
    '/qurban/participant/edit',
    '/qurban/payment/add',
    '/qurban/payment/edit',
  };
  const settingsPaths = {'/settings/users', '/settings/audit-logs'};

  if (transactionPaths.contains(path)) {
    return (role) => role.canManageTransactions;
  }
  if (activityPaths.contains(path)) return (role) => role.canManageActivities;
  if (qurbanPaths.contains(path)) return (role) => role.canManageQurban;
  if (settingsPaths.contains(path)) return (role) => role.canManageSettings;
  return null;
}

// The only routes reachable without an authenticated session.
const _authPaths = {'/login', '/register-mosque'};

// Returns a redirect target if `path` is role-restricted and the current
// role (from globalAuthNotifier) doesn't pass, otherwise null (allow).
String? _roleRedirect(String path) {
  final permissionCheck = _permissionForPath(path);
  if (permissionCheck == null) return null;
  final role = globalAuthNotifier.currentRole;
  if (role == null || !permissionCheck(role)) return '/';
  return null;
}

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  refreshListenable: globalAuthNotifier,
  initialLocation: '/',
  redirect: (context, state) {
    final path = state.uri.path;
    final isAuthPath = _authPaths.contains(path);

    if (globalAuthNotifier.isOffline) {
      if (isAuthPath) return '/';
      return _roleRedirect(path);
    }

    if (!Env.hasValidConfig) {
      // Local-only build: there is no server session to consult, so a locally
      // restored account IS the session -- and that case is exactly what the
      // isOffline branch above handles. Reaching here therefore means nobody is
      // signed in, so only the auth screens may render. Previously this branch
      // returned _roleRedirect(path), which checks the ROLE but never whether a
      // session exists at all: since _permissionForPath('/') is null, an
      // unauthenticated user (currentRole == null) sailed straight onto the
      // dashboard and the entire cash book with no login screen.
      return isAuthPath ? null : '/login';
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

    if (session == null) {
      return isAuthPath ? null : '/login';
    }

    if (isAuthPath) return '/';

    return _roleRedirect(path);
  },
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginPage(),
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
