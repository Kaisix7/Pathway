import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AirportView extends StatefulWidget {
  const AirportView({super.key});

  @override
  State<AirportView> createState() => _AirportViewState();
}

class _AirportViewState extends State<AirportView> {
  String selectedTariff = 'Econom';

  final Map<String, int> tariffs = {
    'Econom': 5000,
    'Business': 10000,
    'Premium': 20000,
  };

  List orders = [];

  Future<void> createOrder() async {
    final url = Uri.parse('http://127.0.0.1:8000/api/orders/');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "name": "Aidan",
        "tariff": selectedTariff,
        "price": tariffs[selectedTariff],
      }),
    );

    if (response.statusCode == 200) {
      print("Создано");
    } else {
      print("Ошибка: ${response.body}");
    }
  }

  Future<void> fetchOrders() async {
    final url = Uri.parse('http://127.0.0.1:8000/api/orders/');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      setState(() {
        orders = jsonDecode(response.body);
      });
    } else {
      print("Ошибка загрузки");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Airport Pickup")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButton<String>(
              value: selectedTariff,
              isExpanded: true,
              items: tariffs.keys.map((tariff) {
                return DropdownMenuItem(
                  value: tariff,
                  child: Text("$tariff - ${tariffs[tariff]}₸"),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedTariff = value!;
                });
              },
            ),

            const SizedBox(height: 20),

            Text(
              "Price: ${tariffs[selectedTariff]}₸",
              style: const TextStyle(fontSize: 20),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: createOrder,
              child: const Text("Order Airport"),
            ),

            ElevatedButton(
              onPressed: fetchOrders,
              child: const Text("Load Orders"),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return Card(
                    child: ListTile(
                      title: Text(order['tariff'].toString()),
                      subtitle:
                          Text("Price: ${order['price']}₸"),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}