# bats file_tags=worker
load helpers/setup

# Runs for whichever harness $DUX_WORKER_HARNESS names. The Makefile runs it twice.
setup() {
  DUX_HOME="$(cd "$(mktemp -d "${BATS_TMPDIR:-/tmp}/dux-home.XXXXXX")" && pwd -P)"; export DUX_HOME
  mkdir -p "$DUX_HOME/data" "$DUX_HOME/state" "$DUX_HOME/config"
  export PATH="$DUX_ROOT/tests/fakes:$DUX_ROOT/bin:$PATH"
  export FAKE_WORKER_LOG="$DUX_HOME/state/fake-worker.log"; : > "$FAKE_WORKER_LOG"
  export DUX_STATUS_LOG="$DUX_HOME/state/status.log"; : > "$DUX_STATUS_LOG"
  export FAKE_WORKER_SCRIPT="$DUX_HOME/state/script"
  printf 'the brief\n' > "$DUX_HOME/brief.md"
  echo '{"permissions":{"deny":[]}}' > "$DUX_HOME/settings.json"
  # The launcher is written into a task channel and reads its outboxes from it,
  # so the tests build one the way dux-worker-wrap does.
  chan="$DUX_HOME/state/channels/t1.RUN"; mkdir -p "$chan"
  : > "$chan/status.outbox"; : > "$chan/report.outbox"
}

mode_of() {  # $1 path; the permission bits on GNU and BSD stat
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null
}

adapter() {  # $@ function and args; runs inside a shell that sourced dux-env and the adapter
  bash -c 'source "$DUX_ROOT/bin/dux-env"; source "$DUX_ROOT/bin/workers/$DUX_WORKER_HARNESS.sh"; "$@"' _ "$@"
}

@test "worker_cmd prints one line naming the harness, model, effort, and brief" {
  [ -n "${DUX_WORKER_HARNESS:-}" ] || skip "DUX_WORKER_HARNESS unset"
  run adapter worker_cmd "$DUX_HOME/brief.md" model-x high "$DUX_HOME/settings.json"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "$DUX_WORKER_HARNESS "* ]]
  [[ "$output" == *"model-x"* ]] && [[ "$output" == *"high"* ]] && [[ "$output" == *"$DUX_HOME/brief.md"* ]]
  case "$DUX_WORKER_HARNESS" in
    claude) [[ "$output" == *"--dangerously-skip-permissions"* ]] && [[ "$output" == *"--settings $DUX_HOME/settings.json"* ]]
            # An ordinary session, not a print run: the brief is its opening prompt.
            [[ "$output" != *"--output-format"* ]] || { echo "print mode survives: $output"; return 1; }
            [[ "$output" != *"--verbose"* ]] || { echo "verbose survives: $output"; return 1; }
            [[ "$output" != *"claude -p"* ]] || { echo "-p survives: $output"; return 1; } ;;
    codex)  [[ "$output" == *"--sandbox danger-full-access"* ]] && [[ "$output" == *"shell_environment_policy.ignore_default_excludes=true"* ]] ;;
  esac
}

