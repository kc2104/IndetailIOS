import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../native_bridge.dart';
import '../repository.dart';
import '../supabase_api.dart';
import '../theme.dart';
import 'app_shell.dart';

enum GatePage {
  welcome,
  signIn,
  signUp,
  signupComplete,
  setupPin,
  unlock,
  workspace,
}

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> with TickerProviderStateMixin {
  GatePage _page = GatePage.welcome;
  AppSession? _session;
  WorkspaceRepository? _repository;
  bool _loading = true;
  bool _busy = false;
  bool _showFingerprint = false;
  String? _error;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();
  String? _createdEmployeeId;
  String? _createdEmail;
  bool _signupSignedIn = false;
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _intro.dispose();
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _confirmPassword.dispose();
    _pin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    try {
      final encoded = await NativeBridge.readSecure('session');
      if (encoded != null) {
        final restored = AppSession.fromJson(
          jsonDecode(encoded) as Map<String, Object?>,
        );
        if (!restored.isDemo && isSupabaseConfigured) {
          _session = restored;
          _repository = _makeRepository(restored);
          if (kIsWeb) {
            try {
              await _repository!.api.getCurrentUser();
              _session = _repository!.api.session;
            } catch (_) {}
            if (mounted) setState(() => _page = GatePage.workspace);
          } else {
            await _refreshFingerprintAvailability();
            final pinExists = await NativeBridge.hasPin();
            if (mounted) {
              setState(
                () => _page = pinExists ? GatePage.unlock : GatePage.setupPin,
              );
              if (pinExists && _showFingerprint) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _page == GatePage.unlock && !_busy) {
                    _unlockWithFingerprint();
                  }
                });
              }
            }
          }
          return;
        }
      }
    } catch (error) {
      _error = _message(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WorkspaceRepository _makeRepository(AppSession session) =>
      WorkspaceRepository(
        session,
        onSessionUpdated: (updated) async {
          _session = updated;
          await NativeBridge.writeSecure(
            'session',
            jsonEncode(updated.toJson()),
          );
        },
      );

  Future<void> _signIn() async {
    if (!isSupabaseConfigured) {
      setState(
        () => _error = 'Live sign-in is disabled until SUPABASE_URL and SUPABASE_ANON_KEY are configured.',
      );
      return;
    }
    final identifier = _email.text.trim();
    if (identifier.isEmpty || _password.text.isEmpty) {
      setState(
        () => _error = 'Enter your work email or Employee ID and password.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final initial = AppSession(
        name: 'Workspace member',
        email: identifier.contains('@') ? identifier : '',
        role: UserRole.employee,
      );
      _repository = _makeRepository(initial);
      final signedIn =
          RegExp(r'^ids\d{4}$', caseSensitive: false).hasMatch(identifier)
          ? await _repository!.api.signInEmployeeId(identifier, _password.text)
          : await _repository!.api.signIn(identifier, _password.text);
      _session = signedIn;
      await NativeBridge.writeSecure('session', jsonEncode(signedIn.toJson()));
      if (kIsWeb) {
        if (mounted) setState(() => _page = GatePage.workspace);
      } else {
        await _refreshFingerprintAvailability();
        final pinExists = await NativeBridge.hasPin();
        if (mounted) {
          setState(
            () => _page = pinExists ? GatePage.workspace : GatePage.setupPin,
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    if (!isSupabaseConfigured) {
      setState(
        () =>
            _error = 'Signup needs the live INDETAIL workspace configuration.',
      );
      return;
    }
    final name = _displayName.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(() => _error = 'Enter your name (up to 80 characters).');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (_password.text.length < 10) {
      setState(() => _error = 'Use a password with at least 10 characters.');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final initial = AppSession(
        name: name,
        email: email,
        role: UserRole.employee,
      );
      _repository = _makeRepository(initial);
      final result = await _repository!.api.signUp(
        displayName: name,
        email: email,
        password: _password.text,
      );
      _createdEmployeeId = result.employeeId;
      _createdEmail = email;
      _signupSignedIn = result.signedIn;
      _password.clear();
      _confirmPassword.clear();
      if (result.signedIn) {
        _session = _repository!.api.session;
        await NativeBridge.writeSecure(
          'session',
          jsonEncode(_session!.toJson()),
        );
        if (!kIsWeb) await _refreshFingerprintAvailability();
        if (mounted) setState(() => _page = GatePage.signupComplete);
      } else if (mounted) {
        setState(() => _page = GatePage.signupComplete);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshFingerprintAvailability() async {
    try {
      final available = await NativeBridge.biometricAvailable();
      final enabled = await NativeBridge.readSecure('biometric_enabled');
      _showFingerprint = available && enabled != 'false';
    } on PlatformException {
      _showFingerprint = false;
    }
  }

  Future<void> _savePin() async {
    final pin = _pin.text;
    if (pin.length != 6 || _confirmPin.text.length != 6) {
      setState(() => _error = 'Enter and confirm a six-digit PIN.');
      return;
    }
    if (pin != _confirmPin.text) {
      setState(() => _error = 'Those PINs do not match. Try again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await NativeBridge.setPin(pin);
      final hasBiometric = await NativeBridge.biometricAvailable();
      if (hasBiometric) {
        await NativeBridge.writeSecure('biometric_enabled', 'true');
        _showFingerprint = true;
      }
      _pin.clear();
      _confirmPin.clear();
      if (mounted) setState(() => _page = GatePage.workspace);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    if (_pin.text.length != 6) {
      setState(() => _error = 'Enter your six-digit PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await NativeBridge.verifyPin(_pin.text)) {
        _pin.clear();
        if (mounted) {
          setState(() {
            _page = GatePage.workspace;
            _error = null;
          });
        }
        _syncInBackground();
      } else {
        _pin.clear();
        if (mounted)
          setState(() => _error = 'That PIN does not match. Try again.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockWithFingerprint() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final available = await NativeBridge.biometricAvailable();
      if (!available) {
        if (mounted) {
          setState(() {
            _error =
                'No fingerprint or face unlock detected. Set up biometric lock in your phone settings.';
          });
        }
        return;
      }
      if (await NativeBridge.authenticateBiometric()) {
        if (mounted) {
          setState(() {
            _page = GatePage.workspace;
            _error = null;
          });
        }
        _syncInBackground();
      } else if (mounted) {
        setState(
          () => _error =
              'Biometric unlock was cancelled. Use your PIN to continue.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _syncInBackground() {
    if (_repository != null && isSupabaseConfigured) {
      _repository!.api.getCurrentUser().then((_) {
        if (mounted) {
          setState(() => _session = _repository!.api.session);
        }
      }).catchError((_) {});
    }
  }

  Future<void> _openDemo() async {
    final role = await showModalBottomSheet<UserRole>(
      context: context,
      backgroundColor: Palette.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preview a role',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              const Text(
                'Sample content stays on this device and is never sent to a server.',
              ),
              const SizedBox(height: 16),
              for (final role in UserRole.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Palette.powder.withValues(alpha: .35),
                    child: Icon(_roleIcon(role), color: Palette.navy),
                  ),
                  title: Text(role.label),
                  subtitle: Text(_roleDescription(role)),
                  trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
                  onTap: () => Navigator.pop(context, role),
                ),
            ],
          ),
        ),
      ),
    );
    if (role == null) return;
    final session = AppSession(
      name: 'Preview workspace',
      email: '',
      role: role,
      isDemo: true,
    );
    setState(() {
      _session = session;
      _repository = _makeRepository(session);
      _page = GatePage.workspace;
      _error = null;
    });
  }

  Future<void> _signOut() async {
    try {
      await _repository?.api.signOut();
      await NativeBridge.deleteSecure('session');
      await NativeBridge.deleteSecure('pin_record');
      await NativeBridge.deleteSecure('pin_failures');
      await NativeBridge.deleteSecure('pin_lockout_until');
      await NativeBridge.deleteSecure('biometric_enabled');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _session = null;
      _repository = null;
      _page = GatePage.welcome;
      _error = null;
    });
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _SplashView();
    if (_page == GatePage.workspace &&
        _session != null &&
        _repository != null) {
      return AppShell(
        key: ValueKey(
          '${_session!.isDemo}:${_session!.role.name}:${_session!.email}',
        ),
        session: _session!,
        repository: _repository!,
        onSignOut: _signOut,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(.035, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: switch (_page) {
            GatePage.welcome => _welcomePage(),
            GatePage.signIn => _signInPage(),
            GatePage.signUp => _signUpPage(),
            GatePage.signupComplete => _signupCompletePage(),
            GatePage.setupPin => _pinPage(setup: true),
            GatePage.unlock => _pinPage(setup: false),
            GatePage.workspace => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _welcomePage() => SingleChildScrollView(
    key: const ValueKey('welcome'),
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _brandMark(size: 40),
            const SizedBox(width: 11),
            Text(
              'INDETAIL',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(letterSpacing: 1.8),
            ),
            const Spacer(),
            _modeBadge(
              isSupabaseConfigured ? 'LIVE CONFIG SET' : 'PREVIEW MODE',
            ),
          ],
        ),
        const SizedBox(height: 34),
        FadeTransition(
          opacity: CurvedAnimation(parent: _intro, curve: Curves.easeOut),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, .1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic),
                ),
            child: _heroCard(),
          ),
        ),
        const SizedBox(height: 25),
        Text(
          'One clear view of the work.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 9),
        const Text(
          'Projects, attendance and daily progress in one calm workspace.',
          style: TextStyle(fontSize: 15, height: 1.5, color: Palette.muted),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => setState(() {
            _page = GatePage.signIn;
            _error = null;
          }),
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Sign in to your workspace'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _page = GatePage.signUp;
            _error = null;
          }),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Create an employee account'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        const SizedBox(height: 11),
        OutlinedButton.icon(
          onPressed: _openDemo,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Explore the interactive preview'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, color: Palette.muted, size: 15),
            SizedBox(width: 7),
            Flexible(
              child: Text(
                isSupabaseConfigured
                    ? 'Workspace data uses Supabase. Attendance is server-verified.'
                    : 'Preview data is local. Live setup is separate.',
                style: const TextStyle(color: Palette.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _heroCard() => Container(
    height: 268,
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Palette.navy,
      borderRadius: BorderRadius.circular(27),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -46,
          top: -70,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .10),
                width: 34,
              ),
            ),
          ),
        ),
        Positioned(
          right: 20,
          bottom: -85,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.blue.withValues(alpha: .28),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'PROJECTS  •  PEOPLE  •  PRODUCTIVITY',
                  style: TextStyle(
                    color: Palette.powder,
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Every detail,\nin its place.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 29,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.6,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'A better rhythm for the workday.',
                          style: TextStyle(color: Palette.powder, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .15),
                      ),
                    ),
                    child: const Icon(
                      Icons.architecture_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _signInPage() => SingleChildScrollView(
    key: const ValueKey('signin'),
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () => setState(() {
            _page = GatePage.welcome;
            _error = null;
          }),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(height: 20),
        _brandMark(size: 48),
        const SizedBox(height: 24),
        Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'Use your work email or your INDETAIL Employee ID.',
          style: TextStyle(color: Palette.muted, height: 1.5),
        ),
        const SizedBox(height: 27),
        if (!isSupabaseConfigured) _setupNotice(),
        const SizedBox(height: 18),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Work email or Employee ID',
            hintText: 'name@company.com · ids1234',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 13),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        if (_error != null) _inlineError(_error!),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Continue securely'),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _page = GatePage.signUp;
              _error = null;
            }),
            child: const Text('New here? Create an account'),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _openDemo,
            child: const Text('Explore preview instead'),
          ),
        ),
      ],
    ),
  );

  Widget _signUpPage() => SingleChildScrollView(
    key: const ValueKey('signup'),
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () => setState(() {
            _page = GatePage.welcome;
            _error = null;
          }),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(height: 20),
        _brandMark(size: 48),
        const SizedBox(height: 24),
        Text(
          'Join INDETAIL',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Create an employee account with your email. INDETAIL will assign your Employee ID automatically.',
          style: TextStyle(color: Palette.muted, height: 1.5),
        ),
        const SizedBox(height: 23),
        if (!isSupabaseConfigured) _setupNotice(),
        TextField(
          controller: _displayName,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Full name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'Create password',
            helperText: 'At least 10 characters',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPassword,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: Icon(Icons.lock_reset_rounded),
          ),
        ),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Palette.sand.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: Palette.navy, size: 18),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'New accounts start with Employee access. An Admin assigns Team Leader permissions inside the workspace.',
                  style: TextStyle(
                    color: Palette.navy,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) _inlineError(_error!),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _signUp,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create employee account'),
        ),
        const SizedBox(height: 9),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _page = GatePage.signIn;
              _error = null;
            }),
            child: const Text('Already registered? Sign in'),
          ),
        ),
      ],
    ),
  );

  Widget _signupCompletePage() => SingleChildScrollView(
    key: const ValueKey('signup-complete'),
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brandMark(size: 48),
        const SizedBox(height: 28),
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFFE7F3EC),
            borderRadius: BorderRadius.circular(19),
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: Palette.green,
            size: 29,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Account created',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          _signupSignedIn
              ? 'Your account is ready. Save your Employee ID for future sign-ins, then set up your six-digit app PIN.'
              : 'We sent an email confirmation link to ${_createdEmail ?? 'your email'}. Verify it, then sign in with your Employee ID and password.',
          style: const TextStyle(color: Palette.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Palette.navy,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR EMPLOYEE ID',
                style: TextStyle(
                  color: Palette.powder,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _createdEmployeeId ?? 'ids0000',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy Employee ID',
                    onPressed: _createdEmployeeId == null
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: _createdEmployeeId!),
                          ),
                    icon: const Icon(Icons.copy_rounded, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 21),
        FilledButton(
          onPressed: () {
            if (_signupSignedIn) {
              setState(() {
                _page = kIsWeb ? GatePage.workspace : GatePage.setupPin;
                _error = null;
              });
            } else {
              _email.text = _createdEmployeeId ?? '';
              _password.clear();
              setState(() {
                _page = GatePage.signIn;
                _error = null;
              });
            }
          },
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(
            _signupSignedIn
                ? (kIsWeb ? 'Open my workspace' : 'Set up my PIN')
                : 'Continue to sign in',
          ),
        ),
        const SizedBox(height: 9),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _page = GatePage.welcome;
              _error = null;
            }),
            child: const Text('Back to welcome'),
          ),
        ),
      ],
    ),
  );

  Widget _setupNotice() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1F7),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Palette.powder),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Palette.navy),
        SizedBox(width: 11),
        Expanded(
          child: Text(
            'Live backend is not configured in this preview APK. Add your Supabase URL and anon key to enable sign-in. No credentials are built in.',
            style: TextStyle(color: Palette.navy, height: 1.42, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _pinPage({required bool setup}) => SingleChildScrollView(
    key: ValueKey(setup ? 'setup-pin' : 'unlock-pin'),
    padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (setup)
          IconButton(onPressed: _signOut, icon: const Icon(Icons.close_rounded))
        else
          const SizedBox(height: 8),
        const SizedBox(height: 35),
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Palette.sand,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            setup ? Icons.password_rounded : Icons.lock_rounded,
            color: Palette.navy,
            size: 28,
          ),
        ),
        const SizedBox(height: 23),
        Text(
          setup ? 'Create your PIN' : 'Unlock INDETAIL',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          setup
              ? 'Use six digits for a quick, private app lock.'
              : 'Enter your six-digit PIN to continue${_session == null ? '' : ', ${_session!.name.split(' ').first}'}.',
          style: const TextStyle(color: Palette.muted, height: 1.45),
        ),
        const SizedBox(height: 25),
        _pinField(_pin, setup ? 'New six-digit PIN' : 'Six-digit PIN'),
        if (setup) ...[
          const SizedBox(height: 12),
          _pinField(_confirmPin, 'Confirm PIN'),
        ],
        if (_error != null) _inlineError(_error!),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy
              ? null
              : setup
              ? _savePin
              : _unlock,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(setup ? 'Set up PIN' : 'Unlock'),
        ),
        if (!setup) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _unlockWithFingerprint,
            icon: const Icon(Icons.fingerprint_rounded, size: 22),
            label: const Text('Unlock with Biometrics (Fingerprint / Face ID)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
        if (!setup)
          Center(
            child: TextButton(
              onPressed: _signOut,
              child: const Text('Sign out'),
            ),
          ),
        if (setup)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              'The PIN hash and session token are stored in Android Keystore protected storage.',
              style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.5),
            ),
          ),
      ],
    ),
  );

  Widget _pinField(TextEditingController controller, String label) => TextField(
    controller: controller,
    obscureText: true,
    keyboardType: TextInputType.number,
    maxLength: 6,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.dialpad_rounded),
      counterText: '',
    ),
  );

  Widget _inlineError(String value) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, color: Palette.red, size: 18),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Palette.red,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _brandMark({double size = 42}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Palette.blue, Palette.navy],
      ),
      borderRadius: BorderRadius.circular(size * .34),
      boxShadow: [
        BoxShadow(
          color: Palette.navy.withValues(alpha: .18),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Icon(
      Icons.architecture_rounded,
      color: Colors.white,
      size: size * .56,
    ),
  );

  Widget _modeBadge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Palette.sand,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Palette.navy,
        fontWeight: FontWeight.w800,
        fontSize: 9,
        letterSpacing: .65,
      ),
    ),
  );

  IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.admin => Icons.admin_panel_settings_outlined,
    UserRole.teamLeader => Icons.groups_2_outlined,
    UserRole.employee => Icons.person_outline_rounded,
  };

  String _roleDescription(UserRole role) => switch (role) {
    UserRole.admin => 'Workspace overview and controls',
    UserRole.teamLeader => 'Team work and report review',
    UserRole.employee => 'Personal tasks and daily progress',
  };
}

class _SplashView extends StatelessWidget {
  const _SplashView();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: Palette.navy,
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Icon(
              Icons.architecture_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 17),
          Text(
            'INDETAIL',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(letterSpacing: 2.3),
          ),
          const SizedBox(height: 23),
          const SizedBox(
            width: 30,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: Palette.blue,
              backgroundColor: Palette.sand,
            ),
          ),
        ],
      ),
    ),
  );
}
