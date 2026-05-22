import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:convert';

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

class AuthView extends StatefulWidget {
  final AppState app;
  const AuthView({super.key, required this.app});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  UserRole role = UserRole.foreigner;
  String selectedCountryCode = 'US';
  bool isAccepted = false;

  final fName = TextEditingController();
  final lName = TextEditingController();
  final fContact = TextEditingController();
  final fNationality = TextEditingController();

  final wIin = TextEditingController();
  final wContact = TextEditingController();
  final wCity = TextEditingController(text: 'Almaty');
  final wRole = TextEditingController(text: 'Coordinator');

  @override
  void initState() {
    super.initState();
    fNationality.text = 'USA';
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
        // Basic onboarding flow stays inside existing screens:
        // registration -> Services -> Airport -> order creation.
        final registered = await ApiService.registerUser(
          name: '${fName.text.trim()} ${lName.text.trim()}',
          email: fContact.text.trim(),
        );

        if (!registered) {
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
    );
  }

  @override
  void dispose() {
    fName.dispose();
    lName.dispose();
    fContact.dispose();
    fNationality.dispose();
    wIin.dispose();
    wContact.dispose();
    wCity.dispose();
    wRole.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grad = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6D5BFF), Color(0xFF1DB7FF)],
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: grad),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.public, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'PATHWAY',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your guide in Kazakhstan',
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            color: Colors.white.withOpacity(0.55),
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _roleSwitch(),
                                const SizedBox(height: 18),
                                Expanded(
                                  child: ListView(
                                    children: [
                                      if (role == UserRole.foreigner) ..._foreignerForm(context),
                                      if (role == UserRole.worker) ..._workerForm(context),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    ),
                                    onPressed: _handleStartPressed,
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text('Start', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                        SizedBox(width: 10),
                                        Icon(Icons.arrow_forward_rounded),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'MVP build • Flutter',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleSwitch() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
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
          const SizedBox(width: 8),
          Expanded(
            child: _seg(
              active: role == UserRole.worker,
              icon: Icons.badge_outlined,
              text: 'Worker',
              onTap: () => setState(() => role = UserRole.worker),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg({required bool active, required IconData icon, required String text, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2E7DFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : const Color(0xFF3C4457)),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: active ? Colors.white : const Color(0xFF3C4457),
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
      TextField(controller: fName, textInputAction: TextInputAction.next),
      const SizedBox(height: 12),
      _label('Last name'),
      TextField(controller: lName, textInputAction: TextInputAction.next),
      const SizedBox(height: 12),
      _label('Contact (phone/email)'),
      TextField(controller: fContact, keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 12),
      _label('Country'),
      CountryListPick(
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
      const SizedBox(height: 8),
      Text(
        fNationality.text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF4A556F),
        ),
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        value: isAccepted,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'I agree to Terms and Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onChanged: (value) {
          setState(() {
            isAccepted = value ?? false;
          });
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _showTermsDialog,
              child: const Text('View Terms'),
            ),
            TextButton(
              onPressed: _showPrivacyDialog,
              child: const Text('View Privacy'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _hintBox(
        title: 'What you get in MVP',
        lines: const [
          'IIN queue booking (Almaty PSC list)',
          'Housing with filters + favorites',
          'Airport pickup order',
          'Visa & Docs tracker + EDS checklist',
          'AI assistant chat (MVP)',
        ],
      ),
      TextButton(
  onPressed: () {
    _snack(context, 'Password reset link sent (demo)');
  },
  child: const Text("Forgot password?"),
),
    ];
  }

  List<Widget> _workerForm(BuildContext context) {
    return [
      _label('IIN'),
      TextField(controller: wIin, keyboardType: TextInputType.number),
      const SizedBox(height: 12),
      _label('Contact (phone/email)'),
      TextField(controller: wContact),
      const SizedBox(height: 12),
      _label('City'),
      TextField(controller: wCity),
      const SizedBox(height: 12),
      _label('Role title'),
      TextField(controller: wRole),
      const SizedBox(height: 12),
      _hintBox(
        title: 'Worker mode (MVP)',
        lines: const [
          'Manage foreigners (demo list)',
          'Track visa/IIN status (demo)',
          'Create service orders on behalf of clients',
          'AI assistant helps answer FAQs',
        ],
      ),
    ];
  }

  Widget _label(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.7, color: Color(0xFF4A556F), fontSize: 12),
      ),
    );
  }

  Widget _hintBox({required String title, required List<String> lines}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF283046))),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2E7DFF))),
                  Expanded(child: Text(l, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF3C4457)))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
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
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeView(app: widget.app),
      ServicesView(app: widget.app),
      const VisaView(),
      AssistantView(app: widget.app),
      AccountView(app: widget.app),
    ];
  return Scaffold(
    body: Column(
  children: [

  
    DropdownButton<String>(
      value: widget.app.locale.languageCode,
      items: const [
        DropdownMenuItem(value: 'en', child: Text('English')),
        DropdownMenuItem(value: 'hi', child: Text('हिन्दी')),
        DropdownMenuItem(value: 'fa', child: Text('دری')),
        DropdownMenuItem(value: 'ar', child: Text('العربية')),
      ],
      onChanged: (value) {
        widget.app.changeLanguage(value!);
      },
    ),

    ///  ЭКРАН
    Expanded(
      child: pages[index],
    ),
  ],
),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => setState(() => index = i),
      destinations: const [
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
  const TopBar({super.key, required this.title, this.trailing});

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 66,
      titleSpacing: 14,
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF00BFA6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('P', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              const Text('DIGITAL RELOCATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF00BFA6))),
            ],
          ),
        ],
      ),
      actions: [
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
        trailing: CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFDEF8F3),
          child: Text(
            app.role == UserRole.worker
                ? (app.workerRole.isEmpty ? 'W' : app.workerRole.characters.first.toUpperCase())
                : (app.firstName.isEmpty ? 'U' : app.firstName.characters.first.toUpperCase()),
            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00BFA6)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _roadmapCard(hello: hello, progress: progress, done: app.roadmapDone, total: app.roadmapTotal),
          const SizedBox(height: 18),
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

  Widget _roadmapCard({required String hello, required double progress, required int done, required int total}) {
    final grad = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF00BFA6), Color(0xFF0D8B7A)],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: grad,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 22, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR ROADMAP', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white70, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(hello, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 30, color: Colors.white)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ADAPTATION PROGRESS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white70, fontSize: 12, letterSpacing: 0.6)),
                      const SizedBox(height: 8),
                      Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 28)),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: Colors.white.withOpacity(0.16),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('TASKS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white70, fontSize: 12, letterSpacing: 0.6)),
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
        color: const Color(0xFFEAECEF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFCCF6EE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF00BFA6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('LEGAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF7E8AA5), letterSpacing: 0.7)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Managed foreigners', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.85))),
          const SizedBox(height: 10),
          for (final m in managed.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Color.lerp(const Color(0xFF00BFA6), const Color(0xFF2E7DFF), rnd.nextDouble())!.withOpacity(0.18),
                    child: Text(m['name']!.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00BFA6))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m['name']!, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text('IIN: ${m['iin']} • Visa: ${m['visa']}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5), fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E8AA5)),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
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
          c: const Color(0xFF00BFA6),
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
      appBar: const TopBar(title: 'PATHWAY'),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Color(0xFF7E8AA5)),
                const SizedBox(width: 10),
                Text('Search for a service…', style: TextStyle(color: Colors.black.withOpacity(0.45), fontWeight: FontWeight.w700)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
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
                  Text(it.subtitle, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFFF1F4FA), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E8AA5)),
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
      appBar: const TopBar(title: 'PATHWAY'),
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 8))],
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
                              color: Color(0xFF263046),
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
                      color: m.fromUser ? const Color(0xFF00BFA6) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 8))],
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: m.fromUser ? Colors.white : const Color(0xFF263046),
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
      appBar: const TopBar(title: 'PATHWAY'),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _card(
            child: ListTile(
              title: Text(name.isEmpty ? 'User' : name, style: const TextStyle(fontWeight: FontWeight.w900)),
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
          decoration: BoxDecoration(color: const Color(0xFFF1F4FA), borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: const Color(0xFF3C4457)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E8AA5)),
        onTap: onTap,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: child,
    );
  }

  Widget _visaLine(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF3C4457), height: 1.4),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w900)),
            TextSpan(text: '${value ?? '-'}'),
          ],
        ),
      ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
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
              Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF3C4457))),
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
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00BFA6))),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
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
              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3C4457))),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
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
                            : const Color(0xFF00BFA6))
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
                        : const Color(0xFF00BFA6),
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
                        color: h.verified ? const Color(0xFF00BFA6).withOpacity(0.14) : const Color(0xFF7E8AA5).withOpacity(0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Icon(h.verified ? Icons.verified_outlined : Icons.info_outline, size: 14, color: h.verified ? const Color(0xFF00BFA6) : const Color(0xFF7E8AA5)),
                          const SizedBox(width: 6),
                          Text(badge, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: h.verified ? const Color(0xFF00BFA6) : const Color(0xFF7E8AA5))),
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
                Text(h.address, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
                const SizedBox(height: 10),
                Text('KZT ${h.priceKztMonthly.toString()} / month', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00BFA6))),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
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
      return const Color(0xFF00BFA6);
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(planLabel(p), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const Spacer(),
              if (selected) const Icon(Icons.check_circle, color: Color(0xFF00BFA6)),
            ],
          ),
          const SizedBox(height: 6),
          Text(price, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7E8AA5))),
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
                    tileColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    title: Text(o.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${o.details}\nStatus: ${o.status}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
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
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  title: Text(order.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(order.details, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
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
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('Amount: ${p.amount.toStringAsFixed(2)}\nDate: ${p.date.toLocal()}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
                ),
              ),
        ],
      ),
    );
  }
}

class WorkerClientsView extends StatelessWidget {
  final AppState app;
  const WorkerClientsView({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final demo = [
      {'name': 'Alice Smith', 'nationality': 'USA', 'visa': '2026-03-15', 'iin': 'Pending'},
      {'name': 'Bob Johnson', 'nationality': 'UK', 'visa': '2026-02-28', 'iin': 'Booked'},
      {'name': 'Charlie Brown', 'nationality': 'Canada', 'visa': '2026-05-10', 'iin': 'Done'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Worker: Clients')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1DB7FF).withOpacity(0.10), borderRadius: BorderRadius.circular(22)),
            child: const Text('MVP demo list. Next step: real backend + CRM dashboard.', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          for (final c in demo)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF1DB7FF).withOpacity(0.14),
                  child: Text(c['name']!.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1DB7FF))),
                ),
                title: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('Nationality: ${c['nationality']}\nVisa: ${c['visa']} • IIN: ${c['iin']}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7E8AA5))),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
        ],
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

    print("Migration submit:");
    print("passport=${passportController.text.trim()}");
    print("address=${addressController.text.trim()}");
    print("contact=${contactController.text.trim()}");

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
