import type { DanmakuMessageJson } from '../protocol';

/** Connector 契约与注册表（独立模块，避免 hub ↔ connector 循环依赖）。 */

export interface DanmakuConnector {
  start(): Promise<void>;
  stop(): void;
}

export type DanmakuSender = (msg: DanmakuMessageJson) => void;

export type ConnectorFactory = (roomId: string, danmakuData: unknown, send: DanmakuSender) => DanmakuConnector;

const connectorFactories = new Map<string, ConnectorFactory>();

export function registerConnector(platform: string, factory: ConnectorFactory): void {
  connectorFactories.set(platform, factory);
}

export function getConnectorFactory(platform: string): ConnectorFactory | undefined {
  return connectorFactories.get(platform);
}
