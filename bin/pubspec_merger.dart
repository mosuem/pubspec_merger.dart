// ignore_for_file: always_specify_types

import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

void main(List<String> arguments) {
  exitCode = 0; // Default exit code for success

  final parser = ArgParser()
    ..addOption(
      'local',
      abbr: 'l',
      mandatory: true,
      help: 'Path to the local pubspec.yaml file.',
    )
    ..addOption(
      'workspace',
      abbr: 'w',
      mandatory: true,
      help: 'Path to the workspace pubspec.yaml file.',
    );

  try {
    final argResults = parser.parse(arguments);

    final localPubspecPath = argResults['local'];
    final workspacePubspecPath = argResults['workspace'];

    if (localPubspecPath == null || workspacePubspecPath == null) {
      throw ArgumentError('Both --local and --workspace options are required.');
    }

    processPubspecs(localPubspecPath, workspacePubspecPath);
  } catch (e) {
    if (e is ArgParserException) {
      print(e.message);
      print(parser.usage);
      exitCode = 64; // Exit code for invalid argument
    } else {
      print('An unexpected error occurred: $e');
      exitCode = 255; // Exit code for unhandled exception
    }
  }
}

void processPubspecs(String localPubspecPath, String workspacePubspecPath) {
  final localFile = File(localPubspecPath);
  final workspaceFile = File(workspacePubspecPath);

  if (!localFile.existsSync()) {
    print('Local pubspec.yaml file not found at $localPubspecPath');
    exitCode = 1;
    return;
  }
  if (!workspaceFile.existsSync()) {
    print('Workspace pubspec.yaml file not found at $workspacePubspecPath');
    exitCode = 1;
    return;
  }

  final localYamlContent = localFile.readAsStringSync();
  final workspaceYamlContent = workspaceFile.readAsStringSync();

  final localYaml = YamlEditor(localYamlContent);
  final workspaceYaml = YamlEditor(workspaceYamlContent);

  processDependencies(localYaml, workspaceYaml, 'dependencies');
  processDependencies(localYaml, workspaceYaml, 'dev_dependencies');
  processDependencies(localYaml, workspaceYaml, 'dependency_overrides');

  // Write the updated workspace file
  localFile.writeAsStringSync(localYaml.toString());
  workspaceFile.writeAsStringSync(workspaceYaml.toString());
  writeResolution(localFile);
  print('Workspace pubspec.yaml file updated successfully.');
}

void writeResolution(File localFile) {
  final List<String> localLines = localFile.readAsLinesSync();
  // Add 'resolution: workspace' to the local pubspec after 'environment'
  const resolutionLine = 'resolution: workspace\n';
  if (!localLines.any((line) => line.startsWith('resolution: workspace'))) {
    bool environmentFound = false;
    int insertIndex = -1;
    for (int i = 0; i < localLines.length; i++) {
      if (localLines[i].startsWith('environment:')) {
        environmentFound = true;
        insertIndex = i + 3; // Insert after the environment line
        break;
      }
    }

    if (environmentFound) {
      if (insertIndex != -1) {
        localLines.insert(insertIndex, resolutionLine);
      }
    }
    localFile.writeAsStringSync('${localLines.join('\n')}\n');
  }
}

void processDependencies(
  YamlEditor localYaml,
  YamlEditor workspaceYaml,
  String dependencyType,
) {
  final localDependenciesPath = [dependencyType];
  final workspaceDependenciesPath = [dependencyType];

  final localDependencies = localYaml.parseOrNull(localDependenciesPath);
  if (localDependencies == null) {
    // It's not an error if the section doesn't exist in the local file.
    return;
  }

  var workspaceDependencies = workspaceYaml.parseOrNull(
    workspaceDependenciesPath,
  );
  if (workspaceDependencies == null) {
    workspaceYaml.update(workspaceDependenciesPath, <String, Object>{});
  }
  workspaceDependencies = workspaceYaml.parseAt(workspaceDependenciesPath);

  if (localDependencies is! Map) {
    throw ArgumentError(
      'Error: $dependencyType in local pubspec is not a map.',
    );
  }
  if (workspaceDependencies is! Map) {
    throw ArgumentError(
      'Error: $dependencyType in workspace pubspec is not a map: $workspaceDependencies',
    );
  }

  (localDependencies as Map).map((key, value) => MapEntry(key, value)).forEach((
    packageName,
    localConstraint,
  ) {
    final packagePath = [dependencyType, packageName as String];
    final workspaceConstraint = workspaceYaml.parseOrNull(packagePath)?.value;
    if (workspaceConstraint != null) {
      if (localConstraint != workspaceConstraint) {
        throw Exception(
          'Conflict: $dependencyType "$packageName" has different constraints in local and workspace pubspec.yaml: local $localConstraint vs workspace $workspaceConstraint',
        );
      }
    } else {
      workspaceYaml.update(packagePath, localConstraint);
      print(
        'Added $dependencyType "$packageName": "$localConstraint" to workspace pubspec.yaml.',
      );
    }
    localYaml.update(packagePath, 'any');
  });
}

extension on YamlEditor {
  YamlNode? parseOrNull(List<String> path) {
    final YamlNode parsed = parseAt(path, orElse: () => wrapAsYamlNode(null));
    return parsed.value != null ? parsed : null;
  }
}
