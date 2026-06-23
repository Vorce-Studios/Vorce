import type { RunHierarchyData } from './types';

export interface RunHierarchyOptions {
  vorceRoot?: string;
  configPath?: string;
  runStatesDir?: string;
  manifestPath?: string;
}

export declare function getRunTopologyManifest(manifestPath?: string): unknown;
export declare function getRunHierarchy(options?: RunHierarchyOptions): RunHierarchyData;
