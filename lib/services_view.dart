import 'package:flutter/material.dart';

class ServicesView extends StatefulWidget {
  const ServicesView({super.key});

  @override
  State<ServicesView> createState() => _ServicesViewState();
}

class _ServicesViewState extends State<ServicesView> {
  int index = 0;

  final pages = [
    Center(child: Text("Home")),
    Center(child: Text("Services")),
    Center(child: Text("Visa")),
    Center(child: Text("Assistant")),
    Center(child: Text("Account")),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],

      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          setState(() => index = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Services'),
          NavigationDestination(icon: Icon(Icons.description), label: 'Visa'),
          NavigationDestination(icon: Icon(Icons.chat), label: 'Assistant'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}