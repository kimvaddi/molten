interface SafetyResult {
  safe: boolean;
  reason?: string;
}

const BLOCKED = [
  { p: /ignore.*previous.*instructions/i, r: "Prompt injection" },
  { p: /system.*prompt/i, r: "Prompt extraction" },
  { p: /jailbreak/i, r: "Jailbreak attempt" },
  { p: /\b(password|api.?key|secret)\s*[:=]/i, r: "Sensitive data" },
];

export async function checkSafety(text: string): Promise<SafetyResult> {
  if (text.length > 4000) {
    return { safe: false, reason: "Input too long" };
  }

  for (const { p, r } of BLOCKED) {
    if (p.test(text)) {
      return { safe: false, reason: r };
    }
  }

  return { safe: true };
}

export function sanitizeOutput(text: string): string {
  return text.replace(/\b[A-Za-z0-9]{32,}\b/g, "[REDACTED]");
}
