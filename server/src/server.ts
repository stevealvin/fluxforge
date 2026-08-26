import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import fs from 'node:fs';
import dotenv from 'dotenv';
import { serve } from '@hono/node-server';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// 加载 server/.env 环境变量
const serverEnvPath = resolve(__dirname, '../.env');
if (fs.existsSync(serverEnvPath)) {
  dotenv.config({ path: serverEnvPath });
} else {
  dotenv.config();
}

import { app } from './index.js';

const port = parseInt(process.env.PORT || '3300', 10);
console.log(`🚀 FluxView Standalone Hono Server running at http://localhost:${port}`);

serve({
  fetch: app.fetch,
  port,
});
