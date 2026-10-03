import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings_model.dart';
import '../services/settings_service.dart';

/// Exposes [SettingsService.instance] as a Provider.
final settingsServiceProvider = Provider<SettingsService>(
  (_) => SettingsService.instance,
);

/// Reactive settings state. Update with [ref.read(settingsNotifierProvider.notifier).update(…)].
class SettingsNotifier extends Notifier<SettingsModel> {
  @override
  SettingsModel build() => ref.read(settingsServiceProvider).settings;

  Future<void> update(SettingsModel Function(SettingsModel) updater) async {
    final next = updater(state);
    state = next;
    await ref.read(settingsServiceProvider).save(next);
  }

  Future<void> reset() async {
    await ref.read(settingsServiceProvider).reset();
    state = const SettingsModel();
  }
}

final settingsNotifierProvider =
    NotifierProvider<SettingsNotifier, SettingsModel>(SettingsNotifier.new);
