# 🌊 FluxForge (流光视界)

> **轻量级、沙箱规则驱动的跨媒体聚合浏览与播放平台**

---

## 📖 项目简介

**FluxForge (流光视界)** 是一款现代化的全栈多媒体聚合浏览平台。项目采用 **Monorepo** 架构，前端基于 Vue 3 + Tailwind CSS 4 + Naive UI + Pinia，后端依托 Hono.js 与 Node.js VM 沙箱构建。

FluxForge 的核心在于其**沙箱 JavaScript 动态规则引擎**。如同“流光”般顺畅无缝，FluxForge 打破了不同内容平台之间的界限，通过简短的规则脚本即可将视频、图集、小说等海量媒体源集中在一个纯净、优雅且无广告的视界中展示与播放。

---

## ✨ 核心特性

* ⚡ **全栈一体化单端口开发 (Unified Dev Server)**：前端与 Hono API 统一在 `http://localhost:5300` 运行，基于 `@hono/vite-dev-server` 享受毫秒级热重载，零跨域与代理开销。
* 🎨 **流光设计系统 (Flux Design System)**：全新设计“幻夜极光·翠影幽绿 (Emerald Aurora & Cyber Jade)”品牌主题色系，支持纯净翡翠白与深邃极夜墨晶双主题无感切换，深度定制 Naive UI 连续 Squircle 大圆角组件覆写与微拟态面板。
* ⚡ **沙箱规则驱动**：内置安全轻量的 JS 运行沙箱，支持编写/导入自定义规则（支持“发现页、搜索页、详情页”三段式解析脚本），轻松对接各类数据源。
* 🎬 **跨媒体全能体验**：
  * 📹 **视频播放**：集成现代 **ArtPlayer** 高清播放器，支持富文本剧情简介与同屏多列相关推荐。
  * 🖼️ **画廊图集**：4:3 网格画廊与大图瀑布流展厅。
  * 📖 **小说阅读**：沉浸式纯净阅读器体验。
* 🚀 **Vercel 一键云端部署**：配置标准 `vercel.json` 与 `api/index.ts`（基于 `hono/vercel` 的 Serverless Function 导出），支持前后端一体化无服务器部署上线。
* 📦 **规范 Monorepo 架构**：使用 `npm workspaces` 管理 `web`（前端）与 `server`（后端 API）子项目。

---

## 📁 目录结构

```text
flux-view/
├── web/                   # Vue 3 + Vite 网页前端
│   ├── src/
│   │   ├── components/    # 粒子背景、ArtPlayer 播放器、代码编辑器等组件
│   │   ├── stores/        # theme (双主题系统), tabs (多标签管理)
│   │   ├── utils/         # ruleService 规则存储与核心解析器
│   │   └── views/         # 首页、发现页、搜索、详情页与规则编辑器
│   └── package.json
├── server/                # Hono.js 后端 API 服务
│   ├── src/               # Hono 路由与规则沙箱执行器
│   └── package.json
├── api/                   # Vercel Serverless Function 入口
│   └── index.ts
├── vite.config.ts         # 根目录一体化全栈配置文件 (内嵌 Hono API 与 Vite SPA)
├── vercel.json            # Vercel 云端部署配置
├── package.json           # Monorepo 根节点 Workspace 配置文件
└── .gitignore             # 统一的 Git 忽略规则
```

---

## 🚀 快速开始

### 准备工作
* **Node.js** >= 20.0.0
* **npm** >= 10.0.0

### 安装与运行

```bash
# 1. 克隆仓库
git clone https://github.com/stevealvin/flux-view.git
cd flux-view

# 2. 安装根目录及所有工作区依赖
npm install

# 3. 启动全栈同端口开发服务 (统一端口: 5300)
npm run dev
```

启动成功后：
* **全栈一体化服务**：`http://localhost:5300`
* **API 健康检查**：`http://localhost:5300/api/health`

---

## ⚙️ 常用脚本命令

| 命令 | 描述 |
| :--- | :--- |
| `npm run dev` | 一键启动全栈一体化单端口开发服务器 (`http://localhost:5300`) |
| `npm run dev:all` | 同 `npm run dev` |
| `npm run dev:split` | 并发启动前端 Web (`web`) 和后端 API (`server`) 独立端口开发服务 |
| `npm run dev:web` | 仅启动前端 Vite 开发服务器 |
| `npm run dev:server` | 仅启动后端 Hono API 开发服务器 (独立端口 7300) |
| `npm run build` | 编译前端生产 bundle (`web/dist`) |
| `npm run build:web` | 仅编译前端 Web |
| `npm run build:server` | 仅编译后端 Server TypeScript |
| `npm run build:all` | 同时编译前端与后端服务 |

---

## ☁️ Vercel 部署

本项目支持通过 Vercel CLI 或 GitHub 仓库联动直接一键部署：

```bash
# 使用 Vercel CLI 一键部署
vercel
```

或在 Vercel 控制台中导入本项目：
* **Framework Preset**: `Vite`
* **Root Directory**: `./`
* **Build Command**: `npm run build:web`
* **Output Directory**: `web/dist`

---

## 📄 开源协议

[MIT License](LICENSE) © 2026 FluxView Team

