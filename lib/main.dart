import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http; 
import 'dart:convert';

/**
 * PROJECT: Meat Track Pro
 * DESCRIPTION: A real-time inventory and sales tracking system integrated with Google Sheets.
 * AUTHOR: H G M Karunarathna
 */

void main() {
  runApp(
    // State Management initialization using Provider
    ChangeNotifierProvider(
      create: (context) => InventoryProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.indigo,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        ),
        home: MainDashboard(),
      ),
    ),
  );
}

// --- 1. CORE LOGIC & DATA SYNCHRONIZATION ---
class InventoryProvider with ChangeNotifier {
  // Google Apps Script Web App URL - The bridge between App and Google Sheets
  final String scriptUrl = "https://script.google.com/macros/s/AKfycbwu4zkF5H0m2LqiMA0CboE4QJt2L4dKOfRqd8UCeXSyYt0DBdzjrh12KMRLkx7WLIO7ew/exec";

  // In-memory data storage for fast UI updates
  List<Map<String, dynamic>> loads = [];
  List<Map<String, dynamic>> sales = [];
  List<Map<String, dynamic>> inventoryItems = []; 
  List<String> shops = []; 

  /**
   * Syncs data to Google Sheets via HTTP POST.
   * This allows the business owner to see live updates on a spreadsheet.
   */
  Future<void> syncWithSheet(String sheetName, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse("$scriptUrl?sheet=$sheetName"),
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        print("Cloud Sync Successful: Data sent to $sheetName ✅");
      }
    } catch (e) {
      print("Cloud Sync Failed: $e");
    }
  }

  // Adding new product to the local master list
  void addNewItem(String name, double price) {
    inventoryItems.add({"name": name, "price": price});
    notifyListeners();
  }

  // Adding new retail partner (Shop)
  void addNewShop(String name) {
    shops.add(name);
    notifyListeners();
  }

  /**
   * Records stock being loaded into the delivery vehicle.
   * Triggers a cloud sync to the 'Loading' sheet.
   */
  void addLoading(String item, int qty) {
    var now = DateTime.now();
    loads.add({'item': item, 'qty': qty, 'date': now});
    
    syncWithSheet("Loading", {
      "id": "L-${now.millisecondsSinceEpoch}",
      "date": now.toString(),
      "itemName": item,
      "qty": qty,
      "unitPrice": 0,
      "total": 0
    });
    
    notifyListeners();
  }

  /**
   * Processes a sale at a retail outlet.
   * Calculates totals and triggers a cloud sync to the 'Sales' sheet.
   */
  void addSale(String shop, String item, int qty, double price) {
    var now = DateTime.now();
    double total = (qty * price).toDouble();
    sales.add({
      'shop': shop, 'item': item, 'qty': qty, 
      'unitPrice': price, 'total': total, 'date': now
    });

    syncWithSheet("Sales", {
      "id": "INV-${now.millisecondsSinceEpoch}",
      "date": now.toString(),
      "shopName": shop,
      "itemName": item,
      "qty": qty,
      "unitPrice": price,
      "total": total
    });

    notifyListeners();
  }

  /**
   * Business Logic: Calculates remaining stock in the lorry
   * Formula: Total Loaded - Total Sold
   */
  int getRemaining(String itemName) {
    int totalLoad = loads.where((l) => l['item'] == itemName).fold(0, (sum, i) => sum + (i['qty'] as int));
    int totalSale = sales.where((s) => s['item'] == itemName).fold(0, (sum, i) => sum + (i['qty'] as int));
    return totalLoad - totalSale;
  }

  // Calculates the monetary value of current stock
  double getTotalStockValue() {
    double total = 0;
    for (var item in inventoryItems) {
      int remaining = getRemaining(item['name']);
      double price = (item['price'] as num).toDouble();
      total += (remaining * price);
    }
    return total;
  }
}

// --- 2. MAIN DASHBOARD (USER INTERFACE) ---
class MainDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color.fromRGBO(44, 62, 80, 1),
          title: const Text("Meat Track", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blueAccent,
            tabs: [
              Tab(icon: Icon(Icons.local_shipping), text: "Load"),
              Tab(icon: Icon(Icons.storefront), text: "Sales"),
              Tab(icon: Icon(Icons.assessment), text: "Stock"),
              Tab(icon: Icon(Icons.settings), text: "Settings"),
            ],
          ),
        ),
        body: TabBarView(children: [LoadingPage(), SalesPage(), StockSummaryPage(), SettingsPage()]),
      ),
    );
  }
}

// --- 3. SALES TRACKING INTERFACE ---
class SalesPage extends StatefulWidget {
  @override
  _SalesPageState createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  String? selectedShop;
  Map<String, dynamic>? selectedItemData;
  final qtyController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    var prov = Provider.of<InventoryProvider>(context);
    var currentBillItems = selectedShop != null 
        ? prov.sales.where((s) => s['shop'] == selectedShop).toList() 
        : [];
    double grandTotal = currentBillItems.fold(0.0, (sum, item) => sum + (item['total'] as num).toDouble());

