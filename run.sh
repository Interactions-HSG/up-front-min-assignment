#!/bin/sh
# Charging one key several ways, and counting what reached the gateway.
#
# The fake gateway comes from /scenarios/gateway.mjs rather than from a second
# copy written here. The candidate wrote `charge` against that shape, and two
# definitions of it would eventually disagree about what their code does — the
# plugin's numbers and these would then be evidence of different things.
#
# These report what the submission did rather than marking it: a card billed
# twice is a number to ask about, not a failure. A non-zero exit means the
# submission could not be run at all.
#
# The probe is written into /build: /work belongs to root so that a submission
# cannot rewrite itself while it is being run, and /tmp is noexec.
#
# Usage: run.sh --list | run.sh [concurrent|sequential|distinct-keys|failed-charge|expiry]
set -eu

if [ "${1:-}" = "--list" ]; then
  printf 'concurrent\tCharges one key twice with both calls in flight at once, and counts gateway calls. A check-then-act implementation bills the card twice here and passes every sequential test its author wrote.\n'
  printf 'sequential\tCharges one key twice, one call after the other, and counts gateway calls. Nearly every submission charges once here, which is what makes it worth having beside the concurrent number.\n'
  printf 'distinct-keys\tCharges two different keys and counts gateway calls. Catches an implementation that is idempotent about the wrong thing and hands the second key the receipt from the first.\n'
  printf 'failed-charge\tThe gateway refuses the first attempt, and the same key is charged again afterwards. Says whether a payment that never happened can still be made, or whether the key is spent.\n'
  printf 'expiry\tCharges a key, winds the injected clock on a year, and charges the same key again. Says whether the record of a charge ever expires. The assignment does not say it must, so what is worth asking is which they chose.\n'
  exit 0
fi

TARGET="${1:-concurrent}"
case "$TARGET" in
  concurrent | sequential | distinct-keys | failed-charge | expiry) ;;
  *) echo "no such target: $TARGET"; exit 2 ;;
esac

mkdir -p "${TMPDIR:-/build/tmp}"
[ -f /work/payments.js ] || { echo "the submission has no payments.js at its root"; exit 2; }
[ -f /scenarios/gateway.mjs ] || {
  echo "this assignment's fake gateway lives in /scenarios/gateway.mjs, which is not mounted"
  exit 2
}

W=/build/viva-run
rm -rf "$W"; mkdir -p "$W"

cat > "$W/probe.mjs" <<'JS'
import { Gateway, load } from '/scenarios/gateway.mjs';

let Payments;
try {
  Payments = await load();
} catch (err) {
  console.log(err?.message ?? String(err));
  process.exit(2);
}

/** A gateway that refuses the first card it is shown and takes the rest. */
class Refusing extends Gateway {
  constructor() {
    super();
    this.attempts = 0;
  }
  async charge(amount) {
    this.attempts += 1;
    if (this.attempts === 1) {
      await new Promise((r) => setTimeout(r, this.latencyMs));
      throw new Error('the gateway refused this card');
    }
    return super.charge(amount);
  }
}

async function run(target) {
  if (target === 'concurrent') {
    const gw = new Gateway();
    const p = new Payments(gw);
    const [a, b] = await Promise.all([p.charge('key-1', 500), p.charge('key-1', 500)]);
    console.log(`receipt A: ${JSON.stringify(a)}`);
    console.log(`receipt B: ${JSON.stringify(b)}`);
    console.log(`gateway charged ${gw.charges.length} time(s) for one key`);
    console.log(
      gw.charges.length === 1
        ? 'charged once, even overlapping'
        : `CHARGED ${gw.charges.length} TIMES — the card was billed ${gw.charges.length}x`,
    );
    return;
  }

  if (target === 'sequential') {
    const gw = new Gateway();
    const p = new Payments(gw);
    const a = await p.charge('key-1', 500);
    const b = await p.charge('key-1', 500);
    console.log(`first receipt: ${JSON.stringify(a)}`);
    console.log(`retry receipt: ${JSON.stringify(b)}`);
    console.log(`gateway charged ${gw.charges.length} time(s)`);
    console.log(
      gw.charges.length === 1
        ? 'charged once'
        : 'CHARGED MORE THAN ONCE — the retry that arrived after the reply was billed',
    );
    return;
  }

  if (target === 'distinct-keys') {
    const gw = new Gateway();
    const p = new Payments(gw);
    const a = await p.charge('key-a', 500);
    const b = await p.charge('key-b', 700);
    console.log(`receipt for key-a: ${JSON.stringify(a)}`);
    console.log(`receipt for key-b: ${JSON.stringify(b)}`);
    console.log(`gateway charged ${gw.charges.length} time(s) for two keys: ${JSON.stringify(gw.charges)}`);
    if (gw.charges.length !== 2) {
      console.log(`TWO KEYS, ${gw.charges.length} CHARGE(S) — this is idempotent about the wrong thing`);
    } else if (JSON.stringify(a) === JSON.stringify(b)) {
      console.log('both keys were charged, but they were handed the same receipt');
    } else {
      console.log('two keys, two charges');
    }
    return;
  }

  if (target === 'failed-charge') {
    const gw = new Refusing();
    const p = new Payments(gw);
    let first = null;
    let firstErr = null;
    try {
      first = await p.charge('key-1', 500);
    } catch (err) {
      firstErr = err;
    }
    console.log(
      firstErr
        ? `the first attempt threw: ${firstErr.message}`
        : `the first attempt returned ${JSON.stringify(first)}`,
    );

    let second = null;
    let secondErr = null;
    try {
      second = await p.charge('key-1', 500);
    } catch (err) {
      secondErr = err;
    }
    console.log(
      secondErr
        ? `the retry threw: ${secondErr.message}`
        : `the retry returned ${JSON.stringify(second)}`,
    );
    console.log(`  gateway attempts:   ${gw.attempts}`);
    console.log(`  charges that stuck: ${gw.charges.length}`);

    if (gw.charges.length === 0) {
      console.log('THE KEY IS SPENT — the retry never reached the gateway, so a card that was never charged never can be');
    } else if (secondErr) {
      console.log('THE FAILURE WAS REMEMBERED — the retry was refused by the submission, not by the gateway');
    } else if (gw.charges.length !== 1) {
      console.log(`CHARGED ${gw.charges.length} TIMES after one refusal`);
    } else {
      console.log('the refused charge was retried, and went through exactly once');
    }
    return;
  }

  if (target === 'expiry') {
    let clock = 1_700_000_000_000;
    const gw = new Gateway();
    const p = new Payments(gw, () => clock);
    const a = await p.charge('key-1', 500);
    clock += 366 * 24 * 60 * 60 * 1000;
    const b = await p.charge('key-1', 500);
    console.log(`first receipt: ${JSON.stringify(a)}`);
    console.log(`a year later:  ${JSON.stringify(b)}`);
    console.log(`gateway charged ${gw.charges.length} time(s)`);
    // Neither answer is wrong on its own. What the candidate has to account
    // for is the one they chose, and what it costs a year from now.
    console.log(
      gw.charges.length === 1
        ? 'the key is still remembered a year on: this map never forgets'
        : `the record expired: the same key was charged ${gw.charges.length} times, a year apart`,
    );
    return;
  }
}

try {
  await run(process.argv[2]);
} catch (err) {
  console.log(`the submission threw: ${err?.message ?? err}`);
  process.exit(1);
}
JS

node "$W/probe.mjs" "$TARGET" 2>&1
