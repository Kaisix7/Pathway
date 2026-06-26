import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:uni_links/uni_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'analytics.dart';
import 'state.dart';
import 'models.dart';
import 'data.dart';
import 'visa_info_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_list_pick/country_list_pick.dart';
import 'map_view.dart';
import 'visa_views.dart';
import 'l10n/app_localizations.dart';
import 'stripe_payment_screen.dart';

class AuthView extends StatefulWidget {
  final AppState app;
  const AuthView({super.key, required this.app});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      // Handle OAuth callback on web
      try {
        final uri = Uri.parse(html.window.location.href);
        final token = uri.queryParameters['token'];
        final email = uri.queryParameters['email'];
        final name = uri.queryParameters['name'] ?? '';
        if (token != null && email != null) {
          widget.app.loginWithOAuthToken(token: token, email: email, name: name);
        }
      } catch (e) {
        debugPrint("Web deep link parsing error: $e");
      }
    } else {
      // Handle OAuth callback on mobile
      try {
        getInitialUri().then((uri) {
          if (uri != null) {
            final token = uri.queryParameters['token'];
            final email = uri.queryParameters['email'];
            final name = uri.queryParameters['name'] ?? '';
            if (token != null && email != null) {
              widget.app.loginWithOAuthToken(token: token, email: email, name: name);
            }
          }
        });

        uriLinkStream.listen((Uri? uri) {
          if (uri != null) {
            final token = uri.queryParameters['token'];
            final email = uri.queryParameters['email'];
            final name = uri.queryParameters['name'] ?? '';
            if (token != null && email != null) {
              widget.app.loginWithOAuthToken(token: token, email: email, name: name);
            }
          }
        });
      } catch (e) {
        debugPrint("Mobile deep link parsing error: $e");
      }
    }
    fNationality.text = 'USA';
  }
  UserRole role = UserRole.foreigner;
  String selectedCountryCode = 'US';
  bool isAccepted = false;

  final fName = TextEditingController();
  final lName = TextEditingController();
  final fContact = TextEditingController();
  final fNationality = TextEditingController();
  final fCompany = TextEditingController();

  final wIin = TextEditingController();
  final wContact = TextEditingController();
  final wCity = TextEditingController(text: 'Almaty');
  final wRole = TextEditingController(text: 'Coordinator');
  final wCompany = TextEditingController();
  final adminPassword = TextEditingController();

  Future<void> loginWithGoogle() async {
    String redirectUriParam = 'http://localhost:8000/';
    if (kIsWeb) {
      redirectUriParam = '${html.window.location.origin ?? "http://localhost:8000"}${html.window.location.pathname ?? ""}';
    }
    final url = Uri.parse("${ApiService.baseUrl}/oauth/google/").replace(
      queryParameters: {'redirect_uri': redirectUriParam}
    );
    final launched = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      _snack(context, 'Could not launch Google Login page.');
    }
  }
  bool isValidEmail(String email) {
    return email.contains('@') && email.contains('.');
  }

  bool isValidIin(String iin) {
    // IIN should be 12 digits
    final cleanIin = iin.replaceAll(RegExp(r'\D'), '');
    return cleanIin.length == 12;
  }

  bool isValidContact(String contact) {
    // Accept email or phone format
    if (isValidEmail(contact)) return true;
    // Phone: at least 10 digits
    final cleanPhone = contact.replaceAll(RegExp(r'\D'), '');
    return cleanPhone.length >= 10;
  }

  Future<void> _showTermsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terms of Service'),
        content: const SingleChildScrollView(
          child: Text(
            'By using PATHWAY, you agree to provide accurate registration information and use the app only for lawful service requests. '
            'The app currently supports an onboarding flow from registration to services and airport booking. '
            'Orders and account information may be stored to provide the requested services.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPrivacyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'PATHWAY collects basic profile information such as name, email, and selected country. '
            'This information is stored to support registration, onboarding, and service orders. '
            'Your basic data is not shared with third parties for marketing purposes in this MVP.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmConsent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Consent'),
        content: const Text(
          'Please confirm that you agree to the Terms of Service and Privacy Policy before registration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _handleStartPressed() async {
    if (role == UserRole.admin) {
      if (fContact.text.trim().isEmpty) {
        _snack(context, 'Please enter your superuser email or username');
        return;
      }
      if (adminPassword.text.isEmpty) {
        _snack(context, 'Please enter your superuser password');
        return;
      }
      try {
        await widget.app.loginAdmin(fContact.text.trim(), adminPassword.text);
      } catch (e) {
        _snack(context, 'Login failed: ${e.toString().replaceAll('Exception:', '').trim()}');
      }
      return;
    }
    if (role == UserRole.foreigner) {
      if (fName.text.trim().isEmpty) {
        _snack(context, 'Please enter your first name');
        return;
      }
      if (lName.text.trim().isEmpty) {
        _snack(context, 'Please enter your last name');
        return;
      }
      if (fContact.text.trim().isEmpty) {
        _snack(context, 'Please enter your email or phone');
        return;
      }
      if (!isValidEmail(fContact.text.trim()) && !isValidContact(fContact.text.trim())) {
        _snack(context, 'Invalid email/phone format');
        return;
      }
      if (fNationality.text.trim().isEmpty) {
        _snack(context, 'Please enter your nationality');
        return;
      }
      if (widget.app.savedEmail.isNotEmpty && fContact.text.trim() != widget.app.savedEmail) {
        _snack(context, 'Email does not match registration');
        return;
      }
      if (!isAccepted) {
        _snack(context, 'Please accept Terms and Privacy Policy');
        return;
      }
      final consentConfirmed = await _confirmConsent();
      if (!consentConfirmed) {
        _snack(context, 'Registration cancelled');
        return;
      }

      try {
        final utms = Analytics.getStoredUtms();
        final token = await ApiService.registerUser(
          name: '${fName.text.trim()} ${lName.text.trim()}',
          email: fContact.text.trim(),
          company: fCompany.text.trim(),
          utmSource: utms['utm_source'] ?? '',
          utmMedium: utms['utm_medium'] ?? '',
          utmCampaign: utms['utm_campaign'] ?? '',
        );

        if (token == null) {
          if (!mounted) return;
          _snack(context, 'Registration failed. Check Django API response.');
          return;
        }

        await widget.app.loginForeigner(
          firstName: fName.text,
          lastName: lName.text,
          contact: fContact.text,
          nationality: fNationality.text,
          nationalityCode: selectedCountryCode,
          company: fCompany.text.trim(),
          utmSource: utms['utm_source'] ?? '',
          utmMedium: utms['utm_medium'] ?? '',
          utmCampaign: utms['utm_campaign'] ?? '',
          token: token,
        );
        return;

      } catch (e) {
        if (!mounted) return;
        _snack(context, 'Could not connect to Django: $e');
        return;
      }
    }

    if (wIin.text.trim().isEmpty) {
      _snack(context, 'Please enter IIN (12 digits)');
      return;
    }
    if (!isValidIin(wIin.text.trim())) {
      _snack(context, 'IIN must be 12 digits');
      return;
    }
    if (wContact.text.trim().isEmpty) {
      _snack(context, 'Please enter your contact');
      return;
    }
    if (!isValidContact(wContact.text.trim())) {
      _snack(context, 'Invalid contact format (email or phone)');
      return;
    }
    widget.app.loginWorker(
      iin: wIin.text,
      contact: wContact.text,
      city: wCity.text,
      roleName: wRole.text,
      company: wCompany.text,
    );
  }

  @override
  void dispose() {
    fName.dispose();
    lName.dispose();
    fContact.dispose();
    fNationality.dispose();
    fCompany.dispose();
    wIin.dispose();
    wContact.dispose();
    wCity.dispose();
    wRole.dispose();
    wCompany.dispose();
    adminPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: isWide ? _wideLayout(context) : _narrowLayout(context),
    );
  }

  // ── Wide layout (desktop/tablet) ─────────────────────────────────────────
  Widget _wideLayout(BuildContext context) {
    return Row(
      children: [
        // Left hero panel
        Expanded(
          flex: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFF0A0A0A)),
              // Subtle grid texture overlay
              Opacity(
                opacity: 0.04,
                child: Image.network(
                  'https://www.transparenttextures.com/patterns/subtle-dots.png',
                  repeat: ImageRepeat.repeat,
                  fit: BoxFit.none,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset('assets/logo.png', width: 40, height: 40, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'PATHWAY',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Hero headline
                    const Text(
                      'RELOCATE\nSMARTER.',
                      style: TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 0.92,
                        letterSpacing: -3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8D44D),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Digital relocation guide for Kazakhstan',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0A0A0A),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    // Feature bullets
                    _heroBullet(Icons.badge_outlined, 'IIN booking & queue navigation'),
                    const SizedBox(height: 14),
                    _heroBullet(Icons.home_outlined, 'Verified housing database'),
                    const SizedBox(height: 14),
                    _heroBullet(Icons.description_outlined, 'Visa & document tracker'),
                    const SizedBox(height: 14),
                    _heroBullet(Icons.smart_toy_outlined, 'AI immigration assistant'),
                    const Spacer(),
                    Text(
                      'PATHWAY • Digital Relocation Platform',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Right form panel
        Container(
          width: 1,
          color: const Color(0xFF1E1E1E),
        ),
        Expanded(
          flex: 4,
          child: Container(
            color: const Color(0xFF0E0E0E),
            child: SafeArea(
              child: _formPanel(context),
            ),
          ),
        ),
      ],
    );
  }

  // ── Narrow layout (mobile) ───────────────────────────────────────────────
  Widget _narrowLayout(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Compact top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/logo.png', width: 32, height: 32, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                const Text(
                  'PATHWAY',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Mini hero
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RELOCATE\nSMARTER.',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 0.92,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8D44D),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Digital relocation guide for Kazakhstan',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(child: _formPanel(context)),
        ],
      ),
    );
  }

  Widget _heroBullet(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFE8D44D).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFFE8D44D)),
        ),
        const SizedBox(width: 14),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── Form panel (shared) ──────────────────────────────────────────────────
  Widget _formPanel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Get started',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create your account or sign in',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          _roleSwitch(),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                if (role == UserRole.foreigner) ..._foreignerForm(context),
                if (role == UserRole.worker) ..._workerForm(context),
                if (role == UserRole.admin) ..._adminForm(context),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _handleStartPressed,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Start Journey',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleSwitch() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _seg(
              active: role == UserRole.foreigner,
              icon: Icons.public,
              text: 'Foreigner',
              onTap: () => setState(() => role = UserRole.foreigner),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _seg(
              active: role == UserRole.worker,
              icon: Icons.badge_outlined,
              text: 'Worker',
              onTap: () => setState(() => role = UserRole.worker),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _seg(
              active: role == UserRole.admin,
              icon: Icons.admin_panel_settings_outlined,
              text: 'Admin',
              onTap: () => setState(() => role = UserRole.admin),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg({required bool active, required IconData icon, required String text, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8D44D) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? const Color(0xFF0A0A0A) : Colors.white38,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: active ? const Color(0xFF0A0A0A) : Colors.white38,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _foreignerForm(BuildContext context) {
    return [
      _label('First name'),
      TextField(
        controller: fName,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          hintText: 'Enter your first name',
          prefixIcon: Icon(Icons.person_outline),
        ),
      ),
      const SizedBox(height: 16),
      _label('Last name'),
      TextField(
        controller: lName,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          hintText: 'Enter your last name',
          prefixIcon: Icon(Icons.person_outline),
        ),
      ),
      const SizedBox(height: 16),
      _label('Contact (phone/email)'),
      TextField(
        controller: fContact,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          hintText: 'email@example.com or +7...',
          prefixIcon: Icon(Icons.email_outlined),
        ),
      ),
      const SizedBox(height: 16),
      _label('Company/Organization Name (Optional)'),
      TextField(
        controller: fCompany,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          hintText: 'e.g. Acme Corp',
          prefixIcon: Icon(Icons.business_outlined),
        ),
      ),
      const SizedBox(height: 16),
      _label('Country'),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, color: Colors.white38, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: CountryListPick(
                initialSelection: selectedCountryCode,
                appBar: AppBar(title: const Text('Select country')),
                theme: CountryTheme(
                  isShowFlag: true,
                  isShowTitle: true,
                  isShowCode: false,
                  isDownIcon: true,
                  showEnglishName: true,
                ),
                onChanged: (code) {
                  setState(() {
                    selectedCountryCode = code?.code ?? 'US';
                    fNationality.text = code?.name ?? 'USA';
                  });
                },
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      CheckboxListTile(
        value: isAccepted,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'I agree to Terms & Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        onChanged: (value) {
          setState(() {
            isAccepted = value ?? false;
          });
        },
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          TextButton(
            onPressed: _showTermsDialog,
            child: Text('View Terms', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
          const Text('•', style: TextStyle(color: Colors.white24)),
          TextButton(
            onPressed: _showPrivacyDialog,
            child: Text('View Privacy', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _hintBox(
        title: 'What you get in PATHWAY',
        lines: const [
          'Priority IIN appointment booking helper',
          'Verified housing database access',
          'Secure Stripe-powered premium services',
          'Visa & document requirements tracker',
          'Immigration assistant powered by Gemini',
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 54,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
            side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.05),
          ),
          onPressed: () {
            loginWithGoogle();
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.network(
                'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1024px-Google_%22G%22_logo.svg.png',
                height: 20,
                errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text(
                'Continue with Google',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.2),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _workerForm(BuildContext context) {
    return [
      _label('IIN'),
      TextField(
        controller: wIin,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          hintText: 'Enter 12-digit IIN',
          prefixIcon: Icon(Icons.badge_outlined),
        ),
      ),
      const SizedBox(height: 16),
      _label('Contact (phone/email)'),
      TextField(
        controller: wContact,
        decoration: const InputDecoration(
          hintText: '+7... or email',
          prefixIcon: Icon(Icons.phone_outlined),
        ),
      ),
      const SizedBox(height: 16),
      _label('City'),
      TextField(
        controller: wCity,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.location_city_outlined),
        ),
      ),
      const SizedBox(height: 16),
      _label('Role title'),
      TextField(
        controller: wRole,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.work_outline),
        ),
      ),
      const SizedBox(height: 16),
      _label('Company/Organization Name (Optional)'),
      TextField(
        controller: wCompany,
        decoration: const InputDecoration(
          hintText: 'e.g. Acme Corp',
          prefixIcon: Icon(Icons.business_outlined),
        ),
      ),
      const SizedBox(height: 16),
      _hintBox(
        title: 'Worker Portal (MVP)',
        lines: const [
          'Manage foreigner profiles',
          'Track visa/IIN queue statuses',
          'Create service orders on behalf of clients',
          'Smart relocation helper chat',
        ],
      ),
    ];
  }

  List<Widget> _adminForm(BuildContext context) {
    return [
      _label('Superuser Email or Username'),
      TextField(
        controller: fContact,
        decoration: const InputDecoration(
          hintText: 'Enter your superuser email or username',
          prefixIcon: Icon(Icons.person_outline),
        ),
      ),
      const SizedBox(height: 16),
      _label('Superuser Password'),
      TextField(
        controller: adminPassword,
        obscureText: true,
        decoration: const InputDecoration(
          hintText: 'Enter your superuser password',
          prefixIcon: Icon(Icons.lock_outline),
        ),
      ),
      const SizedBox(height: 16),
      _hintBox(
        title: 'Admin Dashboard',
        lines: const [
          'View live conversion rates',
          'Track monthly recurring revenue (MRR)',
          'Check subscription churn rate',
          'Monitor DAU/MAU user activity stats',
        ],
      ),
    ];
  }

  Widget _label(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Color(0xFF555555),
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _hintBox({required String title, required List<String> lines}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: Color(0xFFE8D44D),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  final AppState app;
  const Shell({super.key, required this.app});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    final email = widget.app.contact.isNotEmpty ? widget.app.contact : widget.app.workerContact;
    Analytics.track(
      'app_open',
      userEmail: email,
      properties: {'screen': 'shell'},
    );

    if (kIsWeb) {
      try {
        final uri = Uri.parse(html.window.location.href);
        if (uri.queryParameters['payment'] == 'success') {
          widget.app.setPlan(Plan.premium);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Subscription payment successful! Welcome to Premium.'),
                backgroundColor: Colors.green,
              ),
            );
          });
        }
      } catch (e) {
        debugPrint("Web payment status check error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.app.role == UserRole.admin
        ? [
            AdminDashboardView(app: widget.app),
            AccountView(app: widget.app),
          ]
        : [
            HomeView(app: widget.app),
            ServicesView(app: widget.app),
            const VisaView(),
            AssistantView(app: widget.app),
            AccountView(app: widget.app),
          ];
    final safeIndex = index >= pages.length ? 0 : index;
    return Scaffold(
      body: pages[safeIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) {
          setState(() => index = i);
          final email = widget.app.contact.isNotEmpty ? widget.app.contact : widget.app.workerContact;
          if (widget.app.role == UserRole.admin) {
            if (i == 0) {
              Analytics.track('view_admin_dashboard', userEmail: email);
            } else if (i == 1) {
              Analytics.track('view_account', userEmail: email);
            }
            return;
          }
          if (i == 0) {
            Analytics.track('view_home', userEmail: email);
          } else if (i == 1) {
            Analytics.track('view_services', userEmail: email);
          } else if (i == 2) {
            Analytics.track('view_visa', userEmail: email);
          } else if (i == 3) {
            Analytics.track('view_assistant', userEmail: email);
          } else if (i == 4) {
            Analytics.track('view_account', userEmail: email);
          }
        },
        destinations: widget.app.role == UserRole.admin
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'DASHBOARD',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'ACCOUNT',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'HOME',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: 'SERVICES',
                ),
                NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  selectedIcon: Icon(Icons.description),
                  label: 'VISA',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'ASSISTANT',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'ACCOUNT',
                ),
              ],
      ),
    );
  }
}

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? trailing;
  final AppState? app;
  const TopBar({super.key, required this.title, this.trailing, this.app});

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 66,
      titleSpacing: 14,
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/logo.png',
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              const Text('DIGITAL RELOCATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFE8D44D))),
            ],
          ),
        ],
      ),
      actions: [
        if (app != null)
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    app!.locale.languageCode.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                  ),
                ],
              ),
            ),
            onSelected: (value) {
              app!.changeLanguage(value);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('🇬🇧 English')),
              PopupMenuItem(value: 'hi', child: Text('🇮🇳 हिन्दी')),
              PopupMenuItem(value: 'fa', child: Text('🇮🇷 دری')),
              PopupMenuItem(value: 'ar', child: Text('🇸🇦 العربية')),
            ],
          ),
        IconButton(onPressed: () {}, icon: const Icon(Icons.search_rounded)),
        Stack(
          children: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
            Positioned(
              right: 14,
              top: 14,
              child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
            ),
          ],
        ),
        if (trailing != null) Padding(padding: const EdgeInsets.only(right: 10), child: trailing!),
      ],
    );
  }
}

