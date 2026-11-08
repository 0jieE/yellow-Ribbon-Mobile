import 'package:flutter/material.dart';

import '../models/menu_item.dart';
import '../widgets/menu_form.dart';

/// `PATCH /api/menu/{id}/`. Pops with `true` when the item was changed.
class EditPizzaScreen extends StatelessWidget {
  const EditPizzaScreen({super.key, required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) => MenuForm(existing: item);
}
