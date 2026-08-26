import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import fs from 'node:fs';
import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// 仅在本地开发存在 server/.env 时加载 (Vercel 等云端平台直接读取注入的环境变量)
const serverEnvPath = resolve(__dirname, '../.env');
if (fs.existsSync(serverEnvPath)) {
  dotenv.config({ path: serverEnvPath });
}

// 固定读取 2 个核心远程环境变量
const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ [Supabase] 环境变量缺失: 请确保 SUPABASE_URL 与 SUPABASE_SERVICE_ROLE_KEY 已配置');
}

const supabase = createClient(supabaseUrl, supabaseKey);

/**
 * 格式化 Supabase 行记录为标准前端对象
 */
function formatRuleRow(row: any): any {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    type: row.type,
    version: row.version || '1.0.0',
    author: row.author || '管理员',
    description: row.description || '',
    baseUrl: row.base_url || '',
    code: row.code || '',
    enabled: row.enabled !== undefined ? (Number(row.enabled) === 1 ? 1 : 0) : 1,
    created_at: row.created_at,
    updated_at: row.updated_at
  };
}

export const ruleDb = {
  /**
   * 获取全部规则列表
   */
  async getAllRules(): Promise<any[]> {
    const { data, error } = await supabase
      .from('flux_rules')
      .select('*')
      .order('id', { ascending: true });

    if (error) {
      console.error('❌ [Supabase] 查询 flux_rules 失败:', error.message);
      throw error;
    }

    return (data || []).map(formatRuleRow);
  },

  /**
   * 根据 ID 获取单条规则详情
   */
  async getRuleById(id: number | string): Promise<any | null> {
    const { data, error } = await supabase
      .from('flux_rules')
      .select('*')
      .eq('id', Number(id))
      .maybeSingle();

    if (error) {
      console.error(`❌ [Supabase] 查询规则 [ID:${id}] 失败:`, error.message);
      throw error;
    }

    return formatRuleRow(data);
  },

  /**
   * 保存规则 (新增 / 更新)
   */
  async saveRule(data: any): Promise<any> {
    const payload = {
      name: data.name || '',
      type: data.type || 'video',
      version: data.version || '1.0.0',
      author: data.author || '管理员',
      description: data.description || '',
      base_url: data.baseUrl || data.base_url || '',
      code: data.code || '',
      enabled: data.enabled !== undefined ? (data.enabled ? 1 : 0) : 1,
      updated_at: new Date().toISOString()
    };

    if (data.id) {
      const { data: updated, error } = await supabase
        .from('flux_rules')
        .update(payload)
        .eq('id', Number(data.id))
        .select('*')
        .single();

      if (error) {
        console.error(`❌ [Supabase] 更新规则 [ID:${data.id}] 失败:`, error.message);
        throw error;
      }
      return formatRuleRow(updated);
    } else {
      const { data: inserted, error } = await supabase
        .from('flux_rules')
        .insert([{ ...payload, created_at: new Date().toISOString() }])
        .select('*')
        .single();

      if (error) {
        console.error('❌ [Supabase] 插入新规则失败:', error.message);
        throw error;
      }
      return formatRuleRow(inserted);
    }
  },

  /**
   * 删除规则
   */
  async deleteRule(id: number | string): Promise<boolean> {
    const { error } = await supabase
      .from('flux_rules')
      .delete()
      .eq('id', Number(id));

    if (error) {
      console.error(`❌ [Supabase] 删除规则 [ID:${id}] 失败:`, error.message);
      throw error;
    }
    return true;
  },

  /**
   * 切换规则启用状态
   */
  async toggleRuleEnabled(id: number | string, enabled: number): Promise<boolean> {
    const { error } = await supabase
      .from('flux_rules')
      .update({
        enabled: enabled ? 1 : 0,
        updated_at: new Date().toISOString()
      })
      .eq('id', Number(id));

    if (error) {
      console.error(`❌ [Supabase] 更新规则状态 [ID:${id}] 失败:`, error.message);
      throw error;
    }
    return true;
  }
};