class HomeView extends StatelessWidget {
  final AppState app;
  const HomeView({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final hello = app.role == UserRole.worker ? 'Hello!' : 'Hello, ${app.firstName.isEmpty ? '!' : '${app.firstName}!'}';
    final progress = app.roadmapTotal == 0 ? 0.0 : app.roadmapDone / app.roadmapTotal;

    return Scaffold(
      appBar: TopBar(
        title: 'PATHWAY',
        app: app,
        trailing: CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF1E1E1E),
          backgroundImage: app.avatarUrl.isNotEmpty ? NetworkImage(app.avatarUrl) : null,
          child: app.avatarUrl.isEmpty
              ? Text(
                  app.role == UserRole.worker
                      ? (app.workerRole.isEmpty ? 'W' : app.workerRole.characters.first.toUpperCase())
                      : (app.firstName.isEmpty ? 'U' : app.firstName.characters.first.toUpperCase()),
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE8D44D)),
                )
              : null,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _roadmapCard(hello: hello, progress: progress, done: app.roadmapDone, total: app.roadmapTotal),
          const SizedBox(height: 18),
          if (app.plan == Plan.free && app.role == UserRole.foreigner) ...[
            _premiumUpgradeBanner(context),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              const Text('Priority Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const Spacer(),
              TextButton(onPressed: () {}, child: const Text('View All', style: TextStyle(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 10),
          _priorityTaskTile(app.tasks.isNotEmpty ? app.tasks.first.title : 'Apply for Visa'),
          const SizedBox(height: 10),
          if (app.role == UserRole.worker) ...[
            const SizedBox(height: 6),
            const Text('Worker Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            _workerMiniPanel(app),
          ],
          const SizedBox(height: 12),
          const Text('Quick Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          _quickServiceRow(context),
        ],
      ),
    );
  }

  Widget _premiumUpgradeBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE8D44D),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'LIMITED OFFER',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Unlock Premium Features',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Get unlimited AI answers, priority booking queue, and pre-verified dorms.',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: const Color(0xFFE8D44D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StripePaymentScreen(app: app)),
              );
            },
            child: const Row(
              children: [
                Text(
                  'Upgrade',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                SizedBox(width: 4),
                Icon(Icons.bolt, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roadmapCard({required String hello, required double progress, required int done, required int total}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR ROADMAP', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(hello, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 30, color: Colors.white)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ADAPTATION PROGRESS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white38, fontSize: 12, letterSpacing: 0.6)),
                      const SizedBox(height: 8),
                      Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 28)),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: const Color(0xFF2A2A2A),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE8D44D)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('TASKS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white38, fontSize: 12, letterSpacing: 0.6)),
                    const SizedBox(height: 8),
                    Text('$done/$total', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _priorityTaskTile(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE8D44D).withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFFE8D44D)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('LEGAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.white38, letterSpacing: 0.7)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _workerMiniPanel(AppState app) {
    final rnd = Random(2);
    final managed = [
      {'name': 'Alice Smith', 'iin': 'IIN pending', 'visa': '2026-03-15'},
      {'name': 'Bob Johnson', 'iin': 'Booked PSC', 'visa': '2026-02-28'},
      {'name': 'Charlie Brown', 'iin': 'Done', 'visa': '2026-05-10'},
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Managed foreigners', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 10),
          for (final m in managed.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Color.lerp(const Color(0xFFE8D44D), const Color(0xFF2E7DFF), rnd.nextDouble())!.withOpacity(0.18),
                    child: Text(m['name']!.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE8D44D))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m['name']!, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text('IIN: ${m['iin']} • Visa: ${m['visa']}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickServiceRow(BuildContext context) {
    Widget card({required IconData icon, required String t, required VoidCallback onTap, required Color c}) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            height: 86,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF242424)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: c.withOpacity(0.14), borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: c),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900))),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        card(
          icon: Icons.badge_outlined,
          t: 'IIN Queue',
          c: const Color(0xFF2E7DFF),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IinQueueView(app: app))),
        ),
        const SizedBox(width: 12),
        card(
          icon: Icons.home_outlined,
          t: 'Housing',
          c: const Color(0xFFE8D44D),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HousingView(app: app))),
        ),
      ],
    );
  }
}

