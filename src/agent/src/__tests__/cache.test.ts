import { Cache } from "../utils/cache";

describe("Cache", () => {
  it("returns undefined for cache miss", () => {
    const cache = new Cache<string>();
    expect(cache.get("nonexistent-key")).toBeUndefined();
  });

  it("returns cached value within TTL", () => {
    const cache = new Cache<string>(300);
    cache.set("test-key", "cached-response");
    expect(cache.get("test-key")).toBe("cached-response");
  });

  it("reports has() correctly", () => {
    const cache = new Cache<string>();
    expect(cache.has("missing")).toBe(false);
    cache.set("exists", "value");
    expect(cache.has("exists")).toBe(true);
  });

  it("deletes entries", () => {
    const cache = new Cache<string>();
    cache.set("key", "value");
    expect(cache.delete("key")).toBe(true);
    expect(cache.get("key")).toBeUndefined();
  });

  it("clears all entries", () => {
    const cache = new Cache<string>();
    cache.set("a", "1");
    cache.set("b", "2");
    cache.clear();
    expect(cache.size).toBe(0);
  });

  it("returns undefined after TTL expires", () => {
    jest.useFakeTimers();
    const cache = new Cache<string>(1); // 1 second TTL
    cache.set("expire-key", "will-expire");
    jest.advanceTimersByTime(1001);
    expect(cache.get("expire-key")).toBeUndefined();
    jest.useRealTimers();
  });
});
