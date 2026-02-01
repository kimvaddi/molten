import fetch from "node-fetch";

export async function sendSlackMessage(
  channel: string,
  text: string
): Promise<void> {
  const token = process.env.SLACK_BOT_TOKEN;

  if (!token) {
    console.warn("SLACK_BOT_TOKEN not set");
    return;
  }

  const url = "https://slack.com/api/chat.postMessage";

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ channel, text }),
  });

  if (!res.ok) {
    throw new Error(`Slack error: ${res.status}`);
  }
}
