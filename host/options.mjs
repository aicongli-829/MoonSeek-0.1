import { configuration_defaults_json, validate_options_json, validate_template_json } from '../dist/core.mjs';

function moonResult(fn, input) {
  const result = JSON.parse(fn(typeof input === 'string' ? input : JSON.stringify(input)));
  if (result.error) throw new Error(result.error);
  return result;
}

const defaults = moonResult(configuration_defaults_json, '{}');
export const defaultOptions = defaults.defaultOptions;
export const builtInTemplates = defaults.builtInTemplates;

export function validateOptions(input = {}) {
  return moonResult(validate_options_json, input).options;
}

export function validateTemplate(input) {
  return moonResult(validate_template_json, input).template;
}