class ServicesView extends StatelessWidget {
  final AppState app;
  const ServicesView({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final items = <_ServiceTile>[
      _ServiceTile(
        title: 'IIN Queue',
        subtitle: 'PSC appointment booking (Almaty)',
        icon: Icons.map_outlined,
        color: const Color(0xFF2E7DFF),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IinQueueView(app: app))),
      ),
      _ServiceTile(
        title: 'Housing',
        subtitle: 'Verified dorms & apartments',
        icon: Icons.home_outlined,
        color: const Color(0xFF00BFA6),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HousingView(app: app))),
      ),
      _ServiceTile(
        title: 'Map',
        subtitle: 'Search places in Kazakhstan',
        icon: Icons.map,
        color: const Color(0xFF1DB7FF),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MapView()),
        ),
      ),
      _ServiceTile(
        title: 'Airport',
        subtitle: 'Safe pickup & transfers',
        icon: Icons.flight_takeoff_rounded,
        color: const Color(0xFFFF9800),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AirportView(app: app))),
      ),
      _ServiceTile(
        title: 'Visa & Docs',
        subtitle: 'Visa tracker + EDS + documents',
        icon: Icons.description_outlined,
        color: const Color(0xFF7C4DFF),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisaDocsView(app: app))),
      ),
      _ServiceTile(
  title: 'Migration Registration',
  subtitle: 'Register migration address',
  icon: Icons.assignment_outlined,
  color: const Color(0xFF4CAF50),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => MigrationView(app: app)),
  ),
),
      _ServiceTile(
        title: 'Subscription',
        subtitle: 'Free / Standard / Premium',
        icon: Icons.workspace_premium_outlined,
        color: const Color(0xFF00BFA6),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubscriptionView(app: app))),
      ),
      _ServiceTile(
        title: 'Pay with Stripe',
        subtitle: 'Secure checkout and plan upgrade',
        icon: Icons.payment_rounded,
        color: Colors.deepPurple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StripePaymentScreen(app: app)),
        ),
      ),
    ];

    if (app.role == UserRole.worker) {
      items.insert(
        0,
        _ServiceTile(
          title: 'Worker: Clients',
          subtitle: 'Manage foreigners (demo)',
          icon: Icons.badge_outlined,
          color: const Color(0xFF1DB7FF),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkerClientsView(app: app))),
        ),
      );
    }

    return Scaffold(
      appBar: TopBar(title: 'PATHWAY', app: app),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF242424)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Colors.white38),
                const SizedBox(width: 10),
                Text('Search for a service…', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final it in items) ...[
            _serviceCard(it),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _serviceCard(_ServiceTile it) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: InkWell(
        onTap: it.onTap,
        borderRadius: BorderRadius.circular(22),
        child: Row(
          children: [
          const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: it.color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(it.icon, color: it.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(it.subtitle, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white38)),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTile {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _ServiceTile({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

}

class AssistantView extends StatefulWidget {
  final AppState app;
  const AssistantView({super.key, required this.app});

  @override
  State<AssistantView> createState() => _AssistantViewState();
}

class _AssistantViewState extends State<AssistantView> {
  final c = TextEditingController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.app.chat;
    final isChatLoading = widget.app.isChatLoading;

    return Scaffold(
      appBar: TopBar(title: 'PATHWAY', app: widget.app),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: msgs.length + (isChatLoading ? 1 : 0),
              itemBuilder: (_, i) {
                if (isChatLoading && i == msgs.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      constraints: const BoxConstraints(maxWidth: 240),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF242424)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Assistant is typing...',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final m = msgs[i];
                return Align(
                  alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    constraints: const BoxConstraints(maxWidth: 520),
                    decoration: BoxDecoration(
                      color: m.fromUser ? const Color(0xFFE8D44D) : const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(18),
                      border: m.fromUser ? null : Border.all(color: const Color(0xFF242424)),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: m.fromUser ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      decoration: const InputDecoration(hintText: 'Ask the assistant…'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                      onPressed: isChatLoading ? null : _send,
                      child: const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _send() {
    final t = c.text;
    c.clear();
    widget.app.sendChat(t);
    setState(() {});
  }
}

class AccountView extends StatelessWidget {
  final AppState app;
  const AccountView({super.key, required this.app});

  Future<Map<String, dynamic>> _loadVisaInfo() async {
    final data = await rootBundle.loadString('assets/visa_data.json');
    final Map<String, dynamic> visaData = json.decode(data);
    final raw = (visaData[app.nationalityCode] as Map<String, dynamic>?) ??
        {
          'name': app.nationality.isEmpty ? 'Unknown' : app.nationality,
          'days': 'Unknown',
          'type': 'Contact embassy',
        };

    return buildVisaInfo(
      countryName: app.nationality.isEmpty ? 'Unknown' : app.nationality,
      raw: raw,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = app.role == UserRole.worker
        ? '${app.workerRole} • ${app.workerCity}'
        : '${app.firstName} ${app.lastName}'.trim();

    final contact = app.role == UserRole.worker ? app.workerContact : app.contact;

    return Scaffold(
      appBar: TopBar(title: 'PATHWAY', app: app),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _card(
            child: ListTile(
              onTap: () => _showEditProfileBottomSheet(context),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF1E1E1E),
                backgroundImage: app.avatarUrl.isNotEmpty ? NetworkImage(app.avatarUrl) : null,
                child: app.avatarUrl.isEmpty
                    ? Text(
                        app.role == UserRole.worker
                            ? (app.workerRole.isEmpty ? 'W' : app.workerRole.characters.first.toUpperCase())
                            : (app.firstName.isEmpty ? 'U' : app.firstName.characters.first.toUpperCase()),
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE8D44D), fontSize: 20),
                      )
                    : null,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(name.isEmpty ? 'User' : name, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
                ],
              ),
              subtitle: Text(
                app.role == UserRole.worker
                    ? 'Contact: $contact\nPlan: ${planLabel(app.plan)}'
                    : 'Contact: $contact\nCountry: ${app.nationality}\nPlan: ${planLabel(app.plan)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: planColor(app.plan).withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: Text(planLabel(app.plan), style: TextStyle(fontWeight: FontWeight.w900, color: planColor(app.plan))),
              ),
            ),
          ),
          if (app.role == UserRole.foreigner) ...[
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: _loadVisaInfo(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return _card(
                    child: const ListTile(
                      title: Text('Visa Info', style: TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text('Loading...', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  );
                }

                final info = snapshot.data!;
                return _card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.description_outlined, color: Color(0xFF7C4DFF)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Visa Info: ${info['name']}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _visaLine('Stay', info['days']),
                        _visaLine('Type', info['type']),
                        _visaLine('Entry', info['entry']),
                        _visaLine('Passport', info['passport_validity']),
                        _visaLine('Registration', info['registration']),
                        _visaLine('Documents', info['documents']),
                        _visaLine('Processing', info['processing']),
                        _visaLine('Extension', info['extension']),
                        _visaLine('Notes', info['notes']),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          _nav(
            icon: Icons.receipt_long_outlined,
            title: 'Payments',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsView(app: app))),
          ),
          const SizedBox(height: 12),
          _nav(
            icon: Icons.shopping_bag_outlined,
            title: 'Orders',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersView(app: app))),
          ),
          const SizedBox(height: 12),
          _nav(
            icon: Icons.favorite_border_rounded,
            title: 'Favorites',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FavoritesView(app: app))),
          ),
          const SizedBox(height: 12),
          _nav(
            icon: Icons.workspace_premium_outlined,
            title: 'Subscription',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubscriptionView(app: app))),
          ),
          const SizedBox(height: 12),
          _nav(
            icon: Icons.info_outline,
            title: 'About',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoPage(title: 'About', body: _aboutText))),
          ),
          const SizedBox(height: 12),
          _nav(
            icon: Icons.help_outline,
            title: 'Help',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoPage(title: 'Help', body: _helpText))),
          ),
          const SizedBox(height: 12),
          _nav(
            icon: Icons.article_outlined,
            title: 'Terms of Service',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoPage(title: 'Terms of Service', body: _termsText))),
          ),
          const SizedBox(height: 12),
          _nav(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoPage(title: 'Privacy Policy', body: _privacyText))),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: app.logout,
              child: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav({required IconData icon, required String title, required VoidCallback onTap}) {
    return _card(
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: const Color(0xFFE8D44D)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: child,
    );
  }

  Widget _visaLine(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70, height: 1.4),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w900)),
            TextSpan(text: '${value ?? '-'}'),
          ],
        ),
      ),
    );
  }

  void _showEditProfileBottomSheet(BuildContext context) {
    final firstCtrl = TextEditingController(text: app.role == UserRole.worker ? app.workerRole : app.firstName);
    final lastCtrl = TextEditingController(text: app.role == UserRole.worker ? app.workerCity : app.lastName);
    final urlCtrl = TextEditingController(text: app.avatarUrl);
    final companyCtrl = TextEditingController(text: app.company);

    final presetEmojis = ['👨‍🚀', '👩‍💻', '🦊', '🦁', '🦉', '🐱', '🐼', '🦖', '🦄', '🐨'];
    final emojiMap = {
      '👨‍🚀': 'https://api.dicebear.com/7.x/adventurer/png?seed=astronaut',
      '👩‍💻': 'https://api.dicebear.com/7.x/adventurer/png?seed=developer',
      '🦊': 'https://api.dicebear.com/7.x/bottts/png?seed=fox',
      '🦁': 'https://api.dicebear.com/7.x/bottts/png?seed=lion',
      '🦉': 'https://api.dicebear.com/7.x/bottts/png?seed=owl',
      '🐱': 'https://api.dicebear.com/7.x/bottts/png?seed=cat',
      '🐼': 'https://api.dicebear.com/7.x/bottts/png?seed=panda',
      '🦖': 'https://api.dicebear.com/7.x/bottts/png?seed=dino',
      '🦄': 'https://api.dicebear.com/7.x/bottts/png?seed=unicorn',
      '🐨': 'https://api.dicebear.com/7.x/bottts/png?seed=koala',
    };

    String selectedAvatar = app.avatarUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      app.role == UserRole.worker ? 'Edit Worker Profile' : 'Edit Profile',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      app.role == UserRole.worker ? 'ROLE' : 'FIRST NAME',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white.withOpacity(0.5)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: firstCtrl,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        hintText: app.role == UserRole.worker ? 'Enter role' : 'Enter first name',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      app.role == UserRole.worker ? 'CITY' : 'LAST NAME',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white.withOpacity(0.5)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: lastCtrl,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        hintText: app.role == UserRole.worker ? 'Enter city' : 'Enter last name',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'COMPANY / ORGANIZATION NAME',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white.withOpacity(0.5)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: companyCtrl,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        hintText: 'Enter company or team name',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'CHOOSE AVATAR PRESET',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white.withOpacity(0.5)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: presetEmojis.map((emoji) {
                          final url = emojiMap[emoji]!;
                          final isSelected = selectedAvatar == url;
                          return Padding(
                            padding: const EdgeInsets.only(right: 10.0),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  selectedAvatar = url;
                                  urlCtrl.text = url;
                                });
                              },
                              borderRadius: BorderRadius.circular(28),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFFE8D44D) : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.white.withOpacity(0.12),
                                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'CUSTOM AVATAR IMAGE URL',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white.withOpacity(0.5)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: urlCtrl,
                      onChanged: (val) {
                        setState(() {
                          selectedAvatar = val.trim();
                        });
                      },
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        hintText: 'Paste custom avatar image URL',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8D44D),
                          foregroundColor: const Color(0xFF0A0A0A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: () {
                          if (app.role == UserRole.worker) {
                            app.workerRole = firstCtrl.text.trim();
                            app.workerCity = lastCtrl.text.trim();
                            app.company = companyCtrl.text.trim();
                            app.avatarUrl = selectedAvatar.trim();
                            Analytics.userCompany = app.company; // Sync B2B company
                            if (app.company.isNotEmpty && app.workerContact.isNotEmpty) {
                              Analytics.groupIdentify(app.workerContact, app.company);
                            }
                            app.notifyListeners();
                          } else {
                            app.updateProfile(
                              first: firstCtrl.text,
                              last: lastCtrl.text,
                              avatar: selectedAvatar,
                              company: companyCtrl.text,
                            );
                          }
                          Navigator.pop(context);
                        },
                        child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

const String _aboutText =
    'PATHWAY helps foreigners in Kazakhstan manage onboarding tasks: IIN, migration address, housing, airport pickup, visa reminders, maps and assistant guidance.';

const String _helpText =
    'For support, check Services for the needed flow, open Orders to track requests, and use Assistant for common questions about IIN, visa, housing and airport pickup.';

const String _termsText =
    'By using PATHWAY, users agree to provide accurate information, use the service legally, and understand that this MVP provides guidance and order management rather than official government services.';

const String _privacyText =
    'PATHWAY stores profile, order and analytics data needed to provide the service. Sensitive data should be kept minimal. Data is used for support, order tracking and product analytics.';

class InfoPage extends StatelessWidget {
  final String title;
  final String body;

  const InfoPage({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Text(
              body,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF3C4457),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IinQueueView extends StatefulWidget {
  final AppState app;
  const IinQueueView({super.key, required this.app});

  @override
  State<IinQueueView> createState() => _IinQueueViewState();
}

class _IinQueueViewState extends State<IinQueueView> {
  String selectedCity = 'Almaty';
  late IinCenter center;
  DateTime? date;
  String time = '10:00';
  bool docUpload = false;

  @override
  void initState() {
    super.initState();
    center = iinCentersByCity[selectedCity]?.first ?? iinCentersAlmaty.first;
  }

  List<IinCenter> get _currentCenters => iinCentersByCity[selectedCity] ?? iinCentersAlmaty;

  @override
  Widget build(BuildContext context) {
    final canBook = widget.app.plan != Plan.free || widget.app.role == UserRole.worker;

    return Scaffold(
      appBar: AppBar(title: const Text('IIN Queue')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _info(
            title: canBook ? 'Booking available' : 'Upgrade required',
            text: canBook
                ? 'You can book an appointment. Worker accounts can book too.'
                : 'Free plan: view only. Upgrade to Standard/Premium to book.',
            color: canBook ? const Color(0xFF00BFA6) : const Color(0xFF2E7DFF),
          ),
          const SizedBox(height: 12),
          _section('Choose City'),
          const SizedBox(height: 8),
          _card(
            child: DropdownButtonFormField<String>(
              value: selectedCity,
              items: kazakhCities.map((city) => DropdownMenuItem(value: city, child: Text(city))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    selectedCity = v;
                    center = _currentCenters.first;
                  });
                }
              },
              decoration: const InputDecoration(hintText: 'Choose city'),
            ),
          ),
          const SizedBox(height: 12),
          _section('Choose PSC / ЦОН ($selectedCity)'),
          const SizedBox(height: 8),
          _card(
            child: DropdownButtonFormField<IinCenter>(
              value: center,
              items: _currentCenters.map((c) => DropdownMenuItem(value: c, child: Text('${c.name} • ${c.district}'))).toList(),
              onChanged: (v) => setState(() => center = v ?? _currentCenters.first),
              decoration: const InputDecoration(hintText: 'Choose PSC'),
            ),
          ),
          const SizedBox(height: 12),
          _section('Address'),
          const SizedBox(height: 8),
          _card(
            child: ListTile(
              title: Text(center.address, style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('District: ${center.district}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
              trailing: const Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          _section('Date & Time'),
          const SizedBox(height: 8),
          _card(
            child: ListTile(
              title: Text(date == null ? 'Select date' : 'Date: ${date!.toLocal().toString().split(' ').first}', style: const TextStyle(fontWeight: FontWeight.w900)),
              trailing: const Icon(Icons.date_range_outlined),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 60)),
                  initialDate: now.add(const Duration(days: 1)),
                );
                if (picked != null) setState(() => date = picked);
              },
            ),
          ),
          const SizedBox(height: 10),
          _card(
            child: DropdownButtonFormField<String>(
              value: time,
              items: const ['09:00', '10:00', '11:00', '14:00', '15:00', '16:00']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => time = v ?? '10:00'),
              decoration: const InputDecoration(hintText: 'Select time'),
            ),
          ),
          const SizedBox(height: 10),
          _card(
            child: SwitchListTile(
              value: docUpload,
              onChanged: (v) => setState(() => docUpload = v),
              title: const Text('Upload documents in advance', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: const Text('MVP: checklist only (no backend upload yet).', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
            ),
          ),
          const SizedBox(height: 12),
          _section('Documents & EDS (MVP)'),
          const SizedBox(height: 8),
          _card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Required for IIN (common cases)', style: TextStyle(fontWeight: FontWeight.w900)),
                  SizedBox(height: 8),
                  _Bullet(t: 'Passport (original + copy)'),
                  _Bullet(t: 'Migration card / entry stamp (if applicable)'),
                  _Bullet(t: 'Temporary registration / address confirmation (if required)'),
                  _Bullet(t: 'Application form at PSC/ЦОН'),
                  SizedBox(height: 10),
                  Text('EDS/ЭЦП note', style: TextStyle(fontWeight: FontWeight.w900)),
                  SizedBox(height: 6),
                  Text('EDS is needed for eGov services. In MVP we show steps, later we integrate NCA Layer.', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: !canBook
                  ? null
                  : () async {
                      if (date == null) {
                        _snack('Select date');
                        return;
                      }
                      final details =
                          '${center.name}\n${center.address}\n${date!.toLocal().toString().split(' ').first} at $time'
                          '${docUpload ? '\nDocs: checklist ready' : ''}';
                      final saved = await ApiService.createServiceOrder(
                        name: widget.app.firstName.isNotEmpty ? widget.app.firstName : 'Guest',
                        userEmail: widget.app.contact,
                        serviceType: 'iin',
                        title: 'IIN appointment: ${center.district}',
                        details: details,
                        tariff: 'IIN Booking',
                        status: 'pending',
                      );
                      if (!saved) {
                        _snack('IIN booking was not saved to Django');
                        return;
                      }
                      final o = AppOrder(
                        id: 'ord_${DateTime.now().millisecondsSinceEpoch}',
                        title: 'IIN appointment: ${center.district}',
                        details: details,
                        createdAt: DateTime.now(),
                        status: 'pending',
                      );
                      widget.app.addOrder(o);
                      _snack('IIN appointment saved');
                      Navigator.pop(context);
                    },
              child: const Text('Confirm booking', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: child,
    );
  }

  Widget _section(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16));

  Widget _info({required String title, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.info_outline, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
            ]),
          ),
        ],
      ),
    );
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
}

