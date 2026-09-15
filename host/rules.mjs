import { parse_rules_json } from '../dist/core.mjs';

export function parseRuleFile(source) {
  if (typeof source !== 'string') throw new Error('规则内容必须是文字');
  const result = JSON.parse(parse_rules_json(source));
  if (result.error) throw new Error(result.error);
  return result.options;
}
