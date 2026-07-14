import '../../../models/core_emulator_model.dart';
import '../../../models/standalone_emulator_model.dart';

// Helper classes for grouped display
abstract class EmulatorListItem {}

class EmulatorHeaderItem extends EmulatorListItem {
  final String title;
  final bool isInstalled;
  final String? packageName;

  EmulatorHeaderItem({
    required this.title,
    this.isInstalled = false,
    this.packageName,
  });
}

class EmulatorCoreItem extends EmulatorListItem {
  final CoreEmulatorModel core;
  final bool retroArchConfigured;
  final String? retroArchPath;

  EmulatorCoreItem(
    this.core, {
    this.retroArchConfigured = false,
    this.retroArchPath,
  });
}

class EmulatorStandaloneItem extends EmulatorListItem {
  final StandaloneEmulatorModel standalone;
  final bool isInstalled;

  EmulatorStandaloneItem(this.standalone, {this.isInstalled = false});
}

class EmulatorGroupedCoreItem extends EmulatorListItem {
  final String groupName;
  final String? packageName;
  final List<CoreEmulatorModel> cores;
  final bool isInstalled;
  final bool retroArchConfigured;
  final String? retroArchPath;

  EmulatorGroupedCoreItem({
    required this.groupName,
    this.packageName,
    required this.cores,
    this.isInstalled = false,
    this.retroArchConfigured = false,
    this.retroArchPath,
  });
}
