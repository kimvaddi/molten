/**
 * OpenClaw Gateway Protocol Types
 * Based on: https://docs.openclaw.ai/concepts/architecture
 */

// Wire protocol message types
export type MessageType = "req" | "res" | "event";

export interface RequestMessage {
  type: "req";
  id: string;
  method: string;
  params?: Record<string, unknown>;
}

export interface ResponseMessage {
  type: "res";
  id: string;
  ok: boolean;
  payload?: unknown;
  error?: {
    code: string;
    message: string;
  };
}

export interface EventMessage {
  type: "event";
  event: string;
  payload: unknown;
  seq?: number;
  stateVersion?: number;
}

export type GatewayMessage = RequestMessage | ResponseMessage | EventMessage;

// Connect handshake
export interface ConnectParams {
  version: string;
  deviceId: string;
  deviceName: string;
  role?: "client" | "node";
  auth?: {
    token?: string;
    password?: string;
  };
  caps?: string[];
  commands?: string[];
}

export interface ConnectResponse {
  ok: boolean;
  payload?: {
    deviceToken?: string;
    presence?: PresenceState;
    health?: HealthState;
  };
  error?: {
    code: string;
    message: string;
  };
}

// Presence and health
export interface PresenceState {
  gateway: "online" | "offline";
  channels: Record<string, "connected" | "disconnected">;
}

export interface HealthState {
  status: "healthy" | "degraded" | "unhealthy";
  uptime: number;
  version: string;
}

// Agent request/response
export interface AgentRequest {
  message: string;
  sessionId?: string;
  channel?: string;
  userId?: string;
  thinking?: "off" | "minimal" | "low" | "medium" | "high" | "xhigh";
  model?: string;
  idempotencyKey?: string;
}

export interface AgentResponse {
  runId: string;
  status: "accepted" | "running" | "completed" | "failed";
  message?: string;
  summary?: string;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

// Agent streaming events
export interface AgentStreamEvent {
  runId: string;
  type: "text" | "tool_use" | "tool_result" | "error" | "done";
  content?: string;
  toolName?: string;
  toolInput?: Record<string, unknown>;
  toolResult?: unknown;
  error?: string;
}

// Send message request
export interface SendRequest {
  channel: string;
  to: string;
  message: string;
  idempotencyKey?: string;
}

// Gateway configuration
export interface OpenClawConfig {
  enabled: boolean;
  gatewayUrl: string;
  token?: string;
  deviceId: string;
  deviceName: string;
  model?: string;
  thinking?: "off" | "minimal" | "low" | "medium" | "high";
}

// Skills
export interface Skill {
  name: string;
  description: string;
  location: string;
  enabled: boolean;
}

export interface SkillsListResponse {
  skills: Skill[];
}
