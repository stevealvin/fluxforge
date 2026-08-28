import { Hono } from 'hono';
import { corsMiddleware, loggerMiddleware } from './middlewares/index.js';
import rulesRouter from './routes/rules.js';

export const app = new Hono();

// 1. 中间件：日志与跨域支持
app.use('*', loggerMiddleware);
app.use('*', corsMiddleware);

// 2. 根路径与健康检查
app.get('/', (c) => {
  return c.json({
    status: 'ok',
    service: 'flux-view-api',
    time: new Date().toISOString(),
  });
});

// 3. 全部路由统一挂载在 /api 下
const api = new Hono();
api.route('/rules', rulesRouter);
api.get('/health', (c) => c.json({ status: 'ok', time: new Date().toISOString() }));
api.get('/', (c) => c.json({ status: 'ok', message: 'FluxView Rules Engine API is running' }));

app.route('/api', api);

export default app;
