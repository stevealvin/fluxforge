import { Hono } from 'hono';
import { ruleService, crawlerService, sandboxService } from '../services/index.js';

const rules = new Hono();

/**
 * GET /api/rules -> 获取全部规则列表 (RESTful 200)
 */
rules.get('/', async (c) => {
  try {
    const list = await ruleService.getAllRules();
    return c.json(list);
  } catch (error: any) {
    return c.json({ message: error.message || 'Failed to fetch rules' }, 500);
  }
});

/**
 * GET /api/rules/:id -> 获取单条规则详情 (RESTful 200 / 404)
 */
rules.get('/:id', async (c) => {
  try {
    const id = c.req.param('id');
    const rule = await ruleService.getRuleById(id);
    if (!rule) {
      return c.json({ message: `Rule [ID:${id}] not found` }, 404);
    }
    return c.json(rule);
  } catch (error: any) {
    return c.json({ message: error.message || 'Failed to fetch rule' }, 500);
  }
});

/**
 * POST /api/rules -> 创建新规则 (RESTful 201)
 */
rules.post('/', async (c) => {
  try {
    const body = await c.req.json();
    const created = await ruleService.createRule(body);
    return c.json(created, 201);
  } catch (error: any) {
    return c.json({ message: error.message || 'Failed to create rule' }, 400);
  }
});

/**
 * PUT /api/rules/:id -> 全量/增量更新规则 (RESTful 200 / 404)
 */
rules.put('/:id', async (c) => {
  try {
    const id = c.req.param('id');
    const body = await c.req.json();
    const updated = await ruleService.updateRule(id, body);
    if (!updated) {
      return c.json({ message: `Rule [ID:${id}] not found` }, 404);
    }
    return c.json(updated);
  } catch (error: any) {
    return c.json({ message: error.message || 'Failed to update rule' }, 500);
  }
});

/**
 * DELETE /api/rules/:id -> 删除规则 (RESTful 204 No Content)
 */
rules.delete('/:id', async (c) => {
  try {
    const id = c.req.param('id');
    const success = await ruleService.deleteRule(id);
    if (!success) {
      return c.json({ message: `Rule [ID:${id}] not found` }, 404);
    }
    return c.body(null, 204);
  } catch (error: any) {
    return c.json({ message: error.message || 'Failed to delete rule' }, 500);
  }
});

/**
 * PATCH /api/rules/:id/toggle -> 切换规则启用状态 (RESTful 200)
 */
rules.patch('/:id/toggle', async (c) => {
  try {
    const id = c.req.param('id');
    const body = await c.req.json();
    const enabled = body.enabled ? 1 : 0;
    await ruleService.toggleRuleEnabled(id, enabled);
    return c.json({ enabled });
  } catch (error: any) {
    return c.json({ message: error.message || 'Failed to toggle rule' }, 500);
  }
});

/**
 * POST /api/rules/fetch-page -> 抓取采样数据并自动转换编码 (RESTful 200)
 */
rules.post('/fetch-page', async (c) => {
  try {
    const body = await c.req.json();
    const result = await crawlerService.fetchPage(body.url, body.headers);
    return c.json(result);
  } catch (error: any) {
    return c.json({ message: error.message || 'Failed to fetch page' }, 500);
  }
});

/**
 * POST /api/rules/run -> 开发者沙箱调试：直接传入临时 code 脚本执行 (返回结果 + logs 日志)
 */
rules.post('/run', async (c) => {
  try {
    const body = await c.req.json();
    if (!body.code) {
      return c.json({ message: '缺少代码参数 (Missing code)' }, 400);
    }

    const output = await sandboxService.executeRule({
      code: body.code,
      action: body.action || 'discovery',
      params: body.params || {},
      baseUrl: body.baseUrl
    });

    return c.json(output);
  } catch (error: any) {
    return c.json(
      {
        message: error.message || 'Sandbox execution failed',
        stack: error.stack,
        logs: []
      },
      500
    );
  }
});

/**
 * 生产环境执行规则处理器
 */
const handleExecuteProductionRule = async (c: any, ruleId: number | string, action: string, params: any) => {
  try {
    const result = await ruleService.executeRuleById(ruleId, action, params);
    return c.json(result);
  } catch (error: any) {
    const isNotFound = error.message?.includes('不存在');
    return c.json(
      { message: error.message || 'Rule execution failed' },
      isNotFound ? 404 : 500
    );
  }
};

/**
 * POST /api/rules/:id/execute -> 生产环境执行指定 ID 的已入库规则 (RESTful 资源动作)
 */
rules.post('/:id/execute', async (c) => {
  const id = c.req.param('id');
  const body = await c.req.json().catch(() => ({}));
  return handleExecuteProductionRule(c, id, body.action || 'discovery', body.params || {});
});

/**
 * POST /api/rules/execute -> 生产环境通过 Body { ruleId } 执行已入库规则 (兼容传统模式)
 */
rules.post('/execute', async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const ruleId = body.ruleId || body.id;
  if (!ruleId) {
    return c.json({ message: '请提供规则 ID (Missing ruleId)' }, 400);
  }
  return handleExecuteProductionRule(c, ruleId, body.action || 'discovery', body.params || {});
});

export default rules;
