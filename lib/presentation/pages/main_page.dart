import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/core/theme/app_theme.dart';
import 'package:masjid_app/presentation/blocs/sync/sync_cubit.dart';

class MainPage extends StatefulWidget {
  final Widget child;
  const MainPage({super.key, required this.child});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  Widget build(BuildContext context) {
    return BlocListener<SyncCubit, SyncState>(
      listener: (context, state) {
        if (!state.isSyncing &&
            !state.isSuccess &&
            state.errorMessages.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sinkronisasi gagal: ${state.errorMessages.first}'),
              backgroundColor: AppColors.danger,
              action: SnackBarAction(
                label: 'Tutup',
                textColor: Colors.white,
                onPressed: () => context.read<SyncCubit>().clearError(),
              ),
            ),
          );
        }
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: NavigationBar(
            selectedIndex: _calculateSelectedIndex(context),
            onDestinationSelected: (index) {
              _onItemTapped(index, context);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Kas',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                selectedIcon: Icon(Icons.event_note_rounded),
                label: 'Kegiatan',
              ),
              NavigationDestination(
                icon: Icon(Icons.volunteer_activism_outlined),
                selectedIcon: Icon(Icons.volunteer_activism_rounded),
                label: 'Qurban',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Pengaturan',
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/transactions')) {
      return 1;
    }
    if (location.startsWith('/activities')) {
      return 2;
    }
    if (location.startsWith('/qurban')) {
      return 3;
    }
    if (location.startsWith('/settings')) {
      return 4;
    }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/transactions');
        break;
      case 2:
        context.go('/activities');
        break;
      case 3:
        context.go('/qurban');
        break;
      case 4:
        context.go('/settings');
        break;
    }
  }
}
