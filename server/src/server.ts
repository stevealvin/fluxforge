import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import fs from 'node:fs';
import dotenv from 'dotenv';
import { serve } from '@hono/node-server';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// 服务端严格只加载服务端根目录下的 .env 文件 (server/.env)
const serverEnvPath = resolve(__dirname, '../.env');
if (fs.existsSync(serverEnvPath)) {
  dotenv.config({ path: serverEnvPath });
}

import { app } from './index.js';

const port = parseInt(process.env.PORT || '3300', 10);
console.log(`🚀 FluxView Standalone Hono Server running at http://localhost:${port}`);

serve({
  fetch: app.fetch,
  port,
});