# A worker needs six tools: Bash, Read, Glob, Grep, Write and Edit. Everything
# else the harness offers is prompt a Dux worker never uses, paid for on every
# turn. The MCP flags are the same argument about connections: an empty config,
# strictly, so an MCP server the operator has for their own sessions is not
# loaded into a worker. Both entry points get them from one shared string, so a
# printed command and an executed one cannot say different things.
@test "the claude adapter limits a worker to the six tools it uses" {
  [ "${DUX_WORKER_HARNESS:-}" = claude ] || skip "claude only"
  for f in worker_cmd worker_launcher; do
    if [ "$f" = worker_cmd ]; then
      run adapter worker_cmd "$DUX_HOME/brief.md" model-x high "$DUX_HOME/settings.json"
      out="$output"
    else
      adapter worker_launcher "$chan/launch" "$DUX_HOME/brief.md" model-x high \
        "$DUX_HOME/settings.json" "$DUX_ROOT/bin"
      # The launcher quotes every flag, so the quotes come off before the
      # assertions below, which are about which flags are there. That the
      # quoting itself holds is the space-in-a-path test's job.
      out="$(tr -d "'" < "$chan/launch")"
    fi
    # The value the flag was actually given, not a substring of it: a seventh
    # tool appended to the list would match "...,Write,Edit" and pass.
    got="$(printf '%s\n' "$out" | tr ' ' '\n' | grep -A1 -xF -- --tools | sed -n 2p)"
    [ "$got" = Bash,Read,Glob,Grep,Write,Edit ] || { echo "$f: tool list is '$got': $out"; return 1; }
    [[ "$out" == *"--strict-mcp-config"* ]] || { echo "$f: not strict about MCP: $out"; return 1; }
    [[ "$out" == *"--mcp-config $DUX_ROOT/templates/worker-mcp.json"* ]] || { echo "$f: no MCP file: $out"; return 1; }
    [[ "$out" == *"--no-chrome"* ]] || { echo "$f: chrome not disabled: $out"; return 1; }
    # The flags this task deliberately does not use: safe mode drops Bash, and
    # settings-source isolation would drop the project's own instructions.
    [[ "$out" != *"--safe-mode"* ]] || { echo "$f: safe mode: $out"; return 1; }
    [[ "$out" != *"--settings-sources"* ]] || { echo "$f: settings sources: $out"; return 1; }
    # Unchanged: the deny rules reach the session either way.
    [[ "$out" == *"$DUX_HOME/settings.json"* ]] || { echo "$f: settings lost: $out"; return 1; }
  done
}

@test "the bundled MCP config names no server" {
  [ "$(jq -r '.mcpServers | length' "$DUX_ROOT/templates/worker-mcp.json")" -eq 0 ]
}

@test "worker_run runs the harness with the model and effort and returns its exit code" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only: claude starts through its launcher"
  printf 'status working: hi\nstatus done: report\nexit 4\n' > "$FAKE_WORKER_SCRIPT"
  run adapter worker_run "$DUX_HOME/brief.md" model-x high "$DUX_HOME/settings.json"
  [ "$status" -eq 4 ]
  [ "$(sed -n 2p "$DUX_STATUS_LOG")" = "done: report" ]
  grep -q "^$DUX_WORKER_HARNESS " "$FAKE_WORKER_LOG"
  case "$DUX_WORKER_HARNESS" in
    claude) grep -q -- '--model model-x --effort high' "$FAKE_WORKER_LOG" ;;
    codex)  grep -q -- '-m model-x' "$FAKE_WORKER_LOG"; grep -q -- 'model_reasoning_effort="high"' "$FAKE_WORKER_LOG" ;;
  esac
  grep -q -- 'the brief' "$FAKE_WORKER_LOG"
}

@test "worker_effort_ok accepts the harness's levels and rejects others" {
  [ -n "${DUX_WORKER_HARNESS:-}" ] || skip
  run adapter worker_effort_ok high; [ "$status" -eq 0 ]
  run adapter worker_effort_ok bogus; [ "$status" -ne 0 ]
  case "$DUX_WORKER_HARNESS" in
    claude) run adapter worker_effort_ok max; [ "$status" -eq 0 ]; run adapter worker_effort_ok minimal; [ "$status" -ne 0 ] ;;
    codex)  run adapter worker_effort_ok minimal; [ "$status" -eq 0 ]; run adapter worker_effort_ok max; [ "$status" -ne 0 ] ;;
  esac
}

@test "the fake dies on TERM while sleeping" {
  [ -n "${DUX_WORKER_HARNESS:-}" ] || skip
  printf 'sleep 30\nstatus done: report\n' > "$FAKE_WORKER_SCRIPT"
  "$DUX_WORKER_HARNESS" -p x > /dev/null & pid=$!
  sleep 1; kill -TERM "$pid"
  wait "$pid" || rc=$?
  [ "${rc:-0}" -eq 143 ]
  [ "$(grep -c done "$DUX_STATUS_LOG" || true)" -eq 0 ]
}

