import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// A Dart script to convert all dependencies with specific versions to 'any'.
///
/// This script takes a top-level folder path as input, recursively scans
/// for all 'pubspec.yaml' files within that folder. For each project found,
/// it identifies dependencies and dev_dependencies that have a version
/// explicitly defined (not 'any') and changes their version to 'any'.
///
/// Usage: dart run any_deps_converter.dart path_to_top_level_folder
void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('Usage: dart run any_deps_converter.dart <path_to_top_level_folder>');
    exit(1);
  }

  final topLevelPath = arguments[0];
  final topLevelDir = Directory(topLevelPath);

  if (!await topLevelDir.exists()) {
    print('Error: Top-level folder not found at "$topLevelPath"');
    exit(1);
  }

  print('Scanning for pubspec.yaml files in: ${topLevelDir.path}');

  final pubspecFiles = <File>[];
  // Recursively find all pubspec.yaml files
  await for (final FileSystemEntity entity in topLevelDir.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('pubspec.yaml')) {
      pubspecFiles.add(entity);
    }
  }

  if (pubspecFiles.isEmpty) {
    print('No pubspec.yaml files found in "$topLevelPath".');
    return;
  }

  print('Found ${pubspecFiles.length} pubspec.yaml files.');

  for (final pubspecFile in pubspecFiles) {
    print('\n--- Processing project: ${pubspecFile.parent.path} ---');
    await processSingleProject(pubspecFile);
    print('--- Finished processing: ${pubspecFile.parent.path} ---\n');
  }

  print('All specified projects processed.');
}

/// Processes a single Dart/Flutter project by converting specific dependency
/// versions to 'any' in both 'dependencies' and 'dev_dependencies'.
Future<void> processSingleProject(File pubspecFile) async {
  // 1. Read and parse pubspec.yaml
  final pubspecContent = await pubspecFile.readAsString();
  final yamlEditor = YamlEditor(pubspecContent);
  final pubspecMap = loadYaml(pubspecContent) as YamlMap;

  var hasChanges = false; // Flag to track if any modifications were made

  // Process regular dependencies
  final dependenciesNode = pubspecMap['dependencies'] as YamlMap?;
  if (dependenciesNode != null) {
    for (final entry in dependenciesNode.entries) {
      final packageName = entry.key.toString();
      if (entry.value is String) {
        final version = entry.value.toString().trim().toLowerCase();

        if (version != 'any') {
          yamlEditor.update(['dependencies', packageName], 'any');
          print('  Changed $packageName version to "any" in dependencies.');
          hasChanges = true;
        }
      }
    }
  }

  // Process dev dependencies
  final devDependenciesNode = pubspecMap['dev_dependencies'] as YamlMap?;
  if (devDependenciesNode != null) {
    for (final entry in devDependenciesNode.entries) {
      final packageName = entry.key.toString();
      if (entry.value is String) {
        final version = entry.value.toString().trim().toLowerCase();

        if (version != 'any') {
          yamlEditor.update(['dev_dependencies', packageName], 'any');
          print('  Changed $packageName version to "any" in dev_dependencies.');
          hasChanges = true;
        }
      }
    }
  }

  if (!hasChanges) {
    print(
      '  No specific dependency versions found to convert to "any" in this project.',
    );
    return;
  }

  // Create a backup of the original pubspec.yaml if changes were made
  // Write the modified content back to pubspec.yaml
  await pubspecFile.writeAsString(yamlEditor.toString());
  print(
    '  Successfully updated pubspec.yaml. Please run `flutter pub get` or `dart pub get` to apply changes.',
  );
}
