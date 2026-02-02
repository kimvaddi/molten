import fetch from "node-fetch";
import { DefaultAzureCredential } from "@azure/identity";
import { SecretClient } from "@azure/keyvault-secrets";

let cachedToken: string | null = null;
const credential = new DefaultAzureCredential();

async function getTelegramToken(): Promise<string> {
  if (cachedToken) return cachedToken;

  // Try Key Vault first (production)
  const keyVaultUri = process.env.KEY_VAULT_URI;
  if (keyVaultUri) {
    try {
      console.log("Loading Telegram token from Key Vault...");
      const client = new SecretClient(keyVaultUri, credential);
      const secret = await client.getSecret("telegram-bot-token");
      cachedToken = secret.value || "";
      console.log("Telegram token loaded from Key Vault");
      return cachedToken;
    } catch (err) {
      console.warn("Failed to load Telegram token from Key Vault:", err);
    }
  }

  // Fallback to environment variable (local development only)
  cachedToken = process.env.TELEGRAM_BOT_TOKEN || "";
  if (!cachedToken) {
    console.warn("TELEGRAM_BOT_TOKEN not found in Key Vault or environment");
  }
  return cachedToken;
}

export async function sendTelegramMessage(
  chatId: number,
  text: string
): Promise<void> {
  const token = await getTelegramToken();

  if (!token) {
    console.warn("TELEGRAM_BOT_TOKEN not available");
    return;
  }

  const url = `https://api.telegram.org/bot${token}/sendMessage`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      parse_mode: "Markdown",
    }),
  });

  if (!res.ok) {
    const error = await res.text();
    throw new Error(`Telegram error: ${res.status} - ${error}`);
  }
}