# The pane's shell is the harness's parent now, so everything the wrapper used
# to do to its own environment before forking has to happen inside the launcher.
# The check is on what the harness actually received, dumped from its own
# process, not on the text of the file: a scrub that reads right and unsets
# nothing would pass a text assertion.
@test "the launcher hands the harness a scrubbed environment and its own outboxes" {
  [ "${DUX_WORKER_HARNESS:-}" = claude ] || skip "claude only"
  dump="$DUX_HOME/state/dumped-env"
  printf 'dump-env %s\n' "$dump" > "$FAKE_WORKER_SCRIPT"
  adapter worker_launcher "$chan/launch" "$DUX_HOME/brief.md" model-x high \
    "$DUX_HOME/settings.json" "$DUX_ROOT/bin" "$chan/ship-record"
  [ -x "$chan/launch" ]

  # A pane shell carrying everything Dux's own session carries.
  DUX_HOME="$DUX_HOME" HERDR_PANE_ID=w1:p9 TMUX=/tmp/tmux-1/default,99,0 \
    GIT_CONFIG_COUNT=1 CLAUDECODE=1 CLAUDE_CONFIG_DIR=/tmp/cfg DUX_STATE=/tmp/s \
    run "$chan/launch"
  [ "$status" -eq 0 ]
  # Without this the negative greps below pass on a file that was never written.
  [ -s "$dump" ] || { echo "the harness dumped nothing: $output"; return 1; }
  grep -q '^PATH=' "$dump" || { echo "no PATH in the dump"; cat "$dump"; return 1; }

  for v in DUX_HOME DUX_STATE HERDR_PANE_ID TMUX GIT_CONFIG_COUNT CLAUDECODE CLAUDE_CONFIG_DIR; do
    ! grep -q "^$v=" "$dump" || { echo "$v reached the harness:"; grep "^$v=" "$dump"; return 1; }
  done
  [ "$(sed -n 's/^DUX_STATUS_LOG=//p' "$dump")" = "$chan/status.outbox" ]
  [ "$(sed -n 's/^DUX_REPORT=//p' "$dump")" = "$chan/report.outbox" ]
  [ "$(sed -n 's/^DUX_SHIP_RECORD=//p' "$dump")" = "$chan/ship-record" ]

  # Element by element: a substring test would call a PATH holding
  # $DUX_ROOT/bin-of-something clean and a stripped one dirty by turns.
  path="$(sed -n 's/^PATH=//p' "$dump")"
  kept=0
  while IFS= read -r e; do
    [ "$e" != "$DUX_ROOT/bin" ] || { echo "Dux's bin is still on the worker's PATH: $path"; return 1; }
    [ "$e" != "$DUX_ROOT/tests/fakes" ] || kept=1
  done < <(printf '%s\n' "$path" | tr ':' '\n')
  [ "$kept" -eq 1 ] || { echo "the strip took more than Dux's bin: $path"; return 1; }
}

# The one CLAUDE_ name that survives the scrub, and why. Spawn decides a project
# is trusted by reading Claude Code's record under CLAUDE_CONFIG_DIR. With the
# name scrubbed and nothing put back, the worker would answer the trust question
# out of a different file than the one that cleared it, and sit at the dialog
# spawn exists to keep it away from. The value is Dux's own, read where the
# launcher is written; a pane carrying another session's loses to it.
@test "the launcher gives the harness the config directory Dux itself was given" {
  [ "${DUX_WORKER_HARNESS:-}" = claude ] || skip "claude only"
  dump="$DUX_HOME/state/dumped-env"
  printf 'dump-env %s\n' "$dump" > "$FAKE_WORKER_SCRIPT"
  CLAUDE_CONFIG_DIR="$DUX_HOME/dux-config" adapter worker_launcher "$chan/launch" \
    "$DUX_HOME/brief.md" model-x high "$DUX_HOME/settings.json" "$DUX_ROOT/bin"
  CLAUDE_CONFIG_DIR=/tmp/another-session run "$chan/launch"
  [ "$status" -eq 0 ]
  [ -s "$dump" ] || { echo "the harness dumped nothing: $output"; return 1; }
  [ "$(sed -n 's/^CLAUDE_CONFIG_DIR=//p' "$dump")" = "$DUX_HOME/dux-config" ]
}

