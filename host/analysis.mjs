import { analyze_inventory_json } from '../dist/core.mjs';

// The adapter only serializes scan metadata. All aggregation, exact byte
// arithmetic, ordering and recommendations are computed by MoonBit.
export function analyzeInventory(inventory) {
  if (!inventory || !Array.isArray(inventory.files) || !Array.isArray(inventory.duplicates)) {
    throw new Error('请先提供有效的扫描结果');
  }
  const result = JSON.parse(analyze_inventory_json(JSON.stringify({
    files: inventory.files,
    duplicates: inventory.duplicates,
  })));
  if (result.error) throw new Error(result.error);
  return result;
}
