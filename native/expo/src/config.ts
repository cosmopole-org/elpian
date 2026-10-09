/** Options for the web host (`@elpian/web`). */
export interface ElpianWebConfig {
  /**
   * URL of the `@elpian/web` assets folder (fonts/, runtime/), with a trailing
   * slash. Defaults to `/elpian/`: copy the assets into the app's `public/`
   * folder with `npx elpian-expo-web-assets` (writes `public/elpian`).
   */
  assetBase?: string;
}

/**
 * Configures the web host; call it before the first `<ElpianView>` mounts.
 * A no-op on Android and iOS, where the native libraries ship their assets.
 */
export function configureElpianWeb(_config: ElpianWebConfig): void {}
