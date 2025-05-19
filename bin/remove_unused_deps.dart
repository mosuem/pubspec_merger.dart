import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// A Dart script to remove unused dependencies from pubspec.yaml.
///
/// This script takes a top-level folder path as input, recursively scans
/// for all 'pubspec.yaml' files within that folder, and then for each
/// project found, it looks for 'package:' imports in its Dart files.
/// Unused dependencies are then removed from the respective 'pubspec.yaml' file.
///
/// If a 'dependencies' or 'dev_dependencies' section becomes completely empty
/// after removing unused packages, the entire key is removed from the pubspec.yaml.
///
/// Usage: dart run your_script_name.dart path_to_top_level_folder
void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('Usage: dart run pubspec_cleaner.dart <path_to_top_level_folder>');
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

/// Processes a single Dart/Flutter project by cleaning its pubspec.yaml.
/// This involves reading the pubspec, scanning Dart files for imports,
/// identifying unused dependencies, and removing them.
/// If a dependency section becomes empty, its key is removed.
Future<void> processSingleProject(File pubspecFile) async {
  final projectDir = pubspecFile.parent;

  // 1. Read and parse pubspec.yaml
  final pubspecContent = await pubspecFile.readAsString();
  final yamlEditor = YamlEditor(pubspecContent);
  final pubspecMap = loadYaml(pubspecContent) as YamlMap;

  // Extract current dependencies and dev_dependencies
  final currentDependencies = <String, Object>{};
  final currentDevDependencies = <String, Object>{};

  final dependenciesNode = pubspecMap['dependencies'] as YamlMap?;
  if (dependenciesNode != null) {
    dependenciesNode.forEach((key, value) {
      currentDependencies[key.toString()] = value;
    });
  }

  final devDependenciesNode = pubspecMap['dev_dependencies'] as YamlMap?;
  if (devDependenciesNode != null) {
    devDependenciesNode.forEach((key, value) {
      currentDevDependencies[key.toString()] = value;
    });
  }

  print(
    '  Found ${currentDependencies.length} regular dependencies and ${currentDevDependencies.length} dev dependencies.',
  );

  // 2. Scan Dart files in the current project directory for 'package:' imports
  final usedPackages = await findUsedPackages(projectDir);
  print(
    '  Found ${usedPackages.length} unique package imports in Dart files within this project.',
  );

  // 3. Identify unused dependencies
  final unusedDependencies = <String>[];
  final unusedDevDependencies = <String>[];

  currentDependencies.forEach((packageName, version) {
    // Exclude 'flutter' and 'sdk' related dependencies as they are core to Flutter projects.
    // 'sdk' is not a real package but a common placeholder in some pubspecs.
    if (!usedPackages.contains(packageName) && version is String) {
      unusedDependencies.add(packageName);
    }
  });

  currentDevDependencies.forEach((packageName, version) {
    if (!usedPackages.contains(packageName) && version is String) {
      unusedDevDependencies.add(packageName);
    }
  });

  if (unusedDependencies.isEmpty && unusedDevDependencies.isEmpty) {
    print(
      '  No unused dependencies found! This project\'s pubspec.yaml is clean.',
    );
    return;
  }

  print('  --- Unused Dependencies for ${projectDir.path} ---');
  if (unusedDependencies.isNotEmpty) {
    print('  Regular: ${unusedDependencies.join(', ')}');
  }
  if (unusedDevDependencies.isNotEmpty) {
    print('  Dev: ${unusedDevDependencies.join(', ')}');
  }
  print('  --------------------------------------------------');

  // 4. Modify pubspec.yaml to remove unused dependencies

  // Remove unused regular dependencies
  for (final dep in unusedDependencies) {
    yamlEditor.remove(['dependencies', dep]);
    print('  Removed unused regular dependency: $dep');
  }

  // Remove unused dev dependencies
  for (final dep in unusedDevDependencies) {
    yamlEditor.remove(['dev_dependencies', dep]);
    print('  Removed unused dev dependency: $dep');
  }

  // After removals, re-parse the current state of the YAML to check for empty sections
  final updatedPubspecMap = loadYaml(yamlEditor.toString()) as YamlMap;

  // If a section becomes empty, remove its key entirely
  final updatedDependenciesNode = updatedPubspecMap['dependencies'] as YamlMap?;
  if (updatedDependenciesNode != null && updatedDependenciesNode.isEmpty) {
    yamlEditor.remove(['dependencies']);
    print('  Removed empty "dependencies" section.');
  }

  final updatedDevDependenciesNode =
      updatedPubspecMap['dev_dependencies'] as YamlMap?;
  if (updatedDevDependenciesNode != null &&
      updatedDevDependenciesNode.isEmpty) {
    yamlEditor.remove(['dev_dependencies']);
    print('  Removed empty "dev_dependencies" section.');
  }

  // Write the modified content back to pubspec.yaml
  await pubspecFile.writeAsString(yamlEditor.toString());
  print(
    '  Successfully updated pubspec.yaml. Please run `flutter pub get` or `dart pub get` to apply changes.',
  );
}

/// Recursively finds all .dart files in the given directory
/// and extracts all unique 'package:' imports.
Future<Set<String>> findUsedPackages(Directory projectDir) async {
  final usedPackages = <String>{};
  final entities = projectDir.listSync(recursive: true, followLinks: false);

  for (final entity in entities) {
    if (entity is File && entity.path.endsWith('.dart')) {
      try {
        final fileContent = await entity.readAsString();
        // Regex to find import 'package:packageName/...'
        final packageImportRegex = RegExp(
          "import\\s+['|\"]package:([a-zA-Z0-9_]+)/",
        );
        final matches = packageImportRegex.allMatches(fileContent);

        for (final match in matches) {
          if (match.group(1) != null) {
            usedPackages.add(match.group(1)!);
          }
        }
      } catch (e) {
        print('Warning: Could not read file ${entity.path}: $e');
      }
    }
  }
  return usedPackages;
}
