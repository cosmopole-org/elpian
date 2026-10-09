import { installElpian } from '@elpian/web';
import type { ElpianWebConfig } from './config';

export type { ElpianWebConfig } from './config';

/**
 * Metro serves no files next to the bundled @elpian/web module, so the
 * assets come from the app's public/ folder (see `npx elpian-expo-web-assets`).
 */
let config: ElpianWebConfig = { assetBase: '/elpian/' };
let installed = false;

export function configureElpianWeb(next: ElpianWebConfig): void {
  if (installed) {
    console.warn('@elpian/expo: configureElpianWeb() called after the first ElpianView mounted; it has no effect');
    return;
  }
  config = { ...config, ...next };
}

/** Installs the web platform with the configured assets (once). */
export function ensureElpianWeb(): void {
  if (installed) return;
  installed = true;
  const assetBase = new URL(config.assetBase ?? '/elpian/', location.href).toString();
  installElpian({ assetBase });
}
