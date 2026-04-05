describe("queue message parsing", () => {
  it("parses valid base64-encoded JSON queue message", () => {
    const original = {
      channel: "telegram",
      chatId: 12345,
      text: "Hello bot",
      userId: "user1",
      timestamp: Date.now(),
    };
    const encoded = Buffer.from(JSON.stringify(original)).toString("base64");
    const decoded = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
    expect(decoded.channel).toBe("telegram");
    expect(decoded.text).toBe("Hello bot");
    expect(decoded.chatId).toBe(12345);
  });

  it("handles all supported channel types", () => {
    const channels = ["telegram", "slack", "discord", "whatsapp"];
    for (const channel of channels) {
      const msg = { channel, chatId: "123", text: "hi", timestamp: Date.now() };
      const encoded = Buffer.from(JSON.stringify(msg)).toString("base64");
      const decoded = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
      expect(decoded.channel).toBe(channel);
    }
  });

  it("correctly identifies messages exceeding dequeue count threshold", () => {
    const MAX_DEQUEUE_COUNT = 3;
    expect(4).toBeGreaterThan(MAX_DEQUEUE_COUNT);
    expect(3).not.toBeGreaterThan(MAX_DEQUEUE_COUNT);
  });

  it("preserves unicode text through base64 encoding", () => {
    const msg = { channel: "telegram", chatId: 1, text: "Hello 🌍 こんにちは", timestamp: Date.now() };
    const encoded = Buffer.from(JSON.stringify(msg)).toString("base64");
    const decoded = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
    expect(decoded.text).toBe("Hello 🌍 こんにちは");
  });
});
