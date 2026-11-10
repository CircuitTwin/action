# CircuitTwin tests (GitHub Action)

A composite action that runs CircuitTwin test suites on the CircuitTwin server and fails the job
when a case does not pass. It uploads the JUnit XML and the JSON report as a workflow artifact, writes
a job summary, and can keep one comment on the pull request.

It runs on Linux x86-64 runners (GitHub-hosted `ubuntu-*` or self-hosted). The steps use `sh`, `curl`,
`tar` and `sha256sum`; the pull request comment also uses `gh`, which GitHub-hosted runners include.

## Example

```yaml
name: CircuitTwin tests
on:
  push:
  pull_request:

permissions:
  contents: read
  pull-requests: write # only for comment-on-pr

jobs:
  circuittwin:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - name: Build firmware
        run: make firmware # writes build/firmware.elf

      - uses: circuittwin/action@v1 # or pin a full tag such as v1.0.0, or a commit
        with:
          suite: ct/suite.yaml
          token: ${{ secrets.CIRCUITTWIN_TOKEN }}
          comment-on-pr: 'true'
```

The defaults install the signed `ct` 0.1.0 Linux build (release `0.1.0-b138e57177ac`) from `https://circuittwindownloads.blob.core.windows.net/cli`, check its SHA-256 and verify its cosign signature against the CircuitTwin release key, so no download settings are needed. Set `ct-url` and `ct-sha256` (and `ct-version`) to pin another release, or `ct-path` to use a `ct` you installed yourself.

A copy-paste version that passes `actionlint` is in [`examples/github-workflow.yml`](examples/github-workflow.yml).
The example suite is [`examples/ct/suite.yaml`](examples/ct/suite.yaml).

CircuitTwin: [circuittwin.ai](https://circuittwin.ai) · Docs: [Test in CI](https://circuittwin.ai/docs/ci)

## Required secret

`CIRCUITTWIN_TOKEN`: a CircuitTwin access token (`ctk_...`). Create it in **Settings** of the
CircuitTwin organization whose boards the suite uses, with the scopes `runs` (firmware upload) and
`suites` (submit and read suites). Add it under the repository's Settings, Secrets and variables,
Actions. The action passes it to `ct` in the environment; it is never put on a command line or printed.
Secrets are not available to workflows triggered by pull requests from forks, so those runs cannot
sign in.

## Inputs

| Input | Required | Default | Meaning |
|---|---|---|---|
| `suite` | yes | | Suite file to run, or several files, one per line. Firmware paths in a suite are relative to the suite file. |
| `token` | yes | | CircuitTwin access token. Pass a secret. |
| `server` | no | `https://app.circuittwin.ai` | Server origin. HTTP is accepted only for a loopback address. |
| `ct-version` | no | | Version `ct --version` must report; any other version fails the job. |
| `ct-url` | one of `ct-url` / `ct-path` | | https URL of the pinned `ct` Linux x86-64 download (a `.tar.gz` holding `ct`, or the binary). |
| `ct-sha256` | with `ct-url` | | SHA-256 of that download. A different file is refused before it is extracted. |
| `ct-path` | one of `ct-url` / `ct-path` | | An already-installed `ct` to use instead of a download. |
| `cosign-public-key` | no | | Release public key (PEM text). When set, the download must also verify against its cosign bundle. |
| `ct-signature-url` | no | `ct-url` + `.sigstore.json` | Where the cosign bundle is. |
| `allow-insecure-http` | no | `false` | Permit an `http` `ct-url` (a mirror on a private network). The checksum still applies. |
| `timeout-seconds` | no | `1800` | Wait bound per suite. On timeout the suite's queued cases are cancelled and the job fails. |
| `comment-on-pr` | no | `false` | Post, then update, one summary comment on the pull request. Needs `pull-requests: write`. |
| `github-token` | no | `github.token` | Used only for that comment. |
| `results-dir` | no | `circuittwin-results` | Where results are written. |
| `upload-artifacts` | no | `true` | Upload the results directory. |
| `artifact-name` | no | `circuittwin-test-results` | Name of the artifact. |

## Outputs

| Output | Meaning |
|---|---|
| `result` | `passed`, `failed` (a case did not pass) or `error` (the suite could not run). |
| `exit-code` | `0` every case passed, `1` a case failed, errored or was inconclusive, `2` invalid suite or credentials, `3` service error or timeout. |
| `results-dir` | The results directory. |
| `suite-url` | Link to the last suite in the CircuitTwin app. |

## What it writes

For each suite `N` named `NAME`, `circuittwin-results/N-NAME/` holds `junit.xml`, `report.json`
(the `ct.suite-report/1` document), `summary.md` and `result.json` (what `ct` printed, including the
link to the app, which opens its Runs page). `circuittwin-results/summary.md` joins the summaries. The same table
goes to the job summary.

## Pinning `ct`

The action never runs a `ct` it has not checked. Give it the exact download and its SHA-256, and the
job fails if the bytes differ. If you also publish a cosign bundle next to the download, set
`cosign-public-key` and the action verifies it with cosign 3.1.3 (itself checked against a pinned
digest). There is no CircuitTwin-hosted Linux download yet; host the archive you build or are given, or
build `ct` in an earlier step and pass `ct-path`.
