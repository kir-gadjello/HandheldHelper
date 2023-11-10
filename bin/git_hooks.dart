import 'package:git_hooks/git_hooks.dart';
import "dart:io";

void main(List<String> arguments) {
  Map<Git, UserBackFun> params = {Git.preCommit: preCommit};
  GitHooks.call(arguments, params);
}

Future<bool> preCommit() async {
  ProcessResult result = await Process.run('git', ['rev-parse', 'HEAD']);
  String commitHash = result.stdout.trim();

  File('lib/commit_hash.dart')
      .writeAsStringSync('const String APP_COMMIT_HASH = \'$commitHash\';');

  return true;
}
