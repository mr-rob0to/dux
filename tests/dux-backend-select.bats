load helpers/setup

@test "DUX_BACKEND env wins" {
  DUX_BACKEND=herdr run dux-backend name; [ "$output" = herdr ]
  DUX_BACKEND=tmux run dux-backend name; [ "$output" = tmux ]
}

@test "config/backend file is second" {
  echo herdr > "$DUX_HOME/config/backend"
  unset DUX_BACKEND
  run dux-backend name; [ "$output" = herdr ]
}

@test "HERDR_ENV=1 without TMUX selects herdr, otherwise tmux" {
  unset DUX_BACKEND; rm -f "$DUX_HOME/config/backend"
  HERDR_ENV=1 TMUX= run env -u TMUX HERDR_ENV=1 dux-backend name; [ "$output" = herdr ]
  run env -u HERDR_ENV TMUX=/tmp/x dux-backend name; [ "$output" = tmux ]
  run env -u HERDR_ENV -u TMUX dux-backend name; [ "$output" = tmux ]
}

@test "unknown backend value is a finding" {
  DUX_BACKEND=zellij run dux-backend name
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown backend zellij"* ]]
}
