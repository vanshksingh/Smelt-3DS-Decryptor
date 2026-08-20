/**
 * Smelt Next — System Constants & Enums
 */

export const ROM_STATUS = {
  QUEUED: 'queued',
  ANALYZING: 'analyzing',
  READY: 'ready',
  FORGING: 'forging',
  COMPLETED: 'completed',
  ERROR: 'error'
};

export const ANALYSIS_STATE = {
  CLEAN: 'clean',
  PATCH: 'patch',
  DECRYPT: 'decrypt',
  CIA: 'cia',
  INVALID: 'invalid'
};

export const OUTPUT_FORMAT = {
  SAME: 'same',
  CCI: 'cci',
  THREE_DS: '3ds'
};

export const LOG_LEVEL = {
  INFO: 'info',
  SUCCESS: 'success',
  WARN: 'warn',
  ERROR: 'error'
};