class _Bullet extends StatelessWidget {
  final String t;
  const _Bullet({required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE8D44D))),
          Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class HousingView extends StatefulWidget {
  final AppState app;
  const HousingView({super.key, required this.app});

  @override
  State<HousingView> createState() => _HousingViewState();
}

class _HousingViewState extends State<HousingView> {
  HousingType? type;
  bool onlyVerified = true;
  RangeValues price = const RangeValues(30000, 550000);
  String district = 'All';

  @override
  Widget build(BuildContext context) {
    final districts = <String>{'All', ...housingItems.map((e) => e.district)}.toList();
    final filtered = housingItems.where((h) {
      if (type != null && h.type != type) return false;
      if (onlyVerified && !h.verified) return false;
      if (h.priceKztMonthly < price.start.round() || h.priceKztMonthly > price.end.round()) return false;
      if (district != 'All' && h.district != district) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Housing'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FavoritesView(app: widget.app))),
            icon: const Icon(Icons.favorite_border_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _filterCard(districts),
          const SizedBox(height: 14),
          for (final h in filtered) ...[
            _housingCard(h),
            const SizedBox(height: 12),
          ],
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(child: Text('No results. Change filters.', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7E8AA5)))),
            ),
        ],
      ),
    );
  }

  Widget _filterCard(List<String> districts) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Filters', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<HousingType?>(
                  value: type,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All types')),
                    ...HousingType.values.map((e) => DropdownMenuItem(value: e, child: Text(housingTypeLabel(e)))),
                  ],
                  onChanged: (v) => setState(() => type = v),
                  decoration: const InputDecoration(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: district,
                  items: districts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setState(() => district = v ?? 'All'),
                  decoration: const InputDecoration(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: onlyVerified,
            onChanged: (v) => setState(() => onlyVerified = v),
            title: const Text('Only verified', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          Text('Price range (KZT/month): ${price.start.round()} — ${price.end.round()}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white70)),
          RangeSlider(
            values: price,
            min: 30000,
            max: 600000,
            divisions: 57,
            onChanged: (v) => setState(() => price = v),
          ),
        ],
      ),
    );
  }

  Widget _housingCard(HousingItem h) {
    final fav = widget.app.favoritesHousing.contains(h.id);
    final badge = h.verified ? 'VERIFIED' : 'LISTED';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: (h.type == HousingType.hotel
                        ? const Color(0xFFFF9800)
                        : h.type == HousingType.dorm
                            ? const Color(0xFF2E7DFF)
                            : const Color(0xFFE8D44D))
                    .withOpacity(0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                h.type == HousingType.hotel
                    ? Icons.hotel_outlined
                    : h.type == HousingType.dorm
                        ? Icons.apartment_outlined
                        : Icons.home_outlined,
                color: h.type == HousingType.hotel
                    ? const Color(0xFFFF9800)
                    : h.type == HousingType.dorm
                        ? const Color(0xFF2E7DFF)
                        : const Color(0xFFE8D44D),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: h.verified ? const Color(0xFFE8D44D).withOpacity(0.14) : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(18),
                        border: h.verified ? null : Border.all(color: const Color(0xFF2A2A2A)),
                      ),
                      child: Row(
                        children: [
                          Icon(h.verified ? Icons.verified_outlined : Icons.info_outline, size: 14, color: h.verified ? const Color(0xFFE8D44D) : Colors.white38),
                          const SizedBox(width: 6),
                          Text(badge, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: h.verified ? const Color(0xFFE8D44D) : Colors.white38)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 18),
                    const SizedBox(width: 4),
                    Text(h.rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(h.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 6),
                Text(h.address, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white38)),
                const SizedBox(height: 10),
                Text('KZT ${h.priceKztMonthly.toString()} / month', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE8D44D))),
              ]),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: () {
                widget.app.toggleFav(h.id);
                setState(() {});
              },
              icon: Icon(fav ? Icons.favorite : Icons.favorite_border_rounded, color: fav ? Colors.red : const Color(0xFF7E8AA5)),
            ),
          ],
        ),
      ),
    );
  }
}

