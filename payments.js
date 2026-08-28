/**
 * Charging a card at most once, however many times the client asks.
 */

export class Payments {
  constructor(gateway, now = Date.now) {
    this.gateway = gateway;
    this.now = now;
    this.seen = new Map();
  }

  async charge(key, amount) {
    // Already charged? Hand back what the gateway said the first time.
    if (this.seen.has(key)) {
      return this.seen.get(key);
    }

    const receipt = await this.gateway.charge(amount);
    this.seen.set(key, receipt);
    return receipt;
  }
}
