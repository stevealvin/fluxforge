import { defineConfig, loadConfigFromFile, mergeConfig } from 'vite';
import devServer from '@hono/vite-dev-server';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * 根目录全栈一体化 Vite 配置文件 (Unified Dev Server)
 * 
 * 核心原理：
 * 1. 动态加载 web/vite.config.ts 中的子配置 (Vue 3、Tailwind CSS、路径别名等)
 * 2. 挂载 @hono/vite-dev-server 中间件直接加载 server/src/index.ts
 * 3. 前端与 API 统一在 5300 端口运行，享受毫秒级热重载，零跨域与代理开销
 */
export default defineConfig(async (configEnv) => {
  const rootDir = __dirname;
  const webPath = path.resolve(rootDir, 'web');
  const webConfigPath = path.resolve(webPath, 'vite.config.ts');

  // 1. 动态加载 web/vite.config.ts 现有的前端配置
  const loaded = await loadConfigFromFile(configEnv, webConfigPath, webPath);
  const baseWebConfig = loaded?.config || {};

  // 2. 深度合并配置：指定前端 root 并注入 Hono devServer 插件
  return mergeConfig(baseWebConfig, {
    root: webPath,
    plugins: [
      devServer({
        entry: path.resolve(rootDir, 'server/src/index.ts'), // 挂载后端 Hono API 入口
        // 核心规则：仅 /api/* 后端接口由 Hono 处理，其余所有前端路由、页面与静态资源均交由 Vite SPA 渲染
        exclude: [
          /^(?!\/api)(\/.*|$)/,
        ],
      }),
    ],
    server: {
      host: true,
      port: 5300,       // 一体化单端口开发服务 (5300)
      strictPort: true, // 锁定端口防乱跳
    },
  });
});