# A ship recorder is only a ship task's, and the launcher says so by leaving the
# variable out rather than exporting an empty one a worker could still name.
@test "a launcher without a ship recorder exports no DUX_SHIP_RECORD" {
  [ "${DUX_WORKER_HARNESS:-}" = claude ] || skip "claude only"
  dump="$DUX_HOME/state/dumped-env"
  printf 'dump-env %s\n' "$dump" > "$FAKE_WORKER_SCRIPT"
  adapter worker_launcher "$chan/launch" "$DUX_HOME/brief.md" model-x high \
    "$DUX_HOME/settings.json" "$DUX_ROOT/bin"
  run "$chan/launch"
  [ "$status" -eq 0 ]
  [ -s "$dump" ]
  ! grep -q '^DUX_SHIP_RECORD=' "$dump"
}

@test "the launcher is readable and runnable by its owner alone" {
  [ "${DUX_WORKER_HARNESS:-}" = claude ] || skip "claude only"
  adapter worker_launcher "$chan/launch" "$DUX_HOME/brief.md" model-x high \
    "$DUX_HOME/settings.json" "$DUX_ROOT/bin"
  [ "$(mode_of "$chan/launch")" = 500 ]
}

# Every path is baked in as a single-quoted literal. A quote inside one would
# end the literal early and turn the rest into the launcher's own shell code,
# so it refuses, as the ship recorder does.
@test "the launcher refuses a path or value holding a quote" {
  [ "${DUX_WORKER_HARNESS:-}" = claude ] || skip "claude only"
  printf "it's here\n" > "$DUX_HOME/quoted brief.md"
  run adapter worker_launcher "$chan/launch" "$DUX_HOME/br'ief.md" model-x high \
    "$DUX_HOME/settings.json" "$DUX_ROOT/bin"
  [ "$status" -ne 0 ]
  [[ "$output" == *"a path or value holds a quote"* ]]
  [ ! -e "$chan/launch" ]
  # The same for the optional last argument, which a ship task alone passes.
  run adapter worker_launcher "$chan/launch" "$DUX_HOME/brief.md" model-x high \
    "$DUX_HOME/settings.json" "$DUX_ROOT/bin" "$chan/ship'record"
  [ "$status" -ne 0 ]
  [ ! -e "$chan/launch" ]
}

# The brief is the session's opening prompt, so a DUX_HOME with a space in it
# has to survive the launcher as one argument.
@test "the launcher carries the brief through a path holding a space" {
  [ "${DUX_WORKER_HARNESS:-}" = claude ] || skip "claude only"
  spaced="$DUX_HOME/a dir"; mkdir -p "$spaced"
  printf 'the whole brief\n' > "$spaced/brief.md"
  printf 'exit 0\n' > "$FAKE_WORKER_SCRIPT"; : > "$FAKE_WORKER_LOG"
  adapter worker_launcher "$chan/launch" "$spaced/brief.md" model-x high \
    "$spaced/settings.json" "$DUX_ROOT/bin"
  run "$chan/launch"
  [ "$status" -eq 0 ]
  grep -q -- '--settings '"$spaced"'/settings.json' "$FAKE_WORKER_LOG"
  grep -q -- 'the whole brief' "$FAKE_WORKER_LOG"
}

# The name dux-backend pid matches the pane's foreground process against.
@test "worker_process_name names the process the harness runs as" {
  [ "${DUX_WORKER_HARNESS:-}" = claude ] || skip "claude only"
  run adapter worker_process_name
  [ "$status" -eq 0 ]
  [ "$output" = claude ]
}

# ---- the usage a codex run reports ---------------------------------------
# `codex exec --json` ends a run with one turn.completed event, and its usage is
# numbers in fields of their own, apart from the transcript items around it.
# Probed on codex-cli 0.154.0 (the rollout plan, task 32): input counts cached
# input inside it, output counts reasoning inside it, and `exec resume` reports
# the thread's running total under the same thread id.

events() {  # $@ event lines; written where the usage tests read them
  printf '%s\n' "$@" > "$DUX_HOME/events"
}

