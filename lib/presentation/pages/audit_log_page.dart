import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/domain/entities/audit_log.dart';
import 'package:masjid_app/domain/repositories/audit_log_repository.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  // watchLogs() is newest-first; cap how many we render so the list can't grow
  // unbounded on a long-lived mosque install.
  static const _displayCap = 300;

  final _searchController = TextEditingController();
  String _query = '';
  String? _action; // null = all actions

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AuditLog> _filter(List<AuditLog> logs) {
    final q = _query.trim().toLowerCase();
    return logs.where((l) {
      if (_action != null && l.action != _action) return false;
      if (q.isEmpty) return true;
      return (l.description ?? '').toLowerCase().contains(q) ||
          (l.userName ?? l.userId).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final isAdmin =
            (authState is Authenticated && authState.role.canManageSettings) ||
            (authState is AuthOffline && authState.role.canManageSettings);

        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Audit Logs')),
            body: const Center(child: Text('Access Denied')),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Audit Logs')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Cari deskripsi atau pengguna...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            tooltip: 'Bersihkan',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _actionChip('Semua', null),
                    _actionChip('Tambah', 'CREATE'),
                    _actionChip('Ubah', 'UPDATE'),
                    _actionChip('Hapus', 'DELETE'),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<AuditLog>>(
                  stream: GetIt.I<AuditLogRepository>().watchLogs(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final all = snapshot.data ?? [];
                    if (all.isEmpty) {
                      return const Center(child: Text('No logs found'));
                    }

                    final filtered = _filter(all);
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text('Tidak ada log yang cocok'),
                      );
                    }

                    final truncated = filtered.length > _displayCap;
                    final capped = truncated
                        ? filtered.sublist(0, _displayCap)
                        : filtered;

                    return ListView.builder(
                      itemCount: capped.length + (truncated ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= capped.length) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Menampilkan $_displayCap log terbaru dari '
                              '${filtered.length}. Persempit dengan pencarian '
                              'atau filter di atas.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        }
                        return _buildLogTile(capped[index]);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionChip(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: _action == value,
        onSelected: (_) => setState(() => _action = value),
      ),
    );
  }

  Widget _buildLogTile(AuditLog log) {
    final dateFormat = DateFormat('dd MMM yyyy HH:mm');
    Color color;
    switch (log.action) {
      case 'CREATE':
        color = Colors.green;
        break;
      case 'UPDATE':
        color = Colors.blue;
        break;
      case 'DELETE':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(Icons.history, color: color),
        ),
        title: Text(log.description ?? 'No Description'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('User: ${log.userName ?? log.userId}'),
            Text('Time: ${dateFormat.format(log.createdAt)}'),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
