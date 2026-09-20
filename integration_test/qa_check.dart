/// Tiny QA helper shared by the Phase 3 browser suites.
///
/// Each check that completes prints a console line with a fixed prefix so the
/// CDP runner (which captures browser console output) can score the run
/// without needing the flutter tool's result reporter.
int _qaPassCount = 0;

void qaPass(String name) {
  _qaPassCount++;
  // ignore: avoid_print
  print('QA-CHECK PASS #$_qaPassCount: $name');
}

/// Prints a failure marker (call before the failing expect so the CDP runner
/// can attribute the console exception to a named check).
void qaFail(String name) {
  // ignore: avoid_print
  print('QA-CHECK FAIL: $name');
}

String qaSummary() => 'QA-CHECK SUMMARY: $_qaPassCount passed';