    return Column(children: [
      // Sales Entry Form
      Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
        child: Column(children: [
          prov.shops.isEmpty 
          ? const Text("Please add a shop in Settings first!", style: TextStyle(color: Colors.red))
          : DropdownButtonFormField<String>(
            hint: const Text("Select Shop"),
            value: selectedShop,
            items: prov.shops.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (val) => setState(() => selectedShop = val),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.store), border: InputBorder.none),
          ),
          const Divider(),
          Row(children: [
            Expanded(flex: 2, child: DropdownButtonFormField<Map<String, dynamic>>(
              hint: const Text("Item"),
              value: selectedItemData,
              items: prov.inventoryItems.map((item) => DropdownMenuItem(value: item, child: Text(item['name']))).toList(),
              onChanged: (val) => setState(() => selectedItemData = val),
              decoration: const InputDecoration(border: InputBorder.none),
            )),
            Expanded(child: TextField(controller: qtyController, decoration: const InputDecoration(hintText: "Qty", border: InputBorder.none), keyboardType: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              // Input Validation & Stock Check
              if(selectedShop != null && selectedItemData != null && qtyController.text.isNotEmpty) {
                int qty = int.parse(qtyController.text);
                double price = (selectedItemData!['price'] as num).toDouble();
                if (qty <= prov.getRemaining(selectedItemData!['name'])) {
                  prov.addSale(selectedShop!, selectedItemData!['name'], qty, price);
                  setState(() {
                    selectedItemData = null;
                    qtyController.clear();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added & Synced! ✅"), backgroundColor: Colors.green));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Insufficient Stock!"), backgroundColor: Colors.red));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F51B5), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
            child: const Text("ADD TO BILL"),
          )
        ]),
      ),
      // List of current transactions
      Expanded(child: ListView.builder(
        itemCount: currentBillItems.length,
        itemBuilder: (context, index) {
          var item = currentBillItems[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              title: Text(item['item'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Qty: ${item['qty']} x ${item['unitPrice']}"),
              trailing: Text("Rs. ${item['total'].toStringAsFixed(2)}"),
            ),
          );
        },
      )),
      // Real-time Bill Total
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(color: Color(0xFF1C2833)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("GRAND TOTAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text("Rs. ${grandTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      )
    ]);
  }
}

// --- 4. STOCK SUMMARY (INVENTORY MONITORING) ---
class StockSummaryPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var prov = Provider.of<InventoryProvider>(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12), 
            children: prov.inventoryItems.map((item) {
              int stock = prov.getRemaining(item['name']);
              double price = (item['price'] as num).toDouble();
              double itemTotalValue = stock * price;
              return Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.inventory_2, color: Colors.indigo),
                  title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Price: Rs. ${price.toStringAsFixed(0)}"),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("$stock Left", style: TextStyle(fontWeight: FontWeight.bold, color: stock < 5 ? Colors.red : Colors.green)),
                      Text("Val: Rs. ${itemTotalValue.toStringAsFixed(0)}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Total value of remaining inventory
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(color: Color(0xFF2E4053)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL STOCK VALUE", style: TextStyle(color: Colors.white)),
              Text("Rs. ${prov.getTotalStockValue().toStringAsFixed(2)}", 
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        )
      ],
    );
  }
}

// --- 5. LOADING MODULE (STOCK INPUT) ---
class LoadingPage extends StatefulWidget { @override _LoadingPageState createState() => _LoadingPageState(); }
class _LoadingPageState extends State<LoadingPage> {
  String? sel; 
  final con = TextEditingController();
  @override Widget build(BuildContext context) {
    var prov = Provider.of<InventoryProvider>(context);
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      DropdownButtonFormField<String>(
        hint: const Text("Select Item to Load"), 
        value: sel,
        items: prov.inventoryItems.map((e) => DropdownMenuItem(value: e['name'] as String, child: Text(e['name']))).toList(), 
        onChanged: (v) => setState(() => sel = v), 
        decoration: const InputDecoration(border: OutlineInputBorder())),
      const SizedBox(height: 15),
      TextField(controller: con, decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()), keyboardType: TextInputType.number),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: (){ 
          if(sel != null && con.text.isNotEmpty) { 
            prov.addLoading(sel!, int.parse(con.text)); 
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Loaded to Lorry & Synced! ✅"), backgroundColor: Colors.indigo));
            setState(() {
              sel = null;
              con.clear();
            });
          } 
        }, 
        child: const Text("CONFIRM LOAD TO LORRY")
      )
    ]));
  }
}

// --- 6. SYSTEM SETTINGS (CONFIGURATION) ---
class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final itemCon = TextEditingController();
  final priceCon = TextEditingController();
  final shopCon = TextEditingController();

  @override
  Widget build(BuildContext context) {
    var prov = Provider.of<InventoryProvider>(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Product Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(controller: itemCon, decoration: const InputDecoration(labelText: "Product Name", border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: priceCon, decoration: const InputDecoration(labelText: "Unit Price (Rs.)", border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: () {
            if(itemCon.text.isNotEmpty && priceCon.text.isNotEmpty) {
              prov.addNewItem(itemCon.text, double.parse(priceCon.text));
              itemCon.clear(); priceCon.clear();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New Product Added Successfully!")));
            }
          }, child: const Text("Add Product")),
          const Divider(height: 40),
          const Text("Retail Partner Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(controller: shopCon, decoration: const InputDecoration(labelText: "Shop Name", border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: () {
            if(shopCon.text.isNotEmpty) {
              prov.addNewShop(shopCon.text);
              shopCon.clear();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New Retail Shop Registered!")));
            }
          }, child: const Text("Add Shop")),
        ]),
      ),
    );
  }
}