import fetch from "node-fetch";
import { DefaultAzureCredential } from "@azure/identity";
import { SecretClient } from "@azure/keyvault-secrets";

let cachedApiToken: string | null = null;
let cachedPhoneNumberId: string | null = null;
const credential = new DefaultAzureCredential();

async function getWhatsAppConfig(): Promise<{
  apiToken: string;
  phoneNumberId: string;
}> {
  if (cachedApiToken && cachedPhoneNumberId) {
    return { apiToken: cachedApiToken, phoneNumberId: cachedPhoneNumberId };
  }

  const keyVaultUri = process.env.KEY_VAULT_URI;
  if (keyVaultUri) {
    try {
      console.log("Loading WhatsApp config from Key Vault...");
      const client = new SecretClient(keyVaultUri, credential);
      const tokenSecret = await client.getSecret("whatsapp-api-token");
      const phoneSecret = await client.getSecret("whatsapp-phone-number-id");
      cachedApiToken = tokenSecret.value || "";
      cachedPhoneNumberId = phoneSecret.value || "";
      console.log("WhatsApp config loaded from Key Vault");
      return { apiToken: cachedApiToken, phoneNumberId: cachedPhoneNumberId };
    } catch (err) {
      console.warn("Failed to load WhatsApp config from Key Vault:", err);
    }
  }

  // Fallback to environment variables (local dev)
  cachedApiToken = process.env.WHATSAPP_API_TOKEN || "";
  cachedPhoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID || "";
  return { apiToken: cachedApiToken, phoneNumberId: cachedPhoneNumberId };
}

export async function sendWhatsAppMessage(
  to: string,
  text: string
): Promise<void> {
  const { apiToken, phoneNumberId } = await getWhatsAppConfig();

  if (!apiToken || !phoneNumberId) {
    console.warn("WhatsApp API token or phone number ID not configured");
    return;
  }

  const url = `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiToken}`,
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to,
      type: "text",
      text: { body: text },
    }),
  });

  if (!res.ok) {
    const error = await res.text();
    throw new Error(`WhatsApp error: ${res.status} - ${error}`);
  }
}
