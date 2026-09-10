export interface Rule {
  id: number;
  name: string;
  description: string;
  type: string;
  code: string;
  baseUrl: string;
  author: string;
  version: string;
  enabled: number;
  created_at?: string;
  updated_at?: string;
}
