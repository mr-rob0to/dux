load helpers/setup

@test "add appends a queued line in the exact format" {
  run dux-ledger add proj-scout-20260903-abc proj scout local
  [ "$status" -eq 0 ]
  line="$(cat "$DUX_HOME/data/backlog.md")"
  [[ "$line" =~ ^-\ proj-scout-20260903-abc\ project=proj\ shape=scout\ state=queued\ source=local\ endpoint=-\ pr=-\ acked=-\ \(updated\ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\)$ ]]
}

@test "add refuses a duplicate id" {
  dux-ledger add t1 proj scout local
  run dux-ledger add t1 proj scout local
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: task t1 already in ledger"* ]]
  [ "$(grep -c '^- t1 ' "$DUX_HOME/data/backlog.md")" -eq 1 ]
}

@test "set changes one field, keeps the others, and is idempotent" {
  dux-ledger add t1 proj ship local
  dux-ledger add t2 proj scout local
  run dux-ledger set t1 state running
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get t1 state)" = running ]
  [ "$(dux-ledger get t1 shape)" = ship ]
  [ "$(dux-ledger get t2 state)" = queued ]
  before="$(dux-ledger line t1 | sed 's/ (updated .*//')"
  dux-ledger set t1 state running
  [ "$(dux-ledger line t1 | sed 's/ (updated .*//')" = "$before" ]
  [ "$(wc -l < "$DUX_HOME/data/backlog.md" | tr -d ' ')" -eq 2 ]
}

@test "values with colons, slashes, and equals round-trip" {
  dux-ledger add t1 proj scout local
  dux-ledger set t1 endpoint 'tmux:dux:@3'
  dux-ledger set t1 pr 'https://example.invalid/pr/7?x=1'
  [ "$(dux-ledger get t1 endpoint)" = 'tmux:dux:@3' ]
  [ "$(dux-ledger get t1 pr)" = 'https://example.invalid/pr/7?x=1' ]
  [ "$(dux-ledger get t1 state)" = queued ]
}

@test "set on an unknown id is a finding" {
  run dux-ledger set nope state running
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: task nope not in ledger"* ]]
}

@test "set refuses an unknown key, an unknown state, and a value with whitespace" {
  dux-ledger add t1 proj scout local
  run dux-ledger set t1 colour red; [ "$status" -eq 2 ]; [[ "$output" == "finding: unknown ledger key colour"* ]]
  run dux-ledger set t1 state sleeping; [ "$status" -eq 2 ]; [[ "$output" == "finding: unknown state sleeping"* ]]
  run dux-ledger set t1 pr 'a b'; [ "$status" -eq 2 ]; [[ "$output" == "finding: ledger value must be one token"* ]]
  [ "$(dux-ledger get t1 state)" = queued ]
}

@test "an id that is nothing but dots is refused, and a normal id still works" {
  run dux-ledger add .. proj scout local
  [ "$status" -eq 2 ]; [[ "$output" == "finding: task id must not be all dots"* ]]
  run dux-ledger add . proj scout local
  [ "$status" -eq 2 ]; [[ "$output" == "finding: task id must not be all dots"* ]]
  [ ! -s "$DUX_HOME/data/backlog.md" ]
  run dux-ledger add proj-scout-20260904-a1b proj scout local
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get proj-scout-20260904-a1b state)" = queued ]
  run dux-ledger set .. state running
  [ "$status" -eq 2 ]; [[ "$output" == "finding: task id must not be all dots"* ]]
}

@test "a value carrying a backslash never becomes a second ledger line" {
  dux-ledger add t1 proj scout local
  run dux-ledger set t1 pr 'https://example.invalid/pr/1\n-\tt2\tproject=proj'
  [ "$status" -eq 2 ]; [[ "$output" == "finding: ledger value must not contain a backslash"* ]]
  [ "$(wc -l < "$DUX_HOME/data/backlog.md" | tr -d ' ')" -eq 1 ]
  [ "$(dux-ledger get t1 pr)" = "-" ]
}

@test "get refuses an unknown id and an unknown key" {
  dux-ledger add t1 proj scout local
  run dux-ledger get nope state; [ "$status" -eq 2 ]
  run dux-ledger get t1 colour; [ "$status" -eq 2 ]; [[ "$output" == "finding: unknown ledger key colour"* ]]
}

