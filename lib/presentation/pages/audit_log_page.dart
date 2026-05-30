import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:masjid_app/domain/entities/audit_log.dart';
import 'package:masjid_app/domain/repositories/audit_log_repository.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';

class AuditLogPage extends StatelessWidget {
  const AuditLogPage({super.key});

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
          body: StreamBuilder<List<AuditLog>>(
            stream: GetIt.I<AuditLogRepository>().watchLogs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final logs = snapshot.data ?? [];

              if (logs.isEmpty) {
                return const Center(child: Text('No logs found'));
              }

              return ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  return _buildLogTile(log);
                },
              );
            },
          ),
        );
      },
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
