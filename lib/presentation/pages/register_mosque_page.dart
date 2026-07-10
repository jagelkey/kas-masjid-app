import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/core/constants/env.dart';
import 'package:masjid_app/domain/entities/mosque_profile.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/blocs/profile/profile_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class RegisterMosquePage extends StatefulWidget {
  const RegisterMosquePage({super.key});

  @override
  State<RegisterMosquePage> createState() => _RegisterMosquePageState();
}

class _RegisterMosquePageState extends State<RegisterMosquePage> {
  final _mosqueNameController = TextEditingController();
  final _mosqueAddressController = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordVisible = false;

  // To track if we are in the process of saving profile after auth
  bool _isSavingProfile = false;

  // The real, unbypassable gate lives in the claim_first_admin() DB function
  // (it can only ever succeed once). This is just a UX nicety so a visitor
  // doesn't fill out the whole form only to be rejected at the end.
  bool _checkingEligibility = true;
  bool _registrationBlocked = false;

  @override
  void initState() {
    super.initState();
    _checkEligibility();
  }

  Future<void> _checkEligibility() async {
    if (!Env.hasValidConfig) {
      // Offline/local-only mode has no shared backend to protect against --
      // each device is its own isolated instance.
      if (mounted) setState(() => _checkingEligibility = false);
      return;
    }

    try {
      final alreadyClaimed = await Supabase.instance.client.rpc(
        'mosque_admin_exists',
      );
      if (mounted) {
        setState(() {
          _registrationBlocked = alreadyClaimed == true;
          _checkingEligibility = false;
        });
      }
    } catch (e) {
      // Fail open on network/RPC errors -- the actual security boundary is
      // claim_first_admin() at submit time, not this pre-check.
      if (mounted) setState(() => _checkingEligibility = false);
    }
  }

  @override
  void dispose() {
    _mosqueNameController.dispose();
    _mosqueAddressController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  AppBar _buildAppBar() => AppBar(
    title: const Text(
      'Daftar Masjid Baru',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
    centerTitle: true,
    backgroundColor: Colors.white,
    foregroundColor: Colors.black87,
    elevation: 0,
    iconTheme: const IconThemeData(color: Colors.black87),
  );

  @override
  Widget build(BuildContext context) {
    if (_checkingEligibility) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_registrationBlocked) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mosque_outlined,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Masjid ini sudah terdaftar dan memiliki admin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Silakan login, atau hubungi admin masjid untuk didaftarkan sebagai pengguna baru.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Ke Halaman Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: MultiBlocListener(
        listeners: [
          BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state is Authenticated || state is AuthOffline) {
                // Auth success, now save mosque profile
                setState(() {
                  _isSavingProfile = true;
                });
                context.read<ProfileBloc>().add(
                  SaveProfile(
                    MosqueProfile(
                      name: _mosqueNameController.text,
                      address: _mosqueAddressController.text,
                    ),
                  ),
                );
              } else if (state is AuthError) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(state.message)));
              }
            },
          ),
          BlocListener<ProfileBloc, ProfileState>(
            listener: (context, state) {
              if (_isSavingProfile) {
                if (state is ProfileLoaded) {
                  // Both Auth and Profile Save successful
                  context.go('/');
                } else if (state is ProfileError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Gagal menyimpan profil masjid: ${state.message}',
                      ),
                    ),
                  );
                  // Even if profile save fails, user is created, so maybe go to dashboard anyway?
                  // Or let them retry? For now let's go to dashboard as fallback
                  context.go('/');
                }
              }
            },
          ),
        ],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionCard(
                  title: 'Informasi Masjid',
                  icon: Icons.mosque_outlined,
                  children: [
                    TextFormField(
                      controller: _mosqueNameController,
                      decoration: _buildInputDecoration(
                        'Nama Masjid',
                        Icons.home_filled,
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Nama masjid wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _mosqueAddressController,
                      decoration: _buildInputDecoration(
                        'Alamat Masjid',
                        Icons.location_on_outlined,
                      ),
                      maxLines: 2,
                      validator: (value) =>
                          value!.isEmpty ? 'Alamat masjid wajib diisi' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionCard(
                  title: 'Informasi Admin (Ketua)',
                  icon: Icons.person_outline_rounded,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: _buildInputDecoration(
                        'Nama Lengkap Admin',
                        Icons.badge_outlined,
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Nama admin wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: _buildInputDecoration(
                        'Username',
                        Icons.alternate_email_rounded,
                      ),
                      validator: (value) {
                        final username = value?.trim() ?? '';
                        if (username.isEmpty) return 'Username wajib diisi';
                        if (username.length < 3) {
                          return 'Username minimal 3 karakter';
                        }
                        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
                          return 'Username hanya boleh huruf, angka, dan underscore';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: _buildInputDecoration(
                        'Email',
                        Icons.email_outlined,
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Email wajib diisi';
                        if (!RegExp(
                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                        ).hasMatch(email)) {
                          return 'Format email tidak valid';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration:
                          _buildInputDecoration(
                            'Password',
                            Icons.lock_outline_rounded,
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _isPasswordVisible = !_isPasswordVisible,
                              ),
                            ),
                          ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password wajib diisi';
                        }
                        if (value.length < 6) {
                          return 'Password minimal 6 karakter';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthLoading || _isSavingProfile) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return FilledButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          context.read<AuthBloc>().add(
                            RegisterRequested(
                              name: _nameController.text,
                              username: _usernameController.text,
                              email: _emailController.text,
                              password: _passwordController.text,
                              role: UserRole.admin,
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Daftarkan Masjid',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.green, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Divider(height: 1),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
