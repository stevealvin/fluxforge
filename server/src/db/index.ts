import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import fs from 'node:fs';
import dotenv from 'dotenv';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// 本地开发环境加载 server/.env 文件
const envPath = resolve(__dirname, '../../.env');
if (fs.existsSync(envPath)) {
  dotenv.config({ path: envPath });
} else {
  const fallbackEnv = resolve(__dirname, '../.env');
  if (fs.existsSync(fallbackEnv)) {
    dotenv.config({ path: fallbackEnv });
  }
}

const supabaseUrl =
  process.env.SUPABASE_URL ||
  'https://ktyhycnfiketodvbjncy.supabase.co';

const supabaseKey =
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt0eWh5Y25maWtldG9kdmJqbmN5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NTUwNzgxNiwiZXhwIjoyMTAxMDgzODE2fQ.xJTkF4wau9gj_Tlx1FmNCSLXTN1CpfhmX-eQLiTQjCw';

/**
 * 获取 Supabase SDK 单例客户端 (禁用无用 Session 轮询以保障高并发与 Serverless 稳定性)
 */
export const supabase: SupabaseClient = createClient(supabaseUrl, supabaseKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false
  }
});

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
    const now = new Date().toISOString();
    const payload = {
      name: data.name || '',
      type: data.type || 'video',
      version: data.version || '1.0.0',
      author: data.author || '管理员',
      description: data.description || '',
      base_url: data.baseUrl || data.base_url || '',
      code: data.code || '',
      enabled: data.enabled !== undefined ? (Number(data.enabled) === 1 ? 1 : 0) : 1,
      updated_at: now
    };

    if (data.id) {
      const { data: updated, error } = await supabase
        .from('flux_rules')
        .update(payload)
        .eq('id', Number(data.id))
        .select('*')
        .maybeSingle();

      if (error) {
        console.error(`❌ [Supabase] 更新规则 [ID:${data.id}] 失败:`, error.message);
        throw error;
      }
      return formatRuleRow(updated || { ...payload, id: Number(data.id) });
    } else {
      const { data: inserted, error } = await supabase
        .from('flux_rules')
        .insert([{ ...payload, created_at: now }])
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
        enabled: Number(enabled) === 1 ? 1 : 0,
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
