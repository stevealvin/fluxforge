import { ruleDb } from '../db/index.js';
import { sandboxService } from './sandbox.service.js';

export interface RuleEntity {
  id?: number;
  name: string;
  type: string;
  version?: string;
  author?: string;
  description?: string;
  baseUrl?: string;
  base_url?: string;
  code: string;
  enabled?: number | boolean;
  created_at?: string;
  updated_at?: string;
}

export const ruleService = {
  /**
   * 获取所有规则列表
   */
  async getAllRules(): Promise<any[]> {
    return ruleDb.getAllRules();
  },

  /**
   * 根据 ID 查询规则详情
   */
  async getRuleById(id: number | string): Promise<any | null> {
    return ruleDb.getRuleById(id);
  },

  /**
   * 创建新规则
   */
  async createRule(payload: RuleEntity): Promise<any> {
    if (!payload.name) {
      throw new Error('规则名称不能为空');
    }
    if (!payload.code) {
      throw new Error('规则脚本代码不能为空');
    }
    return ruleDb.saveRule(payload);
  },

  /**
   * 更新已有规则
   */
  async updateRule(id: number | string, payload: Partial<RuleEntity>): Promise<any> {
    const existing = await ruleDb.getRuleById(id);
    if (!existing) {
      return null;
    }
    return ruleDb.saveRule({ ...payload, id: Number(id) });
  },

  /**
   * 删除指定规则
   */
  async deleteRule(id: number | string): Promise<boolean> {
    return ruleDb.deleteRule(id);
  },

  /**
   * 切换规则启用状态
   */
  async toggleRuleEnabled(id: number | string, enabled: number | boolean): Promise<boolean> {
    const numEnabled = enabled === true || Number(enabled) === 1 ? 1 : 0;
    return ruleDb.toggleRuleEnabled(id, numEnabled);
  },

  /**
   * 生产环境根据规则 ID 执行生命周期动作
   */
  async executeRuleById(id: number | string, action: string, params: Record<string, any> = {}): Promise<any> {
    const targetRule = await ruleDb.getRuleById(id);
    if (!targetRule) {
      throw new Error(`规则 [ID:${id}] 不存在或已被删除`);
    }

    const { result } = await sandboxService.executeRule({
      code: targetRule.code,
      action,
      params,
      baseUrl: targetRule.baseUrl || targetRule.base_url
    });

    return result;
  }
};
