import 'package:flutter/material.dart';
import 'add_pizza_screen.dart';
import 'edit_pizza_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pizzas = [
  {
    "name": "Hawaiian Pizza",
    "price": "₱399",
    "available": true,
    "image":
        "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=800",
  },
  {
    "name": "Pepperoni Pizza",
    "price": "₱459",
    "available": true,
    "image":
        "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=800&sat=-20",
  },
  {
    "name": "Cheese Pizza",
    "price": "₱329",
    "available": false,
    "image":
        "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=800",
  },
];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Menu Management"),
        backgroundColor: Colors.amber,
        centerTitle: true,
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.amber,
        onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AddPizzaScreen(),
    ),
  );
},
        child: const Icon(Icons.add),
      ),

      body: Padding(
        padding: const EdgeInsets.all(15),

        child: Column(
          children: [

            TextField(
              decoration: InputDecoration(
                hintText: "Search Pizza",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: pizzas.length,
                itemBuilder: (context, index) {

                  final pizza = pizzas[index];

                  return Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 15),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),

                    child: Padding(
                      padding: const EdgeInsets.all(15),

                      child: Row(

                        children: [

                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),

                            child: Image.network(
                              pizza["image"] as String,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                          ),

                          const SizedBox(width: 15),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,

                              children: [

                                Text(
                                  pizza["name"] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),

                                const SizedBox(height: 8),

                                Text(
                                  pizza["price"] as String,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 10),

                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),

                                  decoration: BoxDecoration(
                                    color: (pizza["available"] as bool)
                                        ? Colors.green
                                        : Colors.red,
                                    borderRadius:
                                        BorderRadius.circular(20),
                                  ),

                                  child: Text(
                                    (pizza["available"] as bool)
                                        ? "Available"
                                        : "Unavailable",
                                    style: const TextStyle(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Column(
                            children: [

                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                               onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => EditPizzaScreen(
        pizza: {
          ...pizza,
          "description":
              "Our delicious ${pizza["name"]}.",
        },
      ),
    ),
  );
},
                              ),

                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () {},
                              ),
                            ],
                          )
                        ],
                      ),
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