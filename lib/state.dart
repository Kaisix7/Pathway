import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'analytics.dart';
import 'models.dart';
import 'gemini_service.dart';
import 'api_service.dart';

class AppState extends ChangeNotifier {
  bool authed = false;

  Locale locale = const Locale('en');

  void changeLanguage(String code) {
    locale = Locale(code);
    notifyListeners();
  }

  UserRole role = UserRole.foreigner;
  Plan plan = Plan.free;

  String firstName = '';
  String lastName = '';
  String contact = '';
  String nationality = '';
  String nationalityCode = 'US';
  String avatarUrl = '';
  String company = '';
  String utmSource = '';
  String utmMedium = '';
  String utmCampaign = '';

  String workerIin = '';
  String workerCity = 'Almaty';
  String workerContact = '';
  String workerRole = 'Coordinator';
  String savedEmail = '';

  /// JWT auth token from backend (OAuth or login)
  String? authToken;

  DateTime? visaExpiry;

  final List<TaskItem> tasks = [
    TaskItem(title: 'Get IIN'),
    TaskItem(title: 'Open bank account'),
    TaskItem(title: 'Register address'),
    TaskItem(title: 'Buy SIM card'),
    TaskItem(title: 'Medical insurance'),
    TaskItem(title: 'University documents'),
  ];
  int get roadmapDone => tasks.where((t) => t.done).length;

  int get roadmapTotal => tasks.length;

  double get progress =>
      roadmapTotal == 0 ? 0 : roadmapDone / roadmapTotal;

  final Set<String> favoritesHousing = {};

  final List<AppOrder> orders = [];
  final List<PaymentRecord> payments = [];

  final List<ChatMsg> chat = [
    ChatMsg(
      fromUser: false,
      text:
          "Hi! I'm Pathway Assistant. Ask me about IIN, visa deadlines, housing, or EDS.",
      ts: DateTime.now(),
    ),
  ];

  bool isChatLoading = false;

  final gemini = GeminiService();

  // ── OAuth Login ──────────────────────────────────────────────────────

  /// Login with OAuth token received from Google callback
  Future<void> loginWithOAuthToken({
    required String token,
    required String email,
    String name = '',
  }) async {
    authToken = token;
    savedEmail = email;
    role = UserRole.foreigner;

    // Parse first/last name from full name
    final parts = name.trim().split(' ');
    firstName = parts.isNotEmpty ? parts.first : '';
    lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    contact = email;
    nationality = '';
    nationalityCode = 'US';

    FirebaseFirestore.instance.collection('users').add({
      'role': 'foreigner',
      'firstName': firstName,
      'lastName': lastName,
      'contact': contact,
      'source': 'google_oauth',
      'createdAt': DateTime.now(),
    }).catchError((e) {
      debugPrint('FIREBASE ERROR: $e');
    });

    await Analytics.trackLogin(email, source: 'google');
    await Analytics.identify(email, properties: {
      'name': name,
      'source': 'google_oauth',
    });

    authed = true;
    notifyListeners();

    // Sync plan from backend (non-blocking)
    await fetchAndApplyPlan();
  }

  // ── Foreigner Login ─────────────────────────────────────────────────

  Future<void> loginForeigner({
    required String firstName,
    required String lastName,
    required String contact,
    required String nationality,
    String nationalityCode = 'US',
    String company = '',
    String utmSource = '',
    String utmMedium = '',
    String utmCampaign = '',
    String? token,
  }) async {
    savedEmail = contact;
    role = UserRole.foreigner;

    this.firstName = firstName.trim();
    this.lastName = lastName.trim();
    this.contact = contact.trim();
    this.nationality = nationality.trim();
    this.nationalityCode = nationalityCode;
    this.company = company.trim();
    this.utmSource = utmSource.trim();
    this.utmMedium = utmMedium.trim();
    this.utmCampaign = utmCampaign.trim();

    // Store token if provided (e.g. from backend login response)
    if (token != null && token.isNotEmpty) {
      authToken = token;
    }

    // Sync to Analytics static properties
    Analytics.userCompany = this.company;
    Analytics.utmSource = this.utmSource;
    Analytics.utmMedium = this.utmMedium;
    Analytics.utmCampaign = this.utmCampaign;

    FirebaseFirestore.instance.collection('users').add({
      'role': 'foreigner',
      'firstName': this.firstName,
      'lastName': this.lastName,
      'contact': this.contact,
      'nationality': this.nationality,
      'company': this.company,
      'utm_source': this.utmSource,
      'utm_medium': this.utmMedium,
      'utm_campaign': this.utmCampaign,
      'createdAt': DateTime.now(),
    }).then((_) {
      debugPrint("USER SAVED TO FIREBASE");
    }).catchError((e) {
      debugPrint("FIREBASE ERROR: $e");
    });

    await Analytics.trackSignUp(
      this.contact,
      name: '${this.firstName} ${this.lastName}',
      nationality: this.nationality,
    );
    await Analytics.track(
      'app_open',
      userEmail: this.contact,
      properties: {'source': 'login'},
    );

    authed = true;
    notifyListeners();

    // Sync plan from backend so a previously-subscribed user
    // immediately sees their correct plan without re-purchasing.
    await fetchAndApplyPlan();
  }

