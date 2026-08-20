/**
 * Charging a card at most once, however many times the client asks.
 *
 * The network is the problem. A client that does not hear back cannot tell a
 * lost request from a lost reply, so it retries — and the retry must not
 * charge again. `charge` is the part with a decision in it.
 */

export class Payments {
  constructor(gateway, now = Date.now) {
    this.gateway = gateway;
    this.now = now;
    this.seen = new Map();
  }

  /** The gateway's receipt for this key, charging at most once. */
  async charge(key, amount) {
    throw new Error('not implemented');
  }
}
