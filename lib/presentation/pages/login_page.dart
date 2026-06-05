import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:masjid_app/core/theme/app_theme.dart';
import 'package:masjid_app/domain/repositories/mosque_profile_repository.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/widgets/app_components.dart';
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkMosqueRegistration() async {
    try {
      final repository = GetIt.I<MosqueProfileRepository>();
      final profile = await repository.getProfile();
      if (profile != null && mounted) {
        setState(() {
          _isMosqueRegistered = true;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error checking local mosque registration: $e');
    }

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
    final url = Uri.parse(urlString);
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

  Future<void> _requestPasswordReset() async {
    final identifier = _emailController.text.trim();
    if (identifier.isEmpty || !identifier.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan email akun terlebih dahulu')),
      );
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(identifier);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link reset password telah dikirim ke email'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reset password membutuhkan koneksi online: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    _buildBrandHeader(context),
                    const SizedBox(height: 28),
                    _buildLoginForm(context),
                    if (!_isMosqueRegistered) ...[
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/register-mosque'),
                        icon: const Icon(Icons.add_business_rounded),
                        label: const Text('Daftarkan Masjid Baru'),
                      ),
                    ],
                    const SizedBox(height: 28),
                    _buildFooter(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.line),
          ),
          child: const Icon(
            Icons.mosque_rounded,
            size: 42,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Masjid App',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Kelola kas, kegiatan, dan iuran qurban dalam satu tempat.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        const AppStatusPill(
          label: 'OFFLINE-FIRST',
          icon: Icons.cloud_done_outlined,
          color: AppColors.teal,
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Masuk ke Akun',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email atau Username',
                prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
              ),
              keyboardType: TextInputType.text,
              validator: (value) =>
                  value!.isEmpty ? 'Email/Username wajib diisi' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
              ),
              validator: (value) =>
                  value!.isEmpty ? 'Password wajib diisi' : null,
            ),
            const SizedBox(height: 20),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                if (state is AuthLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                return FilledButton.icon(
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
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Login'),
                );
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _requestPasswordReset,
                child: const Text('Lupa Password?'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        Text(
          'Dibuat oleh ZeFa Aplikasi',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _launchWhatsApp,
              icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 26),
              color: AppColors.primary,
              tooltip: 'WhatsApp',
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => _launchSocialMedia(
                'https://www.tiktok.com/@stmasyithah_?_r=1&_t=ZS-93jticGXkpt',
              ),
              icon: const FaIcon(FontAwesomeIcons.tiktok, size: 22),
              color: AppColors.ink,
              tooltip: 'TikTok',
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => _launchSocialMedia(
                'https://www.instagram.com/rian_aselritz?igsh=MTh5ZG9taW5iNWc5cg==',
              ),
              icon: const FaIcon(FontAwesomeIcons.instagram, size: 26),
              color: const Color(0xFFE1306C),
              tooltip: 'Instagram',
            ),
          ],
        ),
      ],
    );
  }
}
