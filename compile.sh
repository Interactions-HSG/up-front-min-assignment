#!/bin/sh
# Whether the submission is still something node can load.
#
# JavaScript has no compile step, so validity here is what node itself decides:
# the file parses as the module it declares itself to be, it loads without
# throwing, and a Payments class comes out. That is a real check — a patch with
# an unbalanced brace, a stray `await` outside an async function, or an import
# of a package this image does not have fails right here.
#
# It stops at the class. Whether `charge` is on the prototype is not a question
# this can answer without refusing a legal submission — a method written as a
# class field is not on the prototype at all — and run.sh calls it anyway.
set -eu
mkdir -p "${TMPDIR:-/build/tmp}"
[ -f /work/payments.js ] || { echo "the submission has no payments.js at its root"; exit 2; }

W=/build/viva-compile
rm -rf "$W"; mkdir -p "$W"

cat > "$W/check.mjs" <<'JS'
const mod = await import('/work/payments.js');
const Payments = mod.Payments ?? mod.default;
if (typeof Payments !== 'function') {
  console.log('payments.js loads, but exports no Payments class');
  process.exit(1);
}
console.log('payments.js parses, loads, and exports a Payments class');
JS

node "$W/check.mjs" 2>&1
