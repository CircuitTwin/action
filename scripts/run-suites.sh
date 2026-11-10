#!/bin/sh
# Run CircuitTwin test suites with `ct cloud suite run` and collect the results.
#
# Environment:
#   CT_SUITES           Suite files, one per line (relative to the working directory).
#   CT_SERVER           Server origin, for example https://app.circuittwin.ai.
#   CT_TOKEN            CircuitTwin access token (ctk_...), never printed.
#   CT_TIMEOUT_SECONDS  Wait bound per suite (default 1800); queued cases are cancelled on timeout.
#   CT_RESULTS_DIR      Output directory (default circuittwin-results).
#   CT_SUMMARY_FILE     File the Markdown summary is appended to (a job summary). Optional.
#   CT_OUTPUT_FILE      File `name=value` outputs are appended to (GITHUB_OUTPUT). Optional.
#
# Writes <results>/<n>-<suite name>/{junit.xml,report.json,summary.md,result.json} per suite and
# <results>/summary.md for all. Exit code: 0 every case passed; 1 a case failed, errored or was
# inconclusive; 2 invalid suite, input or credentials; 3 the service could not run it. With
# several suites the highest code wins and every suite still runs.
set -eu
set -f

fail() {
  printf 'circuittwin: %s\n' "$*" >&2
  exit 2
}

[ -n "${CT_SERVER:-}" ] || fail "server is required"
[ -n "${CT_TOKEN:-}" ] || fail "token is required (store a CircuitTwin access token as a secret)"
command -v ct >/dev/null 2>&1 || fail "ct is not installed; run the install step first"
results="${CT_RESULTS_DIR:-circuittwin-results}"
timeout="${CT_TIMEOUT_SECONDS:-1800}"
case "$timeout" in
  '' | *[!0-9]*) fail "timeout must be a whole number of seconds" ;;
esac

suites=$(printf '%s\n' "${CT_SUITES:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true)
[ -n "$suites" ] || fail "no suite file given"

# ct reads the server and token from the environment; neither appears on a command line.
export CT_SERVER CT_TOKEN
mkdir -p "$results"
marker='<!-- circuittwin-ci-report -->'
printf '%s\n' "$marker" >"$results/summary.md"
overall=0
n=0
url=''
IFS='
'
for suite in $suites; do
  n=$((n + 1))
  name=$(basename "$suite" | sed -e 's/\.[^.]*$//' -e 's/[^A-Za-z0-9._-]/_/g')
  out="$results/$n-$name"
  mkdir -p "$out"
  printf 'circuittwin: running %s\n' "$suite"
  code=0
  ct cloud suite run "$suite" --wait --timeout "$timeout" \
    --junit "$out/junit.xml" --report "$out/report.json" --markdown "$out/summary.md" \
    >"$out/result.json" || code=$?
  cat "$out/result.json"
  case "$code" in
    0 | 1) ;;
    *)
      # The suite did not run to a report: say so in the summary.
      {
        printf '### CircuitTwin test suite: %s\n\nThe suite did not run (exit code %s).\n\n```json\n' "$suite" "$code"
        cat "$out/result.json"
        printf '\n```\n'
      } >"$out/summary.md"
      ;;
  esac
  sed -e '/circuittwin-ci-report/d' "$out/summary.md" >>"$results/summary.md"
  printf '\n' >>"$results/summary.md"
  found=$(sed -n 's/.*"url":"\([^"]*\)".*/\1/p' "$out/result.json" | head -n 1)
  if [ -n "$found" ]; then url="$found"; fi
  if [ "$code" -gt "$overall" ]; then overall="$code"; fi
done

case "$overall" in
  0) verdict=passed ;;
  1) verdict=failed ;;
  *) verdict=error ;;
esac
if [ -n "${CT_SUMMARY_FILE:-}" ]; then
  sed -e '/circuittwin-ci-report/d' "$results/summary.md" >>"$CT_SUMMARY_FILE"
fi
if [ -n "${CT_OUTPUT_FILE:-}" ]; then
  {
    printf 'exit-code=%s\n' "$overall"
    printf 'result=%s\n' "$verdict"
    printf 'results-dir=%s\n' "$results"
    printf 'suite-url=%s\n' "$url"
  } >>"$CT_OUTPUT_FILE"
fi
printf 'circuittwin: %s (exit code %s)\n' "$verdict" "$overall"
exit "$overall"
