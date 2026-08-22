import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import fs from 'node:fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const rulesFilePath = resolve(__dirname, '../resources/rules.json');

function readRulesFile(): any[] {
  try {
    if (fs.existsSync(rulesFilePath)) {
      const content = fs.readFileSync(rulesFilePath, 'utf-8').trim();
      if (content) {
        return JSON.parse(content);
      }
    }
  } catch (err) {
    console.error('❌ [ruleDb] 读取 rules.json 失败:', err);
  }
  return [];
}

function writeRulesFile(rules: any[]): void {
  const dir = dirname(rulesFilePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(rulesFilePath, JSON.stringify(rules, null, 2), 'utf-8');
}

export const ruleDb = {
  async getAllRules(): Promise<any[]> {
    return readRulesFile();
  },

  async getRuleById(id: number | string): Promise<any | null> {
    const numId = Number(id);
    const rules = readRulesFile();
    const found = rules.find((r) => Number(r.id) === numId || String(r.id) === String(id));
    return found || null;
  },

  async saveRule(data: any): Promise<any> {
    const rules = readRulesFile();
    const now = new Date().toISOString();

    const payload = {
      name: data.name,
      type: data.type,
      version: data.version,
      author: data.author,
      description: data.description,
      baseUrl: data.baseUrl,
      code: data.code,
      enabled: data.enabled ? 1 : 0,
      updated_at: now
    };

    if (data.id) {
      const numId = Number(data.id);
      const index = rules.findIndex((r) => Number(r.id) === numId || String(r.id) === String(data.id));

      if (index !== -1) {
        const existing = rules[index];
        const updated = {
          ...existing,
          ...payload,
          id: numId,
          created_at: existing.created_at || now
        };
        rules[index] = updated;
        writeRulesFile(rules);
        return updated;
      }
      throw new Error(`Rule [ID:${data.id}] not found to update`);
    } else {
      const nextId =
        rules.length > 0 ? Math.max(...rules.map((r) => Number(r.id) || 0)) + 1 : 1;

      const newRule = {
        id: nextId,
        ...payload,
        created_at: now
      };
      rules.push(newRule);
      writeRulesFile(rules);
      return newRule;
    }
  },

  async deleteRule(id: number | string): Promise<boolean> {
    const numId = Number(id);
    const rules = readRulesFile();
    const filtered = rules.filter((r) => Number(r.id) !== numId && String(r.id) !== String(id));

    if (filtered.length < rules.length) {
      writeRulesFile(filtered);
      return true;
    }
    return false;
  },

  async toggleRuleEnabled(id: number | string, enabled: number): Promise<boolean> {
    const numId = Number(id);
    const rules = readRulesFile();
    const rule = rules.find((r) => Number(r.id) === numId || String(r.id) === String(id));

    if (rule) {
      rule.enabled = enabled ? 1 : 0;
      rule.updated_at = new Date().toISOString();
      writeRulesFile(rules);
      return true;
    }
    return false;
  }
};
