# A reader that stops before its producer is done closes the pipe under it, and
# a producer that handles SIGPIPE rather than dying reports the failed write on
# stderr, where Dux prints only findings. This has been fixed three times as
# three separate bugs; this check is what stops a fourth.
#
# Rejected: `head`, and `grep` with a flag that returns early, in a piped
# position. A piped position is after a `|` on the same line, or at the start of
# a stage the line before continued.
#
# Accepted, because none of them has a producer to break: `head -c N file` and
# `grep -q PAT file` read a file directly. So do the sanctioned forms:
# dux-env's take_bytes and take_line, and `grep ... >/dev/null`, which reads to
# the end because it has to print every match.
BEGIN {
  reader = "(head([ \t]|$)|grep[ \t]+(-[A-Za-z]*[qm][A-Za-z]*([ \t]|=|[0-9]|$)|--(quiet|silent|max-count)))"
}
{ line = $0; sub(/^[ \t]*/, "", line) }
line ~ /^#/ { next }
{
  if (line ~ ("\\|[ \t]*" reader) || (piped && line ~ ("^\\|?[ \t]*" reader))) {
    print FILENAME ":" FNR ": " $0
    rc = 1
  }
  # The next line is a piped stage when this one ends in a pipe, with or without
  # a line continuation after it, or when it starts with one.
  cont = (line ~ /\|[ \t]*(\\[ \t]*)?$/)
  piped = (cont || line ~ /^\|/)
}
END { exit rc }
