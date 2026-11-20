#!/bin/zsh
# Previews each file through the installed bench extension (via the milestone 1 probe) and
# prints the result rows the extension wrote. usage: run-appex.sh probe-binary file...
setopt nullglob
PROBE=$1; shift
TSV=$HOME/Library/Containers/com.mdrum.infiniview.bench.preview/Data/bench.tsv
FIFO=$(mktemp -u); mkfifo $FIFO
$PROBE < $FIFO >/dev/null 2>&1 &
PP=$!
exec 3>$FIFO
rm -f $TSV
n=0
for f in "$@"; do
  n=$((n + 1))
  print -u3 -- "$f"
  for i in {1..240}; do sleep 0.25; [[ -f $TSV && $(wc -l < $TSV) -ge $n ]] && break; done
  [[ -f $TSV && $(wc -l < $TSV) -ge $n ]] || { echo "timeout on $f" >&2; n=$((n - 1)); }
  sleep 0.5
done
exec 3>&-; kill $PP 2>/dev/null; rm -f $FIFO
cat $TSV
