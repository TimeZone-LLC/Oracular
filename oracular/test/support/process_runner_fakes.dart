import 'package:oracular/utils/process_runner.dart'
    show ProcessResult, ProcessRunner;

export 'package:oracular/utils/process_runner.dart' show ProcessResult;

class CapturedProcessCall {
  CapturedProcessCall({
    required this.executable,
    required List<String> arguments,
    this.workingDirectory,
    Map<String, String>? environment,
  }) : arguments = List<String>.unmodifiable(arguments),
       environment = environment == null
           ? null
           : Map<String, String>.unmodifiable(environment);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;

  List<String> get command => <String>[executable, ...arguments];
}

class CapturingProcessRunner extends ProcessRunner {
  CapturingProcessRunner(List<ProcessResult> results)
    : results = List<ProcessResult>.of(results),
      super(showVerbose: false);

  final List<ProcessResult> results;
  final List<CapturedProcessCall> calls = <CapturedProcessCall>[];
  final List<List<String>> invocations = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool inheritStdio = false,
  }) async {
    final CapturedProcessCall call = CapturedProcessCall(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    calls.add(call);
    invocations.add(call.command);
    if (results.isEmpty) {
      return failureResult('no scripted result');
    }
    return results.removeAt(0);
  }

  @override
  Future<ProcessResult?> runWithRetry(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? operationName,
    bool? interactive,
  }) async {
    return run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}

class ScriptedProcessRunner extends ProcessRunner {
  ScriptedProcessRunner({
    List<ProcessResult> results = const <ProcessResult>[],
    super.maxAutoRetries = 0,
    super.showVerbose = false,
    super.interactive = true,
    ProcessResult? defaultResult,
  }) : results = List<ProcessResult>.of(results),
       _defaultResult = defaultResult;

  final List<ProcessResult> results;
  final ProcessResult? _defaultResult;
  final List<CapturedProcessCall> calls = <CapturedProcessCall>[];
  int _cursor = 0;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool inheritStdio = false,
  }) async {
    calls.add(
      CapturedProcessCall(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      ),
    );
    if (_cursor >= results.length) {
      return _defaultResult ?? successResult();
    }
    return results[_cursor++];
  }

  @override
  Future<ProcessResult?> runWithRetry(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? operationName,
    bool? interactive,
  }) async {
    return run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}

ProcessResult successResult({String stdout = '', String stderr = ''}) {
  return ProcessResult(exitCode: 0, stdout: stdout, stderr: stderr);
}

ProcessResult failureResult(
  String stderr, {
  int exitCode = 1,
  String stdout = '',
}) {
  return ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr);
}

class ToolInventoryProcessRunner extends ProcessRunner {
  ToolInventoryProcessRunner({
    Map<String, String> versions = const <String, String>{},
    Set<String> missingCommands = const <String>{},
  }) : versions = Map<String, String>.unmodifiable(versions),
       missingCommands = Set<String>.unmodifiable(missingCommands),
       super(maxAutoRetries: 0, showVerbose: false, interactive: false);

  final Map<String, String> versions;
  final Set<String> missingCommands;
  final List<CapturedProcessCall> calls = <CapturedProcessCall>[];

  @override
  Future<bool> commandExists(
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(
      CapturedProcessCall(executable: 'which', arguments: <String>[command]),
    );
    return !missingCommands.contains(command);
  }

  @override
  Future<String?> getCommandVersion(
    String command, {
    List<String> versionArgs = const <String>['--version'],
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(CapturedProcessCall(executable: command, arguments: versionArgs));
    if (missingCommands.contains(command)) {
      return null;
    }
    return versions[command] ?? '$command 1.0.0';
  }
}
