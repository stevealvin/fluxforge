# AGENTS.md

## Project overview

FluxForge (流光视界) — 轻量级、沙箱规则驱动的跨媒体聚合浏览与播放平台（全栈 Monorepo 架构）。
- **server**: 基于 Hono.js + Node.js VM 沙箱的高性能规则执行微服务，内置 `better-sqlite3`、`cheerio` 与 `axios` 爬虫解析沙箱环境。
- **web**: 基于 Vue 3 + Naive UI (`naive-ui`) + Tailwind CSS 4 + Pinia 的现代化高质感跨媒体浏览与播放系统，支持极夜曜黑与纯净视界浅色双主题，支持多标签页无缝切换、实时规则调试与 Monaco Code Editor 沙箱。

## Commands

```bash
npm run dev           # 根目录全栈一体化单端口模式 (Vite + @hono/vite-dev-server 统一在 5300 端口运行，零跨域秒级热更)
npm run dev:all       # 同上 (统一在 5300 端口)
npm run dev:split     # 并发独立启动后端 Hono API 与前端 Vite 开发服务器
npm run dev:server    # 单独启动后端 Hono API 服务 (独立端口 7300)
npm run dev:web       # 单独启动前端 Vite 开发服务器
npm run build         # 构建前端生产包 (Vite Bundle)
npm run build:web     # 仅构建前端生产包
npm run build:server  # 仅编译后端 TypeScript 服务
npm run start         # 启动后端生产服务
```

## Stack & toolchain

- **Monorepo**: npm workspaces (`web`, `server`)
- **Backend (`server`)**: Node.js + TypeScript + Hono + `@hono/node-server` + better-sqlite3 + VM Sandbox
- **Frontend (`web`)**: Vue 3.5 + `<script setup>` SFCs + TypeScript + Vite + Tailwind CSS 4 + Naive UI (`naive-ui`) + Pinia + Vue Router + Monaco Editor + ArtPlayer
- **Deployment**: Vercel (`vercel.json` + `api/index.ts` Serverless Function)

## Architecture

```
flux-view/
  package.json        # Monorepo 根配置与一键启动脚本
  vite.config.ts      # 根目录一体化全栈配置文件 (动态继承 web 并内嵌 server API)
  vercel.json         # Vercel 一键部署配置文件 (Vite SPA + Serverless Rewrites)
  api/
    index.ts          # Vercel Serverless Function 入口 (hono/vercel handle)
  server/             # Hono 后端服务 (独立端口 7300)
    src/
      index.ts        # Hono 应用入口 (basePath('/api'), 兼容独立运行与 Vite 挂载)
      server.ts       # 独立 Node.js 服务入口
      db.ts           # SQLite 数据库连接与表结构自动迁移
      routes/         # 业务路由与沙箱解析器 (rules.ts)
    resources/        # SQLite 数据库持久化存储
  web/                # Naive UI 前端 SPA (端口 5300)
    public/           # 静态资源 (icon.svg 等)
    src/
      stores/         # theme, tabs
      components/     # ArtPlayer, CodeEditor, ParticlesBg
      views/          # home, search, module-view (video/picture/novel), rules, gallery
      assets/css/     # Tailwind 4 与流光双主题样式 (main.css)
      utils/          # ruleService, http
      main.ts         # 前端入口
```

## Key quirks

- **Unified Single Port**: 开发环境下，根目录 `vite.config.ts` 通过 `@hono/vite-dev-server` 挂载 `server/src/index.ts`，前端与 API 统一在 `http://localhost:5300` 运行，无需代理即可访问 `/api/*`。
- **Theme System**: 基于 Pinia + `@vueuse/core` (`stores/theme.ts`) 实现浅色（纯净星暮白）与深色（曜夜极光翡翠）双主题，并在 `App.vue` 中注入 Naive UI 深度 Theme Overrides（以极光幽绿 `#059669` / `#10b981` 为品牌主色）。
- **Rule Sandbox**: 规则脚本在 `server/src/routes/rules.ts` 的 Node.js `vm` 沙箱中执行，支持 CommonJS / ES Module 自动转译，内置注入 `axios`、`cheerio` 等解析库。
- **Vercel Serverless**: 根目录 `api/index.ts` 导出 `handle(app)`，部署至 Vercel 时自动接管 `/api/*` 请求。

## 🛑 STRICT EXECUTION RULES (人类用户的最高硬性指令)
- 你编写的代码，要写清楚关键中文注释，方便你理解，也方便我理解
- 我写的代码你要检查逻辑并提示我或者直接修改
- 你每次修改时要说清楚你的理解，并优化我提出的建议，尝试更好的方案
- 你每次修改时检查有没有同名方法，或者类似的逻辑有没有被其他地方调用，或者重复定义
- 代码规范你参考下项目其他地方，并且有不规范的地方指出来，看看影响大不大，是否应该改正
- 检查下项目有没有说明书，然后查看说明书了解整个项目和注意事项，同时后续记录修改日志
- 必须完全以简体中文来进行内部推理和思考过程，这是一项严格的规定
- 每次修改代码后不需要进行 Git 提交或推送，除非人类用户明确发出要求