  void loginWorker({
    required String iin,
    required String contact,
    required String city,
    required String roleName,
    String company = '',
  }) {
    role = UserRole.worker;

    workerIin = iin.trim();
    workerContact = contact.trim();
    workerCity = city.trim().isEmpty ? 'Almaty' : city.trim();
    workerRole = roleName.trim().isEmpty ? 'Coordinator' : roleName.trim();
    this.company = company.trim();

    // Sync to Analytics
    Analytics.userCompany = this.company;

    Analytics.trackLogin(workerContact, source: 'worker');
    Analytics.track(
      'app_open',
      userEmail: workerContact,
      properties: {'role': 'worker'},
    );

    authed = true;
    notifyListeners();
  }

  Future<void> loginAdmin(String email, String password) async {
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Login failed');
    }

    final data = jsonDecode(response.body);
    if (data['user']['role'] != 'admin') {
      throw Exception('Access denied. Admin role required.');
    }

    savedEmail = email;
    role = UserRole.admin;
    authToken = data['token'];
    authed = true;

    // Apply plan from login response immediately
    plan = _parsePlan(data['user']['plan'] as String?);

    await Analytics.trackLogin(email, source: 'admin');
    await Analytics.identify(email, properties: {
      'role': 'admin',
    });

    notifyListeners();

