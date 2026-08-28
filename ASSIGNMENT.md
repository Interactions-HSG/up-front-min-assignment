# Charge the card once (example assignment)

A client that does not hear back from you cannot tell a lost request from a
lost reply, so it retries. The retry carries the same **idempotency key**, and
it must not charge the card again.

Your problem is `payments.js`, and one method in it.

## What to do

1. **`Payments.charge(key, amount)`** — return the gateway's receipt, calling
   `gateway.charge(amount)` at most once per key.
2. A charge that *fails* is not a charge: the client must be able to retry it.

## What you are marked on

Whether you can explain what you built, in a viva, against the commit you hand
in. Three things worth being able to answer:

- Which line records the key, and where is it relative to the gateway call?
- How long should a key be remembered, and what breaks at either extreme?
- Two requests with the same key arrive *at the same time*. What happens?
