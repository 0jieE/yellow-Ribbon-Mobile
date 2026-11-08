import 'package:flutter/material.dart';

import '../widgets/menu_form.dart';

/// `POST /api/menu/`. Pops with `true` when an item was created.
class AddPizzaScreen extends StatelessWidget {
  const AddPizzaScreen({super.key});

  @override
  Widget build(BuildContext context) => const MenuForm();
}