@test "list filters by state and project" {
  dux-ledger add a1 proj scout local; dux-ledger add a2 proj ship local; dux-ledger add b1 other scout local
  dux-ledger set a2 state running
  run dux-ledger list; [ "$output" = $'a1\na2\nb1' ]
  run dux-ledger list --state queued; [ "$output" = $'a1\nb1' ]
  run dux-ledger list --project proj --state running; [ "$output" = "a2" ]
  run dux-ledger list --state done; [ "$output" = "" ]
}

@test "six parallel sets all land" {
  for i in 1 2 3 4 5 6; do dux-ledger add "t$i" proj scout local; done
  jobs=""; for i in 1 2 3 4 5 6; do dux-ledger set "t$i" state running & jobs="$jobs $!"; done
  wait $jobs
  for i in 1 2 3 4 5 6; do [ "$(dux-ledger get "t$i" state)" = running ]; done
  [ "$(wc -l < "$DUX_HOME/data/backlog.md" | tr -d ' ')" -eq 6 ]
  [ ! -d "$DUX_HOME/data/backlog.md.lock" ]
}

@test "a held ledger mutex is a finding after the wait, never a silent skip" {
  dux-ledger add t1 proj scout local
  mkdir "$DUX_HOME/data/backlog.md.lock"
  DUX_LEDGER_WAIT_TENTHS=3 run dux-ledger set t1 state running
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: ledger busy"* ]]
  [ "$(dux-ledger get t1 state)" = queued ]
}

@test "a mutex older than a minute is reclaimed" {
  dux-ledger add t1 proj scout local
  mkdir "$DUX_HOME/data/backlog.md.lock"
  touch -t 202001010000 "$DUX_HOME/data/backlog.md.lock"
  DUX_LEDGER_WAIT_TENTHS=3 run dux-ledger set t1 state running
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get t1 state)" = running ]
  [ ! -d "$DUX_HOME/data/backlog.md.lock" ]
}

@test "add writes acked=- and ack records the current state" {
  dux-ledger add t1 proj scout local
  [[ "$(dux-ledger line t1)" == *" pr=- acked=- (updated "* ]]
  [ "$(dux-ledger get t1 acked)" = - ]
  dux-ledger set t1 state done
  run dux-ledger ack t1
  [ "$status" -eq 0 ]
  [ "$(dux-ledger get t1 acked)" = done ]
  [ "$(dux-ledger get t1 state)" = done ]
}

@test "unack lets the same state wake again" {
  dux-ledger add t1 proj scout local
  dux-ledger set t1 state stale; dux-ledger ack t1
  run dux-ledger list --unacked; [ "$output" = "" ]
  run dux-ledger unack t1
  [ "$status" -eq 0 ]; [ "$(dux-ledger get t1 acked)" = - ]
  run dux-ledger list --unacked; [ "$output" = t1 ]
  run dux-ledger unack nope; [ "$status" -eq 2 ]; [[ "$output" == "finding: task nope not in ledger"* ]]
}

@test "an old line reads as unacknowledged and gains the field on ack" {
  printf -- '- old project=proj shape=scout state=done source=local endpoint=herdr:w1:p9 pr=- (updated 2026-09-01T00:00:00Z)\n' > "$DUX_HOME/data/backlog.md"
  [ "$(dux-ledger get old acked)" = - ]
  run dux-ledger list --unacked; [ "$output" = old ]
  dux-ledger ack old
  [[ "$(dux-ledger line old)" == "- old project=proj shape=scout state=done source=local endpoint=herdr:w1:p9 pr=- acked=done (updated "* ]]
  [ "$(dux-ledger get old shape)" = scout ]
}

@test "ack refuses unknown and bad ids, and set cannot write acked" {
  run dux-ledger ack nope; [ "$status" -eq 2 ]; [[ "$output" == "finding: task nope not in ledger"* ]]
  run dux-ledger ack ../x; [ "$status" -eq 2 ]; [[ "$output" == "finding: task id must match"* ]]
  dux-ledger add t1 proj scout local
  run dux-ledger set t1 acked done; [ "$status" -eq 2 ]; [[ "$output" == "finding: unknown ledger key acked"* ]]
}

@test "list --unacked names changed event states only" {
  for s in queued running needs-decision blocked done failed ended stale dead; do
    dux-ledger add "t-$s" proj scout local
    dux-ledger set "t-$s" state "$s"
  done
  dux-ledger ack t-done
  run dux-ledger list --unacked
  [ "$output" = $'t-needs-decision\nt-blocked\nt-failed\nt-ended\nt-stale\nt-dead' ]
}
