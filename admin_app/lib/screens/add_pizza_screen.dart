import 'package:flutter/material.dart';

class AddPizzaScreen extends StatefulWidget {
  const AddPizzaScreen({super.key});

  @override
  State<AddPizzaScreen> createState() => _AddPizzaScreenState();
}

class _AddPizzaScreenState extends State<AddPizzaScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController descriptionController =
      TextEditingController();

  bool available = true;

  @override
  void dispose() {
    nameController.dispose();
    priceController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f5f5),

      appBar: AppBar(
        title: const Text("Add Pizza"),
        centerTitle: true,
        backgroundColor: Colors.amber,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Form(
          key: _formKey,

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Center(
                child: Stack(
                  children: [

                    CircleAvatar(
                      radius: 65,
                      backgroundColor: Colors.grey.shade300,
                      child: const Icon(
                        Icons.local_pizza,
                        size: 60,
                        color: Colors.grey,
                      ),
                    ),

                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        backgroundColor: Colors.amber,
                        child: IconButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Image Picker will be added later.",
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.camera_alt),
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Pizza Name",
                  prefixIcon: const Icon(Icons.local_pizza),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter pizza name";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Price",
                  prefixIcon: const Icon(Icons.attach_money),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter price";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: "Description",
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.description),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              SwitchListTile(
                value: available,
                activeColor: Colors.green,
                title: const Text("Available"),
                subtitle: const Text("Display this pizza to customers"),
                onChanged: (value) {
                  setState(() {
                    available = value;
                  });
                },
              ),

              const SizedBox(height: 35),

              SizedBox(
                width: double.infinity,
                height: 55,

                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {

                    if (_formKey.currentState!.validate()) {

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Pizza saved successfully! (Dummy Data)",
                          ),
                        ),
                      );

                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text(
                    "Save Pizza",
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}