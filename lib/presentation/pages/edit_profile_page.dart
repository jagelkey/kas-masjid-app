import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Load data after first frame to access context safely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
    });
  }

  void _loadUserData() {
    final state = context.read<AuthBloc>().state;
    if (state is Authenticated) {
      _fullNameController.text = state.user.userMetadata?['full_name'] ?? '';
      _usernameController.text = state.user.userMetadata?['username'] ?? '';
      _emailController.text = state.user.email ?? '';
    } else if (state is AuthOffline) {
      _fullNameController.text = state.user.metadata['full_name'] ?? '';
      _usernameController.text = state.user.metadata['username'] ?? '';
      _emailController.text = state.user.email;
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final password = _passwordController.text.trim();
      final confirmPassword = _confirmPasswordController.text.trim();
      final email = _emailController.text.trim().toLowerCase();
      final username = _usernameController.text.trim().toLowerCase();
      final fullName = _fullNameController.text.trim();

      // Check if anything actually changed
      final state = context.read<AuthBloc>().state;
      String? currentEmail;
      String? currentUsername;
      String? currentFullName;

      if (state is Authenticated) {
        currentEmail = state.user.email?.toLowerCase();
        currentUsername = state.user.userMetadata?['username']?.toLowerCase();
        currentFullName = state.user.userMetadata?['full_name'];
      } else if (state is AuthOffline) {
        currentEmail = state.user.email.toLowerCase();
        currentUsername = state.user.metadata['username']?.toLowerCase();
        currentFullName = state.user.metadata['full_name'];
      }

      final bool hasChanges =
          email != currentEmail ||
          username != currentUsername ||
          fullName != currentFullName ||
          password.isNotEmpty;

      if (!hasChanges) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada perubahan untuk disimpan')),
        );
        return;
      }

      // Validate password match
      if (password.isNotEmpty && password != confirmPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password baru tidak cocok')),
        );
        return;
      }

      // Validate password strength
      if (password.isNotEmpty && password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password minimal 6 karakter')),
        );
        return;
      }

      // Validate email format
      if (!email.contains('@') || !email.contains('.')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Format email tidak valid')),
        );
        return;
      }

      // Validate username length
      if (username.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username minimal 3 karakter')),
        );
        return;
      }

      // Validate username (no spaces, alphanumeric only)
      if (username.contains(' ')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Username tidak boleh mengandung spasi'),
          ),
        );
        return;
      }

      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Username hanya boleh huruf, angka, dan underscore'),
          ),
        );
        return;
      }

      // Validate full name
      if (fullName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama lengkap tidak boleh kosong')),
        );
        return;
      }

      // Show confirmation dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Konfirmasi Perubahan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Apakah Anda yakin ingin menyimpan perubahan ini?'),
              const SizedBox(height: 16),
              if (password.isNotEmpty) ...[
                const Text(
                  'Password akan diubah',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text('Nama: $fullName'),
              Text('Username: $username'),
              Text('Email: $email'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.read<AuthBloc>().add(
                  UpdateProfileRequested(
                    fullName: fullName,
                    username: username,
                    email: email,
                    password: password.isNotEmpty ? password : null,
                  ),
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profil')),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthLoading) {
            setState(() => _isLoading = true);
          } else if (state is AuthSuccess) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
            context.pop(); // Go back
          } else if (state is AuthError) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          } else {
            setState(() => _isLoading = false);
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isLoading) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Lengkap',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_circle),
                    helperText: 'Hanya huruf, angka, dan underscore',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Wajib diisi';
                    if (value.contains(' ')) return 'Tidak boleh ada spasi';
                    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                      return 'Hanya huruf, angka, dan underscore';
                    }
                    if (value.length < 3) return 'Minimal 3 karakter';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Wajib diisi';
                    if (!RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    ).hasMatch(value)) {
                      return 'Format email tidak valid';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Ubah Password (Opsional)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password Baru',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                    helperText:
                        'Minimal 6 karakter. Kosongkan jika tidak ingin mengubah',
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value != null && value.isNotEmpty && value.length < 6) {
                      return 'Password minimal 6 karakter';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Konfirmasi Password Baru',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (_passwordController.text.isNotEmpty &&
                        (value == null || value.isEmpty)) {
                      return 'Konfirmasi password diperlukan';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _isLoading ? 'Menyimpan...' : 'Simpan Perubahan',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
