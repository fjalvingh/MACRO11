#!/bin/sh
#
# Regression tests: assemble each tests/*.mac and compare the messages,
# exit status, listing and object dump with tests/*.ref.
#
# Usage: run-tests.sh [-u]
#   -u  update the .ref files from the current output
#

cd "$(dirname "$0")" || exit 1

MACRO11=../macro11
DUMPOBJ=../dumpobj
update=0
[ "$1" = "-u" ] && update=1

pass=0
fail=0

for src in *.mac; do
    name=${src%.mac}
    out=$name.out

    "$MACRO11" "$src" -l "$name.lst" -o "$name.obj" > "$out" 2>&1
    echo "exit status $?" >> "$out"
    echo "--- listing" >> "$out"
    cat "$name.lst" >> "$out"
    echo "--- object" >> "$out"
    "$DUMPOBJ" "$name.obj" >> "$out" 2>&1
    rm -f "$name.lst" "$name.obj"

    if [ $update = 1 ]; then
        mv "$out" "$name.ref"
        echo "UPDATED $name"
    elif cmp -s "$out" "$name.ref"; then
        rm -f "$out"
        echo "PASS  $name"
        pass=$((pass + 1))
    else
        echo "FAIL  $name (diff $name.ref $out)"
        fail=$((fail + 1))
    fi
done

[ $update = 1 ] && exit 0

echo "$pass passed, $fail failed"
[ $fail = 0 ]