class FavoritesView extends StatelessWidget {
  final AppState app;
  const FavoritesView({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final fav = housingItems.where((e) => app.favoritesHousing.contains(e.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: fav.isEmpty
          ? const Center(child: Text('No favorites yet', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7E8AA5))))
          : ListView(
              padding: const EdgeInsets.all(18),
              children: fav
                  .map((h) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          title: Text(h.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${housingTypeLabel(h.type)} • ${h.address}\nKZT ${h.priceKztMonthly}/month', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}

class AirportView extends StatefulWidget {
  final AppState app;
  const AirportView({super.key, required this.app});

  @override
  State<AirportView> createState() => _AirportViewState();
}

class _AirportViewState extends State<AirportView> {
  DateTime? date;
  String time = '12:00';
  String flight = '';
  int pax = 1;
  String car = 'Economy';
  String pickupLocation = 'Almaty Airport - Terminal 2';
  String destination = '';
  final customPriceController = TextEditingController();

  Future<void> _pickTime() async {
    final parts = time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 12,
        minute: int.tryParse(parts.last) ?? 0,
      ),
    );

    if (picked != null) {
      setState(() {
        time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _submitOrder(int price) async {
    if (widget.app.plan == Plan.free && widget.app.role != UserRole.worker) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Free plan cannot create airport orders')));
      return;
    }

    if (date == null || flight.trim().isEmpty || destination.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill date, flight, destination')));
      return;
    }

    final saved = await ApiService.createAirportOrder(
      name: widget.app.firstName.isNotEmpty ? widget.app.firstName : 'Guest',
      userEmail: widget.app.contact,
      tariff: car,
      price: price,
      pickupLocation: pickupLocation,
      flightNumber: flight.trim(),
      arrivalDate: date!.toLocal().toString().split(' ').first,
      arrivalTime: time,
      passengers: pax,
      destination: destination.trim(),
    );

    if (saved == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order was not saved to Django')));
      return;
    }

    widget.app.addOrder(saved);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order created. Open Payments to complete it.')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final basePrice = car == 'Economy' ? 12000 : car == 'Comfort' ? 18000 : 25000;
    final price = int.tryParse(customPriceController.text.trim()) ?? basePrice;

    return Scaffold(
      appBar: AppBar(title: const Text('Airport Pickup')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _card(
            child: ListTile(
              title: Text(date == null ? 'Select arrival date' : 'Date: ${date!.toLocal().toString().split(' ').first}', style: const TextStyle(fontWeight: FontWeight.w900)),
              trailing: const Icon(Icons.date_range_outlined),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 120)), initialDate: now.add(const Duration(days: 1)));
                if (picked != null) setState(() => date = picked);
              },
            ),
          ),
          const SizedBox(height: 10),
          _card(
            child: ListTile(
              title: Text('Time: $time', style: const TextStyle(fontWeight: FontWeight.w900)),
              trailing: const Icon(Icons.access_time),
              onTap: _pickTime,
            ),
          ),
          const SizedBox(height: 10),
          _card(
            child: DropdownButtonFormField<String>(
              value: pickupLocation,
              items: const [
                'Almaty Airport - Terminal 1',
                'Almaty Airport - Terminal 2',
                'Arrival Hall Exit A',
                'Arrival Hall Exit B',
                'VIP Parking Area',
              ].map((place) => DropdownMenuItem(value: place, child: Text(place))).toList(),
              onChanged: (v) => setState(() => pickupLocation = v ?? 'Almaty Airport - Terminal 2'),
              decoration: const InputDecoration(hintText: 'Pickup location'),
            ),
          ),
          const SizedBox(height: 10),
          _card(
            child: TextField(
              decoration: const InputDecoration(hintText: 'Flight number (e.g., KC 123)'),
              onChanged: (v) => flight = v,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _card(
                  child: DropdownButtonFormField<int>(
                    value: pax,
                    items: [1, 2, 3, 4, 5].map((n) => DropdownMenuItem(value: n, child: Text('$n pax'))).toList(),
                    onChanged: (v) => setState(() => pax = v ?? 1),
                    decoration: const InputDecoration(hintText: 'Passengers'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _card(
                  child: DropdownButtonFormField<String>(
                    value: car,
                    items: const ['Economy', 'Comfort', 'Minivan'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => car = v ?? 'Economy'),
                    decoration: const InputDecoration(hintText: 'Car type'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _card(
            child: TextField(
              controller: customPriceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Your price',
                helperText: 'Default: $basePrice KZT',
              ),
            ),
          ),
          const SizedBox(height: 10),
          _card(
            child: TextField(
              decoration: const InputDecoration(hintText: 'Destination address (hotel/home)'),
              onChanged: (v) => destination = v,
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: ListTile(
              title: const Text('Price', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('$price KZT', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7E8AA5))),
              trailing: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: () => _submitOrder(price),
              child: const Text('Confirm & Pay', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: child,
    );
  }

  @override
  void dispose() {
    customPriceController.dispose();
    super.dispose();
  }
}

class VisaDocsView extends StatefulWidget {
  final AppState app;
  const VisaDocsView({super.key, required this.app});

  @override
  State<VisaDocsView> createState() => _VisaDocsViewState();
}

class _VisaDocsViewState extends State<VisaDocsView> {
  @override
  Widget build(BuildContext context) {
    final d = widget.app.visaExpiry;
    final days = d == null ? null : d.difference(DateTime.now()).inDays;

    Color badgeColor() {
      if (days == null) return const Color(0xFF7E8AA5);
      if (days < 0) return Colors.red;
      if (days <= 14) return const Color(0xFFFF9800);
      return const Color(0xFFE8D44D);
    }

    String badgeText() {
      if (days == null) return 'Not set';
      if (days < 0) return 'Expired';
      return '$days days left';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Visa & Docs')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: badgeColor().withOpacity(0.10),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: badgeColor().withOpacity(0.16), borderRadius: BorderRadius.circular(18)),
                  child: Icon(Icons.event_outlined, color: badgeColor()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Visa Tracker', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(d == null ? 'Set your visa expiry date to receive guidance.' : 'Expiry: ${d.toLocal().toString().split(' ').first}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF3C4457))),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: badgeColor().withOpacity(0.14), borderRadius: BorderRadius.circular(16)),
                  child: Text(badgeText(), style: TextStyle(fontWeight: FontWeight.w900, color: badgeColor())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 54,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  firstDate: now.subtract(const Duration(days: 1)),
                  lastDate: now.add(const Duration(days: 365)),
                  initialDate: now.add(const Duration(days: 30)),
                );
                widget.app.setVisaExpiry(picked);
                if (picked != null) {
                  final details =
                      'Visa expiry updated to ${picked.toLocal().toString().split(' ').first}\nCountry: ${widget.app.nationality}';
                  final saved = await ApiService.createServiceOrder(
                    name: widget.app.firstName.isNotEmpty ? widget.app.firstName : 'Guest',
                    userEmail: widget.app.contact,
                    serviceType: 'visa',
                    title: 'Visa update',
                    details: details,
                    tariff: 'Visa Tracker',
                    status: 'done',
                  );
                  if (saved) {
                    widget.app.addOrder(
                      AppOrder(
                        id: 'ord_${DateTime.now().millisecondsSinceEpoch}',
                        title: 'Visa update',
                        details: details,
                        status: 'done',
                        createdAt: DateTime.now(),
                      ),
                    );
                  }
                }
                setState(() {});
              },
              child: const Text('Set / Update visa expiry date', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(height: 14),
          _block(
            title: 'If visa is expiring soon',
            items: const [
              'Prepare passport + migration documents',
              'Check your registration status',
              'Contact Migration Service (local guidance varies by visa type)',
              'Keep copies of all documents',
            ],
          ),
          const SizedBox(height: 12),
          _block(
            title: 'EDS / ЭЦП (Electronic signature)',
            items: const [
              'Needed for many eGov actions',
              'MVP: checklist only (no integration yet)',
              'Future: NCA Layer + bank + university integrations',
            ],
          ),
          const SizedBox(height: 12),
          _block(
            title: 'IIN documents (MVP guidance)',
            items: const [
              'Passport (original + copy)',
              'Entry stamp / migration card (if applicable)',
              'Address registration confirmation (if required)',
              'Application at PSC/ЦОН',
            ],
          ),
        ],
      ),
    );
  }

  Widget _block({required String title, required List<String> items}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          for (final it in items) _Bullet(t: it),
        ],
      ),
    );
  }
}

class SubscriptionView extends StatelessWidget {
  final AppState app;
  const SubscriptionView({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _plan(
            context,
            p: Plan.free,
            price: '0 KZT',
            features: const ['Services browsing', 'Housing view', 'Visa & Docs guidance', 'Assistant basic'],
          ),
          const SizedBox(height: 12),
          _plan(
            context,
            p: Plan.standard,
            price: '≈ 7.99 USD / month',
            features: const ['IIN booking access', 'Reminders', 'Verified partners (later)', 'Priority support (basic)'],
          ),
          const SizedBox(height: 12),
          _plan(
            context,
            p: Plan.premium,
            price: '≈ 24.99 USD / month',
            features: const ['Priority IIN booking', 'Personal assistant', 'Best housing selection', '24/7 support (later)'],
          ),
        ],
      ),
    );
  }

  Widget _plan(BuildContext context, {required Plan p, required String price, required List<String> features}) {
    final currentPlan = app.plan;
    final selected = currentPlan == p;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(planLabel(p), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const Spacer(),
              if (selected) const Icon(Icons.check_circle, color: Color(0xFFE8D44D)),
            ],
          ),
          const SizedBox(height: 6),
          Text(price, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white38)),
          const SizedBox(height: 10),
          for (final f in features) _Bullet(t: f),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: selected
                  ? null
                  : () {
                      app.setPlan(p);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Plan selected: ${planLabel(p)}')));
                    },
              child: Text(selected ? 'Current plan' : 'Select', style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

class OrdersView extends StatefulWidget {
  final AppState app;
  const OrdersView({super.key, required this.app});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  bool isLoading = true;
  String? errorText;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      final userEmail = widget.app.contact.isNotEmpty ? widget.app.contact : widget.app.workerContact;
      final orders = await ApiService.fetchOrders(userEmail: userEmail);
      widget.app.setOrders(orders);
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorText = 'Could not load orders';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => isLoading = true);
              _loadOrders();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorText != null
              ? Center(child: Text(errorText!, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7E8AA5))))
              : widget.app.orders.isEmpty
          ? const Center(child: Text('No orders yet', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7E8AA5))))
          : ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: widget.app.orders.length,
              itemBuilder: (_, i) {
                final o = widget.app.orders[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    tileColor: const Color(0xFF141414),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: Color(0xFF242424)),
                    ),
                    title: Text(o.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${o.details}\nStatus: ${o.status}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white38)),
                  ),
                );
              },
            ),
    );
  }
}

