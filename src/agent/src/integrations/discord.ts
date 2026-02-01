import fetch from "node-fetch";

export async function sendDiscordMessage(
  channelId: string,
  content: string
): Promise<void> {
  const token = process.env.DISCORD_BOT_TOKEN;

  if (!token) {
    console.warn("DISCORD_BOT_TOKEN not set");
    return;
  }

  const url = `https://discord.com/api/v10/channels/${channelId}/messages`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bot ${token}`,
    },
    body: JSON.stringify({ content }),
  });

  if (!res.ok) {
    throw new Error(`Discord error: ${res.status}`);
  }
}
