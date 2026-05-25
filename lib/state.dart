import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'analytics.dart';
import 'models.dart';
import 'gemini_service.dart';

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

  String workerIin = '';
  String workerCity = 'Almaty';
  String workerContact = '';
  String workerRole = 'Coordinator';
  String savedEmail = '';

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
          'Hi! I’m Pathway Assistant. Ask me about IIN, visa deadlines, housing, or EDS.',
      ts: DateTime.now(),
    ),
  ];

  bool isChatLoading = false;

  final gemini = GeminiService();

  Future<void> loginForeigner({
    required String firstName,
    required String lastName,
    required String contact,
    required String nationality,
    String nationalityCode = 'US',
  }) async {
    savedEmail = contact;
    role = UserRole.foreigner;

    this.firstName = firstName.trim();
    this.lastName = lastName.trim();
    this.contact = contact.trim();
    this.nationality = nationality.trim();
    this.nationalityCode = nationalityCode;

    try {
      await FirebaseFirestore.instance.collection('users').add({
        'role': 'foreigner',
        'firstName': this.firstName,
        'lastName': this.lastName,
        'contact': this.contact,
        'nationality': this.nationality,
        'createdAt': DateTime.now(),
      });

      print("USER SAVED TO FIREBASE");
    } catch (e) {
      print("FIREBASE ERROR:");
      print(e);
    }

    await Analytics.track(
      'registration',
      userEmail: this.contact,
      properties: {
        'role': 'foreigner',
        'nationality': this.nationality,
      },
    );
    await Analytics.track(
      'app_open',
      userEmail: this.contact,
      properties: {'source': 'login'},
    );

    authed = true;
    notifyListeners();
  }

  void loginWorker({
    required String iin,
    required String contact,
    required String city,
    required String roleName,
  }) {
    role = UserRole.worker;

    workerIin = iin.trim();
    workerContact = contact.trim();
    workerCity = city.trim().isEmpty ? 'Almaty' : city.trim();
    workerRole = roleName.trim().isEmpty ? 'Coordinator' : roleName.trim();

    Analytics.track(
      'app_open',
      userEmail: workerContact,
      properties: {'role': 'worker'},
    );

    authed = true;
    notifyListeners();
  }

  void logout() {
    // Clear all user data
    authed = false;
    role = UserRole.foreigner;
    plan = Plan.free;
    
    // Clear foreigner data
    firstName = '';
    lastName = '';
    contact = '';
    nationality = '';
    nationalityCode = 'US';
    savedEmail = '';
    
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

<<<<<<< HEAD
=======
  void updateOrder(AppOrder updatedOrder) {
    final index = orders.indexWhere((order) => order.id == updatedOrder.id);
    if (index == -1) {
      orders.insert(0, updatedOrder);
    } else {
      orders[index] = updatedOrder;
    }
    notifyListeners();
  }

>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
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
