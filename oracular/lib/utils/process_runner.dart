import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';

import 'package:fast_log/fast_log.dart';

import 'user_prompt.dart';

/// Result of a process execution
class ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool success;

  ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  }) : success = exitCode == 0;

  @override
  String toString() =>
      'ProcessResult(exitCode: $exitCode, success: $success, stdout: ${stdout.length} chars, stderr: ${stderr.length} chars)';
}

// RetryChoice is now defined in user_prompt.dart

/// Exception thrown when user chooses to abort
class AbortException implements Exception {
  final String message;
  AbortException([this.message = 'Operation aborted by user']);

  @override
  String toString() => message;
}

/// Execute shell commands with retry logic
class ProcessRunner {
  /// Maximum automatic retries before prompting user
  final int maxAutoRetries;

  /// Whether to show verbose output
  final bool showVerbose;

  /// Whether `runWithRetry` is allowed to prompt the user when automatic
  /// retries are exhausted. Set to `false` when running inside a spinner or
  /// other non-interactive UI so we never block waiting for stdin.
  final bool interactive;

  ProcessRunner({
    this.maxAutoRetries = 2,
    this.showVerbose = false,
    this.interactive = true,
  });

  /// Run a command and return the result
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool inheritStdio = false,
  }) async {
    if (showVerbose) {
      verbose('Running: $executable ${arguments.join(' ')}');
      if (workingDirectory != null) {
        verbose('  in: $workingDirectory');
      }
    }

    final io.ProcessResult result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: Platform.isWindows,
    );

    return ProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  /// Run a command with automatic retry on failure
  /// Returns null if user chooses to skip
  /// Throws AbortException if user chooses to abort
  Future<ProcessResult?> runWithRetry(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? operationName,
    bool? interactive,
  }) async {
    final bool effectiveInteractive = interactive ?? this.interactive;
    final String opName = operationName ?? '$executable ${arguments.join(' ')}';
    int attempt = 0;

    while (true) {
      attempt++;
      final ProcessResult result = await run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );

      if (result.success) {
        return result;
      }

      // Failed - check if we should auto-retry
      if (attempt <= maxAutoRetries) {
        warn('$opName failed (attempt $attempt/$maxAutoRetries), retrying...');
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }

      // Auto-retries exhausted - ask user (only if interactive)
      if (!effectiveInteractive) {
        error('$opName failed after $maxAutoRetries attempts');
        if (result.stderr.isNotEmpty) {
          error('stderr: ${result.stderr.trim()}');
        }
        return null;
      }

      error('$opName failed after $maxAutoRetries attempts');
      if (result.stderr.isNotEmpty) {
        error('Error output:');
        print(result.stderr);
      }

      final RetryChoice choice = await UserPrompt.askRetryChoice(opName);
      switch (choice) {
        case RetryChoice.retry:
          attempt = 0; // Reset retry counter
          continue;
        case RetryChoice.skip:
          return null;
        case RetryChoice.abort:
          throw AbortException();
      }
    }
  }

  /// Run a command and stream output in real-time
  Future<int> runStreaming(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (showVerbose) {
      verbose('Running (streaming): $executable ${arguments.join(' ')}');
    }

    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: Platform.isWindows,
    );

    // Stream stdout and stderr
    process.stdout.listen((List<int> data) => stdout.add(data));
    process.stderr.listen((List<int> data) => stderr.add(data));

    return await process.exitCode;
  }

  /// Run a command but give up after [timeout], killing the process.
  ///
  /// Used for tool probes (`which`, `--version`) where a wedged external
  /// CLI must never hang the whole wizard — a hung `flutterfire --version`
  /// would otherwise block `oracular check tools` forever.
  Future<ProcessResult> runBounded(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final Process process = await Process.start(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );

    // Collect output via explicit subscriptions so they can be cancelled on
    // timeout. If the probed tool spawns a grandchild (e.g. the flutterfire
    // wrapper script starting a Dart VM), killing the direct child leaves
    // the grandchild holding the pipe write ends — an uncancelled stream
    // subscription on those pipes would keep THIS VM alive forever.
    final StringBuffer stdoutBuffer = StringBuffer();
    final StringBuffer stderrBuffer = StringBuffer();
    final StreamSubscription<String> stdoutSub =
        process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);
    final StreamSubscription<String> stderrSub =
        process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);

    try {
      final int exitCode = await process.exitCode.timeout(timeout);
      // Give the pipes a moment to flush any buffered output, but never
      // wait on a grandchild that kept them open.
      await Future.wait(<Future<void>>[
        stdoutSub.asFuture<void>(),
        stderrSub.asFuture<void>(),
      ]).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
      return ProcessResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return ProcessResult(
        exitCode: -1,
        stdout: stdoutBuffer.toString(),
        stderr:
            '$executable ${arguments.join(' ')} timed out after '
            '${timeout.inSeconds}s',
      );
    } finally {
      await stdoutSub.cancel();
      await stderrSub.cancel();
    }
  }

  /// Check if a command exists on the system
  Future<bool> commandExists(
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final ProcessResult result = await runBounded(
        Platform.isWindows ? 'where' : 'which',
        <String>[command],
        timeout: timeout,
      );
      return result.success;
    } catch (e) {
      return false;
    }
  }

  /// Get the version of a command
  Future<String?> getCommandVersion(
    String command, {
    List<String> versionArgs = const <String>['--version'],
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final ProcessResult result = await runBounded(
        command,
        versionArgs,
        timeout: timeout,
      );
      if (result.success) {
        return result.stdout.trim().split('\n').first;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

/// Global process runner instance
final processRunner = ProcessRunner();