@test "codex usage takes cached input out of input and adds no reasoning to output" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  events '{"type":"thread.started","thread_id":"t-1"}' '{"type":"turn.started"}' \
    '{"type":"turn.completed","usage":{"input_tokens":55813,"cached_input_tokens":33664,"cache_write_input_tokens":0,"output_tokens":132,"reasoning_output_tokens":40}}'
  run adapter worker_usage < "$DUX_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "input=22149 output=132 cache_read=33664 cache_write=0" ]
}

@test "codex usage counts a resumed thread's running total once" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  # The probe's own numbers: one run, then exec resume of the same thread.
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":28384,"cached_input_tokens":6528,"cache_write_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0}}' \
    '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":62356,"cached_input_tokens":13568,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0}}'
  run adapter worker_usage < "$DUX_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "input=48788 output=10 cache_read=13568 cache_write=0" ]
}

@test "codex usage adds separate runs together" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":0,"output_tokens":30,"reasoning_output_tokens":0}}' \
    '{"type":"thread.started","thread_id":"t-2"}' \
    '{"type":"turn.completed","usage":{"input_tokens":2000,"cached_input_tokens":500,"cache_write_input_tokens":0,"output_tokens":70,"reasoning_output_tokens":9}}'
  run adapter worker_usage < "$DUX_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "input=2100 output=100 cache_read=900 cache_write=0" ]
}

@test "codex usage leaves a count codex did not give unknown, never zero" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  # A refused model: the run failed and reported no usage at all.
  events '{"type":"thread.started","thread_id":"t-1"}' '{"type":"error","message":"status 400"}' \
    '{"type":"turn.failed","error":{"message":"status 400"}}'
  run adapter worker_usage < "$DUX_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "input=unknown output=unknown cache_read=unknown cache_write=unknown" ]
  run adapter worker_usage < /dev/null
  [ "$output" = "input=unknown output=unknown cache_read=unknown cache_write=unknown" ]
  # One field missing and one that is not a count: those two, and only those.
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":55813,"cached_input_tokens":33664,"cache_write_input_tokens":0,"output_tokens":"132"}}'
  run adapter worker_usage < "$DUX_HOME/events"
  [ "$output" = "input=22149 output=unknown cache_read=33664 cache_write=0" ]
  # A run that gave nothing makes the sum of two runs unknown, not the other run alone.
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":0,"output_tokens":30}}' \
    '{"type":"thread.started","thread_id":"t-2"}' '{"type":"turn.completed","usage":{}}'
  run adapter worker_usage < "$DUX_HOME/events"
  [ "$output" = "input=unknown output=unknown cache_read=unknown cache_write=unknown" ]
}

@test "codex usage leaves input unknown when a run reports cache writes" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  # Every probe reported 0 cache writes, so whether input counts them is not
  # known. Input would be wrong by that much either way; the rest still holds.
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":55813,"cached_input_tokens":33664,"cache_write_input_tokens":500,"output_tokens":132}}'
  run adapter worker_usage < "$DUX_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "input=unknown output=132 cache_read=33664 cache_write=500" ]
}

