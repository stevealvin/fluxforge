import { logger } from 'hono/logger';

/**
 * 全局请求日志中间件
 */
export const loggerMiddleware = logger();
