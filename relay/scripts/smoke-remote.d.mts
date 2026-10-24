export type SmokeSecrets = {
  adminToken: string;
  contentKey: string;
  readTokens: string[];
  writeToken: string;
};

export function runFiniteSmoke(
  originInput: string,
  secrets: SmokeSecrets,
  fetchImplementation?: typeof fetch,
  advanceTime?: (milliseconds: number) => Promise<void>,
): Promise<{ operations: number; passed: boolean }>;
