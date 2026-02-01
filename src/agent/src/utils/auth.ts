import * as crypto from "crypto";

// Verify Telegram webhook signature
export function verifyTelegramSignature(
  token: string,
  payload: string,
  signature: string
): boolean {
  const secretKey = crypto.createHash("sha256").update(token).digest();
  const hmac = crypto.createHmac("sha256", secretKey).update(payload).digest("hex");
  return hmac === signature;
}

// Verify Slack request signature
export function verifySlackSignature(
  signingSecret: string,
  timestamp: string,
  body: string,
  signature: string
): boolean {
  const baseString = `v0:${timestamp}:${body}`;
  const hmac = crypto
    .createHmac("sha256", signingSecret)
    .update(baseString)
    .digest("hex");
  const expectedSignature = `v0=${hmac}`;
  
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );
}

// Generate a simple session token
export function generateSessionToken(): string {
  return crypto.randomBytes(32).toString("hex");
}

// Hash user ID for anonymization
export function hashUserId(userId: string): string {
  return crypto.createHash("sha256").update(userId).digest("hex").slice(0, 16);
}