@test "codex usage counts reviewer runs printed inside a worker's run only as the reviewers'" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  # A codex worker that runs a separate gate prints both reviewers' own events,
  # and the model can repeat them, inside its transcript items. Each review is
  # counted from its own event stream, so here they count for nothing: only the
  # worker's own top-level event does.
  reviewers='{"type":"thread.started","thread_id":"t-2"}
{"type":"turn.completed","usage":{"input_tokens":999999,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":999999}}
{"type":"thread.started","thread_id":"t-3"}
{"type":"turn.completed","usage":{"input_tokens":999999,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":999999}}'
  ran="$(jq -cn --arg out "$reviewers" '{type:"item.completed",item:{id:"c",type:"command_execution",aggregated_output:$out}}')"
  said="$(jq -cn --arg text "$reviewers" '{type:"item.completed",item:{id:"m",type:"agent_message",text:$text}}')"
  events '{"type":"thread.started","thread_id":"t-1"}' "$ran" "$said" 'turn.completed "input_tokens":999999' \
    '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":0,"output_tokens":30}}'
  run adapter worker_usage < "$DUX_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "input=600 output=30 cache_read=400 cache_write=0" ]
}

# ---- the gate's review block ---------------------------------------------
# Step 6 of the ship skill carries the block that runs a reviewer, and step 7
# runs the same block. It is run here as the skill carries it, against a codex
# that writes what the probes showed: events on stdout, its answer to -o.

review_block() {
  sed -n '/^## Step 6\./,/^## Step 7\./p' "$DUX_ROOT/skills/ship/SKILL.md" | awk '
    /^```bash$/ { inside = 1; text = ""; next }
    /^```$/ { if (inside && text ~ /SHIP_ENV" reviewer\)/) printf "%s", text; inside = 0; next }
    inside { text = text $0 "\n" }'
}

gate_fakes() {  # $1 the reviewer command ship-env resolves
  mkdir -p "$DUX_HOME/fake" "$DUX_HOME/tmp"
  printf '#!/bin/sh\ncase "$1" in reviewer) echo %s ;; --root) echo %s ;; esac\n' "'$1'" "'$DUX_ROOT'" \
    > "$DUX_HOME/fake/ship-env"
  cat > "$DUX_HOME/fake/codex" <<'FAKE'
#!/bin/sh
answer=""
while [ "$#" -gt 0 ]; do [ "$1" = -o ] && answer="$2"; shift; done
echo '{"type":"thread.started","thread_id":"t-1"}'
if [ -n "${FAKE_REFUSED:-}" ]; then
  echo '{"type":"error","message":"{\"type\":\"error\",\"status\":400}"}'
  echo '{"type":"turn.failed","error":{"message":"{\"type\":\"error\",\"status\":400}"}}'
  exit 1
fi
# Codex writes its answer with no newline after the last line.
printf '## Findings\nNo findings.' > "$answer"
echo '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":0,"output_tokens":30}}'
FAKE
  printf '#!/bin/sh\nprintf "## Findings\\nNo findings.\\n"\n' > "$DUX_HOME/fake/other-reviewer"
  chmod +x "$DUX_HOME/fake/ship-env" "$DUX_HOME/fake/codex" "$DUX_HOME/fake/other-reviewer"
}

run_review_block() {
  block="$(review_block)"
  [ -n "$block" ] || { echo "step 6 carries no reviewer block"; return 1; }
  run env SHIP_ENV="$DUX_HOME/fake/ship-env" BASE=main TMPDIR="$DUX_HOME/tmp" \
    PATH="$DUX_HOME/fake:$PATH" bash -c "$block"
}

@test "the gate prints a codex review's answer, then the usage codex reported for it" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  gate_fakes 'codex exec -m some-model --sandbox read-only'
  run_review_block
  [ "${lines[0]}" = "## Findings" ]
  [ "${lines[1]}" = "No findings." ]
  [ "${lines[2]}" = "usage: input=600 output=30 cache_read=400 cache_write=0" ]
  [ "${#lines[@]}" -eq 3 ]
  # Nothing of the run is left behind.
  [ -z "$(ls -A "$DUX_HOME/tmp")" ]
}

@test "the gate shows a refused review model, leaves its usage unknown and fails" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  gate_fakes 'codex exec -m some-model --sandbox read-only'
  FAKE_REFUSED=1 run_review_block
  [ "$status" -eq 2 ]
  [[ "$output" != *"## Findings"* ]]
  [[ "$output" == *'reviewer error: {"type":"error","status":400}'* ]]
  [[ "$output" == *"usage: input=unknown output=unknown cache_read=unknown cache_write=unknown"* ]]
  [ "${lines[${#lines[@]}-1]}" = "finding: the reviewer exited 1" ]
  [ -z "$(ls -A "$DUX_HOME/tmp")" ]
}

@test "the gate leaves a reviewer that gives no counts unknown" {
  [ "${DUX_WORKER_HARNESS:-}" = codex ] || skip "codex only"
  gate_fakes 'other-reviewer --read-only'
  run_review_block
  [ "${lines[0]}" = "## Findings" ]
  [ "${lines[1]}" = "No findings." ]
  [ "${lines[2]}" = "usage: input=unknown output=unknown cache_read=unknown cache_write=unknown" ]
  [ -z "$(ls -A "$DUX_HOME/tmp")" ]
}
