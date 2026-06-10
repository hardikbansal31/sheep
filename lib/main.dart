import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  final repository = container.read(repositoryProvider);
  await repository.ensureInitialState();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SheepApp(),
    ),
  );
}