class PaymentsView extends StatefulWidget {
  final AppState app;
  const PaymentsView({super.key, required this.app});

  @override
  State<PaymentsView> createState() => _PaymentsViewState();
}

class _PaymentsViewState extends State<PaymentsView> {
  bool isPaying = false;

  int _amountFromDetails(AppOrder order) {
    final match = RegExp(r'Price: (\d+) KZT').firstMatch(order.details);
    if (match == null) return 0;
    return int.tryParse(match.group(1) ?? '0') ?? 0;
  }

  Future<void> _pay(AppOrder order) async {
    setState(() => isPaying = true);
    try {
      if (!order.id.startsWith('api_')) {
        final paidOrder = AppOrder(
          id: order.id,
          title: order.title,
          details: order.details,
          status: 'done',
          createdAt: order.createdAt,
        );
        widget.app.updateOrder(paidOrder);
        widget.app.addPayment(
          PaymentRecord(
            id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
            title: paidOrder.title,
            amount: _amountFromDetails(paidOrder).toDouble(),
            date: DateTime.now(),
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment completed')));
        return;
      }

      final paidOrder = await ApiService.payOrder(order.id);
      if (paidOrder == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment failed')));
        return;
      }

      widget.app.updateOrder(paidOrder);
      widget.app.addPayment(
        PaymentRecord(
          id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
          title: paidOrder.title,
          amount: _amountFromDetails(paidOrder).toDouble(),
          date: DateTime.now(),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment completed')));
    } finally {
      if (mounted) setState(() => isPaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingOrders = widget.app.orders.where((order) => order.status == 'pending').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (pendingOrders.isNotEmpty) ...[
            const Text('Pending payments', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),
            for (final order in pendingOrders)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  tileColor: const Color(0xFF141414),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFF242424)),
                  ),
                  title: Text(order.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(order.details, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white38)),
                  trailing: FilledButton(
                    onPressed: isPaying ? null : () => _pay(order),
                    child: const Text('Pay'),
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
          const Text('Payment history', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          if (widget.app.payments.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(child: Text('No payments yet', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7E8AA5)))),
            )
          else
            for (final p in widget.app.payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  tileColor: const Color(0xFF141414),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFF242424)),
                  ),
                  title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('Amount: ${p.amount.toStringAsFixed(2)}\nDate: ${p.date.toLocal()}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white38)),
                ),
              ),
        ],
      ),
    );
  }
}

