import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/domain/repositories/mosque_profile_repository.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:url_launcher/url_launcher.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordVisible = false;
  bool _isMosqueRegistered = false;

  @override
  void initState() {
    super.initState();
    _checkMosqueRegistration();
  }

  Future<void> _checkMosqueRegistration() async {
    // 1. Cek Lokal (Repository)
    try {
      final repository = GetIt.I<MosqueProfileRepository>();
      final profile = await repository.getProfile();
      if (profile != null && mounted) {
        setState(() {
          _isMosqueRegistered = true;
        });
        return; // Jika lokal ada, tidak perlu cek remote
      }
    } catch (e) {
      debugPrint('Error checking local mosque registration: $e');
    }

    // 2. Cek Remote (Supabase)
    // Hanya bisa diakses jika user punya internet dan RLS 'mosque_profiles' mengizinkan public read
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('mosque_profiles')
          .select('id')
          .limit(1)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _isMosqueRegistered = true;
        });
      }
    } catch (e) {
      debugPrint('Error checking remote mosque registration: $e');
    }
  }

  Future<void> _launchSocialMedia(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat membuka link')),
        );
      }
    }
  }

  Future<void> _launchWhatsApp() async {
    await _launchSocialMedia('https://wa.me/6282187179981');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated || state is AuthOffline) {
            context.go('/');
          } else if (state is AuthError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mosque,
                    size: 64,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Masjid App',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kelola Kas & Jadwal Masjid dengan Mudah',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 32),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Masuk ke Akun',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: 'Email atau Username',
                              prefixIcon: const Icon(
                                Icons.alternate_email_rounded,
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            keyboardType: TextInputType.text,
                            validator: (value) => value!.isEmpty
                                ? 'Email/Username wajib diisi'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () =>
                                      _isPasswordVisible = !_isPasswordVisible,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            validator: (value) =>
                                value!.isEmpty ? 'Password wajib diisi' : null,
                          ),
                          const SizedBox(height: 24),
                          BlocBuilder<AuthBloc, AuthState>(
                            builder: (context, state) {
                              if (state is AuthLoading) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return FilledButton(
                                onPressed: () {
                                  if (_formKey.currentState!.validate()) {
                                    context.read<AuthBloc>().add(
                                      LoginRequested(
                                        _emailController.text,
                                        _passwordController.text,
                                      ),
                                    );
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (!_isMosqueRegistered) ...[
                  Text(
                    'Belum memiliki akun?',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  TextButton(
                    onPressed: () {
                      context.push('/register-mosque');
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Daftarkan Masjid Baru'),
                  ),
                ],
                const SizedBox(height: 48),
                const Text(
                  'Dibuat oleh ZeFa Aplikasi',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _launchWhatsApp,
                      icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 28),
                      color: Colors.green,
                      tooltip: 'WhatsApp',
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: () => _launchSocialMedia(
                        'https://www.tiktok.com/@stmasyithah_?_r=1&_t=ZS-93jticGXkpt',
                      ),
                      icon: const FaIcon(FontAwesomeIcons.tiktok, size: 24),
                      color: Colors.black,
                      tooltip: 'TikTok',
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: () => _launchSocialMedia(
                        'https://www.instagram.com/rian_aselritz?igsh=MTh5ZG9taW5iNWc5cg==',
                      ),
                      icon: const FaIcon(FontAwesomeIcons.instagram, size: 28),
                      color: Colors.purple,
                      tooltip: 'Instagram',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
