import 'package:flutter/material.dart';

class EditPizzaScreen extends StatefulWidget {
  final Map<String, dynamic> pizza;

  const EditPizzaScreen({
    super.key,
    required this.pizza,
  });

  @override
  State<EditPizzaScreen> createState() => _EditPizzaScreenState();
}

class _EditPizzaScreenState extends State<EditPizzaScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController nameController;
  late TextEditingController priceController;
  late TextEditingController descriptionController;

  late bool available;

  @override
  void initState() {
    super.initState();

    nameController =
        TextEditingController(text: widget.pizza["name"]);

    priceController =
        TextEditingController(text: widget.pizza["price"]);

    descriptionController =
        TextEditingController(
      text: widget.pizza["description"] ?? "",
    );

    available = widget.pizza["available"];
  }

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
        title: const Text("Edit Pizza"),
        backgroundColor: Colors.amber,
        centerTitle: true,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Form(
          key: _formKey,

          child: Column(
            children: [

              Stack(
                alignment: Alignment.bottomRight,

                children: [

                  CircleAvatar(
                    radius: 65,
                    backgroundImage:
                        NetworkImage(widget.pizza["image"]),
                  ),

                  FloatingActionButton.small(
                    backgroundColor: Colors.amber,
                    onPressed: () {

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Image replacement will be added later.",
                          ),
                        ),
                      );

                    },
                    child: const Icon(Icons.camera_alt),
                  )
                ],
              ),

              const SizedBox(height: 30),

              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Pizza Name",
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                ),
                validator: (value) =>
                    value!.isEmpty ? "Required" : null,
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Price",
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                ),
                validator: (value) =>
                    value!.isEmpty ? "Required" : null,
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: "Description",
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SwitchListTile(
                value: available,
                title: const Text("Available"),
                activeColor: Colors.green,
                onChanged: (value) {

                  setState(() {
                    available = value;
                  });

                },
              ),

              const SizedBox(height: 30),

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

                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Pizza updated successfully!",
                          ),
                        ),
                      );

                      Navigator.pop(context);
                    }

                  },
                  icon: const Icon(Icons.save),
                  label: const Text(
                    "Update Pizza",
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}