#!/bin/sh
# Create or update one comment per pull request with the suite summary.
#
# Environment: GH_TOKEN (the workflow's GITHUB_TOKEN), GITHUB_REPOSITORY, PR_NUMBER,
# SUMMARY_FILE (Markdown starting with the circuittwin-ci-report marker).
# A failure here never changes the test verdict: it is reported as a warning.
set -eu

marker='circuittwin-ci-report'
warn() {
  printf '::warning::CircuitTwin: %s\n' "$*"
  exit 0
}

[ -n "${PR_NUMBER:-}" ] || warn "this event is not a pull request; no comment was posted"
[ -s "${SUMMARY_FILE:-}" ] || warn "there is no summary to post"
command -v gh >/dev/null 2>&1 || warn "the GitHub CLI (gh) is not installed; no comment was posted"
api="repos/$GITHUB_REPOSITORY/issues"
existing=$(gh api --paginate "$api/$PR_NUMBER/comments" \
  --jq ".[] | select(.user.type == \"Bot\" and (.body | contains(\"$marker\"))) | .id" 2>/dev/null | head -n 1) \
  || warn "could not list the pull request comments (does the job have pull-requests: write?)"
if [ -n "$existing" ]; then
  gh api --method PATCH "$api/comments/$existing" -F "body=@$SUMMARY_FILE" >/dev/null \
    || warn "could not update the comment (does the job have pull-requests: write?)"
else
  gh api --method POST "$api/$PR_NUMBER/comments" -F "body=@$SUMMARY_FILE" >/dev/null \
    || warn "could not post the comment (does the job have pull-requests: write? Pull requests from forks cannot)"
fi
printf 'circuittwin: pull request comment updated\n'
