type LogLevel = "debug" | "info" | "warn" | "error";

const LEVELS: Record<LogLevel, number> = { debug: 0, info: 1, warn: 2, error: 3 };
const currentLevel = (process.env.LOG_LEVEL as LogLevel) || "info";

function log(level: LogLevel, message: string, meta?: object): void {
  if (LEVELS[level] < LEVELS[currentLevel]) return;
  
  const entry = {
    timestamp: new Date().toISOString(),
    level: level.toUpperCase(),
    message,
    ...meta,
  };
  
  const output = JSON.stringify(entry);
  
  switch (level) {
    case "error":
      console.error(output);
      break;
    case "warn":
      console.warn(output);
      break;
    default:
      console.log(output);
  }
}

export const logger = {
  debug: (msg: string, meta?: object) => log("debug", msg, meta),
  info: (msg: string, meta?: object) => log("info", msg, meta),
  warn: (msg: string, meta?: object) => log("warn", msg, meta),
  error: (msg: string, meta?: object) => log("error", msg, meta),
};