class WorkerClientsView extends StatefulWidget {
  final AppState app;
  const WorkerClientsView({super.key, required this.app});

  @override
  State<WorkerClientsView> createState() => _WorkerClientsViewState();
}

class _WorkerClientsViewState extends State<WorkerClientsView> {
  List<AppOrder> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.fetchOrders(userEmail: '');
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _completeOrder(AppOrder order) async {
    try {
      final updated = await ApiService.payOrder(order.id);
      if (updated != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order marked as Completed (Done) successfully!')),
        );
        _fetchOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update order status.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating order: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Worker: Client Orders', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: const Color(0xFF0A0A0A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchOrders,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8D44D)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 10),
                        Text('Error loading orders: $_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchOrders,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text(
                            'No active orders found.',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.45)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(18),
                      itemCount: _orders.length,
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        final isCompleted = order.status.toLowerCase() == 'done';
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: Color(0xFF242424)),
                          ),
                          elevation: 0,
                          color: const Color(0xFF141414),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? const Color(0xFFE8D44D).withOpacity(0.14)
                                            : const Color(0xFFFFF3E0).withOpacity(0.14),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        order.status.toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                          color: isCompleted
                                              ? const Color(0xFFE8D44D)
                                              : const Color(0xFFFF9800),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Order ${order.id}',
                                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                    ),
                                  ],
                                ) ,
                                const SizedBox(height: 12),
                                Text(
                                  order.title,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF2A2A2A)),
                                  ),
                                  child: Text(
                                    order.details,
                                    style: const TextStyle(height: 1.4, color: Colors.white70, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                if (!isCompleted) ...[
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 44,
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFFE8D44D),
                                        foregroundColor: const Color(0xFF0A0A0A),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: () => _completeOrder(order),
                                      icon: const Icon(Icons.check_circle_outline, size: 18),
                                      label: const Text('Mark as Done', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
class MigrationView extends StatefulWidget {
  final AppState app;

  const MigrationView({super.key, required this.app});

  @override
  State<MigrationView> createState() => _MigrationViewState();
}

class _MigrationViewState extends State<MigrationView> {

  final passportController = TextEditingController();
  final addressController = TextEditingController();
  final contactController = TextEditingController();

  Future<void> _submitMigration() async {
    if (widget.app.plan == Plan.free && widget.app.role != UserRole.worker) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Free plan cannot submit migration requests")),
      );
      return;
    }

    if (passportController.text.trim().isEmpty ||
        addressController.text.trim().isEmpty ||
        contactController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    debugPrint("Migration submit:");
    debugPrint("passport=${passportController.text.trim()}");
    debugPrint("address=${addressController.text.trim()}");
    debugPrint("contact=${contactController.text.trim()}");

    await FirebaseFirestore.instance
        .collection("migration_requests")
        .add({
      "passport": passportController.text.trim(),
      "address": addressController.text.trim(),
      "contact": contactController.text.trim(),
      "createdAt": DateTime.now(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Submitted")),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("Migration Registration")),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [

            TextField(
              controller: passportController,
              decoration: const InputDecoration(
                labelText: "Passport number",
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: "Address in Kazakhstan",
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: contactController,
              decoration: const InputDecoration(
                labelText: "Contact phone/email",
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,

              child: ElevatedButton(
                onPressed: _submitMigration,

                child: const Text("Submit"),
              ),
            )

          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    passportController.dispose();
    addressController.dispose();
    contactController.dispose();
    super.dispose();
  }
}


class AdminDashboardView extends StatefulWidget {
  final AppState app;
  const AdminDashboardView({super.key, required this.app});

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  Map<String, dynamic>? _kpis;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchKpi();
  }

  Future<void> _fetchKpi() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/analytics/kpi/'),
        headers: {
          if (widget.app.authToken != null)
            'Authorization': 'Bearer ${widget.app.authToken}',
        },
      );
      if (response.statusCode == 200) {
        setState(() {
          _kpis = jsonDecode(response.body);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load KPIs: ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error connecting to API: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: TopBar(
        title: 'KPI DASHBOARD',
        app: widget.app,
        trailing: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: _fetchKpi,
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8D44D)))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                          const SizedBox(height: 16),
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _fetchKpi,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildDashboard(),
      ),
    );
  }

  Widget _buildDashboard() {
    final conversion = _kpis?['conversion_rate_percent'] ?? 0.0;
    final mrr = _kpis?['mrr_usd'] ?? 0.0;
    final churn = _kpis?['churn_rate_percent'] ?? 0.0;
    final dau = _kpis?['dau'] ?? 0;
    final mau = _kpis?['mau'] ?? 0;
    final stickiness = _kpis?['stickiness_ratio_percent'] ?? 0.0;
    final totalUsers = _kpis?['registered_users'] ?? 0;
    final premiumUsers = _kpis?['premium_users'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live Startup Metrics',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Dynamic KPI stats computed from database logs.',
            style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 2 : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildKpiCard('CONVERSION RATE', '$conversion%', 'Premium users / Total registrations'),
              _buildKpiCard('MONTHLY REVENUE (MRR)', '\$${mrr.toStringAsFixed(2)}', 'Active premium users * \$24.99'),
              _buildKpiCard('CHURN RATE', '$churn%', 'Cancellations ratio'),
              _buildKpiCard('DAU / MAU ACTIVITY', '$dau / $mau', 'Stickiness Ratio: $stickiness%'),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'User Demographics',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  _buildStatRow('Total Registered Users', '$totalUsers'),
                  const Divider(color: Colors.white10),
                  _buildStatRow('Total Premium Pass Holders', '$premiumUsers'),
                  const Divider(color: Colors.white10),
                  _buildStatRow('Free Tier Users', '${totalUsers - premiumUsers}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, String desc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFE8D44D),
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