    // Re-fetch plan from backend to confirm
    await fetchAndApplyPlan();
  }

  void logout() {
    // Clear all user data
    authed = false;
    role = UserRole.foreigner;
    plan = Plan.free;
    authToken = null;
    
    // Clear foreigner data
    firstName = '';
    lastName = '';
    contact = '';
    nationality = '';
    nationalityCode = 'US';
    savedEmail = '';
    avatarUrl = '';
    company = '';
    utmSource = '';
    utmMedium = '';
    utmCampaign = '';
    
    // Clear worker data
    workerIin = '';
    workerCity = 'Almaty';
    workerContact = '';
    workerRole = 'Coordinator';
    
    // Clear app data
    visaExpiry = null;
    favoritesHousing.clear();
    orders.clear();
    payments.clear();
    chat.clear();
    
    // Reset chat with initial message
    chat.add(
      ChatMsg(
        fromUser: false,
        text: 'Hi! I\'m Pathway Assistant. Ask me about IIN, visa deadlines, housing, or EDS.',
        ts: DateTime.now(),
      ),
    );
    
    // Reset tasks to default
    tasks.clear();
    tasks.addAll([
      TaskItem(title: 'Get IIN'),
      TaskItem(title: 'Open bank account'),
      TaskItem(title: 'Register address'),
      TaskItem(title: 'Buy SIM card'),
      TaskItem(title: 'Medical insurance'),
      TaskItem(title: 'University documents'),
    ]);
    
    notifyListeners();
  }

  void updateProfile({required String first, required String last, required String avatar, String company = ''}) {
    firstName = first.trim();
    lastName = last.trim();
    avatarUrl = avatar.trim();
    this.company = company.trim();
    Analytics.userCompany = this.company;
    if (this.company.isNotEmpty && contact.isNotEmpty) {
      Analytics.groupIdentify(contact, this.company);
    }
    notifyListeners();
  }

  /// Convert the backend plan string (e.g. 'premium', 'standard', 'free') to a [Plan] enum.
  Plan _parsePlan(String? planStr) {
    switch (planStr) {
      case 'premium':
        return Plan.premium;
      case 'standard':
        return Plan.standard;
      default:
        return Plan.free;
    }
  }

  /// Fetch the user's plan from the backend and update local state.
  /// Silently ignores errors so it never blocks the login flow.
  Future<void> fetchAndApplyPlan() async {
    if (authToken == null || authToken!.isEmpty) return;
    try {
      final profile = await ApiService.fetchUserProfile(authToken!);
      if (profile == null) return;
      final backendPlan = _parsePlan(profile['plan'] as String?);
      if (backendPlan != plan) {
        plan = backendPlan;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('fetchAndApplyPlan error: $e');
    }
  }

  void setPlan(Plan p) {
    plan = p;

    if (p != Plan.free) {
      payments.insert(
        0,
        PaymentRecord(
          id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Subscription: ${planLabel(p)}',
          amount: p == Plan.standard ? 7.99 : 24.99,
          date: DateTime.now(),
          status: PaymentStatus.completed,
        ),
      );
    }

    notifyListeners();
  }

  void toggleFav(String id) {
    if (favoritesHousing.contains(id)) {
      favoritesHousing.remove(id);
    } else {
      favoritesHousing.add(id);
    }

    notifyListeners();
  }

  void toggleTask(int index) {
    tasks[index].done = !tasks[index].done;
    notifyListeners();
  }

  void addOrder(AppOrder o) {
    orders.insert(0, o);
    final email = contact.isNotEmpty ? contact : workerContact;
    Analytics.track(
      'activation',
      userEmail: email,
      properties: {
        'title': o.title,
        'status': o.status,
      },
    );
    notifyListeners();
  }

  void updateOrder(AppOrder updatedOrder) {
    final index = orders.indexWhere((order) => order.id == updatedOrder.id);
    if (index == -1) {
      orders.insert(0, updatedOrder);
    } else {
      orders[index] = updatedOrder;
    }
    notifyListeners();
  }

  void setOrders(List<AppOrder> newOrders) {
    orders
      ..clear()
      ..addAll(newOrders);
    notifyListeners();
  }

  void addPayment(PaymentRecord p) {
    payments.insert(0, p);
    notifyListeners();
  }

  void setVisaExpiry(DateTime? d) {
    visaExpiry = d;
    notifyListeners();
  }

  Future<void> sendChat(String text) async {

    final t = text.trim();
    if (t.isEmpty) return;

    chat.add(ChatMsg(fromUser: true, text: t, ts: DateTime.now()));
    isChatLoading = true;
    notifyListeners();

    final reply = await gemini.ask(t);

    chat.add(
      ChatMsg(
        fromUser: false,
        text: reply,
        ts: DateTime.now(),
      ),
    );

    isChatLoading = false;
    notifyListeners();
  }

  String _assistantReply(String q) {
    final s = q.toLowerCase();

    if (s.contains('iin') || s.contains('иин')) {
      return 'IIN (ИИН) is your personal identification number in Kazakhstan. In the app: Services → IIN Queue → choose a PSC/ЦОН in Almaty and book a time.';
    }

    if (s.contains('eds') ||
        s.contains('эцп') ||
        s.contains('key') ||
        s.contains('электрон')) {
      return 'EDS/ЭЦП (electronic signature) is often needed for eGov services. In MVP: Services → Visa & Docs → EDS.';
    }

    if (s.contains('visa') ||
        s.contains('виза') ||
        s.contains('expiry') ||
        s.contains('сгора')) {
      final d = visaExpiry;

      if (d == null) {
        return 'Add visa expiry in Services → Visa Tracker to see days remaining.';
      }

      final days = d.difference(DateTime.now()).inDays;

      if (days < 0) {
        return 'Your visa expired ${days.abs()} days ago. Contact Migration Service immediately.';
      }

      if (days <= 14) {
        return 'Urgent: visa expires in $days days.';
      }

      return 'Your visa expires in $days days.';
    }

    if (s.contains('housing') ||
        s.contains('жиль') ||
        s.contains('отел') ||
        s.contains('общаг') ||
        s.contains('кварт')) {
      return 'Open Services → Housing to browse hotels, dorms and apartments.';
    }

    if (s.contains('airport') ||
        s.contains('аэропорт') ||
        s.contains('transfer') ||
        s.contains('трансфер')) {
      return 'Airport pickup is available in Services → Airport.';
    }

    return 'Ask about IIN, visa deadlines, housing or airport transfer.';
  }
}
