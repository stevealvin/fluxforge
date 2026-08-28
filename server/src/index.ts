import { Hono } from 'hono';
import { corsMiddleware, loggerMiddleware } from './middlewares/index.js';
import rulesRouter from './routes/rules.js';

// 1. 创建全局统一带有 /api 前缀的 Hono 实例
export const app = new Hono().basePath('/api');

// 2. 中间件：日志与跨域支持
app.use('*', loggerMiddleware);
app.use('*', corsMiddleware);

// 3. 健康检查端点 (位于 /api/health)
app.get('/health', (c) => {
  return c.json({
    status: 'ok',
    service: 'flux-view-api',
    time: new Date().toISOString(),
  });
});

// 4. 挂载规则引擎业务路由 (自动处于 /api/rules/*)
app.route('/rules', rulesRouter);

export default app;
