import 'dart:io';

import 'package:args/args.dart';

void main(List<String> arguments) {
  exitCode = 0; // Default exit code for success

  final parser = ArgParser()
    ..addOption(
      'local',
      abbr: 'l',
      help: 'Path to the local pubspec.yaml file.',
    )
    ..addOption(
      'workspace',
      abbr: 'w',
      help: 'Path to the workspace pubspec.yaml file.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Display usage information.',
      negatable: false,
    );

  try {
    final argResults = parser.parse(arguments);

    if (argResults['help'] == true) {
      _printUsage(parser);
      return;
    }

    final localPubspecPath = argResults['local'];
    final workspacePubspecPath = argResults['workspace'];

    if (localPubspecPath == null || workspacePubspecPath == null) {
      throw ArgumentError('Both --local and --workspace options are required.');
    }

    processPubspecs(localPubspecPath, workspacePubspecPath);
  } catch (e) {
    print('Error: $e');
    exitCode = 1; // Set exit code for error.
  }
}

void processPubspecs(String localPubspecPath, String workspacePubspecPath) {
  final localFile = File(localPubspecPath);
  final workspaceFile = File(workspacePubspecPath);

  if (!localFile.existsSync()) {
    throw ArgumentError('Local pubspec file not found at $localPubspecPath');
  }
  if (!workspaceFile.existsSync()) {
    throw ArgumentError(
      'Workspace pubspec file not found at $workspacePubspecPath',
    );
  }

  String localContent = localFile.readAsStringSync();
  String workspaceContent = workspaceFile.readAsStringSync();

  // Add 'resolution: workspace' to the local pubspec after 'environment'
  const resolutionLine = '  resolution: workspace';
  if (localContent.contains('environment:')) {
    final environmentIndex = localContent.indexOf('environment:');
    final endOfEnvironment = localContent.indexOf('\n', environmentIndex);
    if (endOfEnvironment != -1) {
      localContent = localContent.replaceRange(
        endOfEnvironment + 1,
        endOfEnvironment + 1,
        '\n$resolutionLine',
      );
    } else {
      localContent += '\n$resolutionLine';
    }
    localFile.writeAsStringSync(localContent); //write local file.
  } else if (!localContent.contains(resolutionLine)) {
    //if no environment, add resolution at the end.
    localContent += '\n$resolutionLine';
    localFile.writeAsStringSync(localContent);
  }

  // Process dependencies, dev_dependencies, and dependency_overrides.
  workspaceContent = _processDependencies(
    localContent,
    workspaceContent,
    'dependencies',
  );
  workspaceContent = _processDependencies(
    localContent,
    workspaceContent,
    'dev_dependencies',
  );
  workspaceContent = _processDependencies(
    localContent,
    workspaceContent,
    'dependency_overrides',
  );

  // Write the updated workspace pubspec back to the file.
  workspaceFile.writeAsStringSync(workspaceContent);

  print(
    'Successfully merged dependencies from ${localFile.path} to ${workspaceFile.path}',
  );
}

String _processDependencies(
  String localContent,
  String workspaceContent,
  String dependencyType,
) {
  final localDependencies = _extractDependencies(localContent, dependencyType);
  if (localDependencies.isEmpty) {
    return workspaceContent; // No dependencies of this type in local pubspec.
  }

  String updatedWorkspaceContent = workspaceContent;
  final workspaceDependencies = _extractDependencies(
    workspaceContent,
    dependencyType,
  );

  for (final localDependency in localDependencies.entries) {
    final localName = localDependency.key;
    final localConstraint = localDependency.value;

    if (workspaceDependencies.containsKey(localName)) {
      final workspaceConstraint = workspaceDependencies[localName];
      if (workspaceConstraint != 'any') {
        if (workspaceConstraint != localConstraint) {
          throw ArgumentError(
            'Conflict: Dependency "$localName" has different constraints in local and workspace pubspecs: "$localConstraint" vs. "$workspaceConstraint".',
          );
        }
      }
      // If it exists, but the constraint is already 'any', we don't need to change anything.
    } else {
      // Add the dependency with the 'any' constraint to the workspace content, preserving formatting.

      final dependencyBlockStart = updatedWorkspaceContent.indexOf(
        '$dependencyType:',
      );
      if (dependencyBlockStart != -1) {
        var insertIndex = updatedWorkspaceContent.indexOf(
          '\n  ',
          dependencyBlockStart,
        );
        if (insertIndex == -1) {
          insertIndex =
              updatedWorkspaceContent.indexOf('\n', dependencyBlockStart) + 1;
        }

        if (insertIndex != -1) {
          final insertString = '  $localName: any\n';
          updatedWorkspaceContent = updatedWorkspaceContent.replaceRange(
            insertIndex,
            insertIndex,
            insertString,
          );
          print(
            'Added dependency "$localName" with constraint "any" to workspace $dependencyType.',
          );
        } else {
          final insertString = '\n  $localName: any\n';
          updatedWorkspaceContent = updatedWorkspaceContent.replaceRange(
            dependencyBlockStart + dependencyType.length + 1,
            dependencyBlockStart + dependencyType.length + 1,
            insertString,
          );
          print(
            'Added dependency "$localName" with constraint "any" to workspace $dependencyType.',
          );
        }
      } else {
        //If the whole block is missing
        final insertString = '\n$dependencyType:\n  $localName: any\n';
        updatedWorkspaceContent += insertString;
        print(
          'Added dependency "$localName" with constraint "any" to workspace $dependencyType.',
        );
      }
    }
  }
  return updatedWorkspaceContent;
}

// Extracts dependencies and their constraints from a pubspec.yaml string.
Map<String, String> _extractDependencies(
  String content,
  String dependencyType,
) {
  final dependencies = <String, String>{};
  final start = content.indexOf('$dependencyType:');
  if (start == -1) {
    return dependencies;
  }

  var currentIndex =
      start + dependencyType.length + 1; // Start after "dependencies:"
  while (true) {
    final nameStart = content.indexOf('  ', currentIndex);
    if (nameStart == -1 || content[nameStart + 1] == ' ') {
      break; // No more dependencies or end of block.
    }
    var nameEnd = content.indexOf(':', nameStart);
    if (nameEnd == -1) break;

    final name = content.substring(nameStart + 2, nameEnd).trim();
    currentIndex = nameEnd + 1;
    var constraintEnd = content.indexOf('\n', currentIndex);
    if (constraintEnd == -1) constraintEnd = content.length;
    final constraint = content.substring(currentIndex, constraintEnd).trim();
    if (name.isNotEmpty) {
      dependencies[name] = constraint.isNotEmpty ? constraint : 'any';
    }

    currentIndex = constraintEnd + 1;
    if (currentIndex >= content.length ||
        content.substring(currentIndex).trim().startsWith(RegExp(r'^\w'))) {
      break;
    }
  }
  return dependencies;
}

void _printUsage(ArgParser parser) {
  print('Usage: dart pubspec_merge.dart [options]');
  print(parser.usage);
}
