import { addPluginListener, invoke } from '@tauri-apps/api/core';
import type { LayoutSnapshot, NativeSource } from './types.js';

/** Explicit iOS adapter. Browser/desktop/Android callers use the CSS observer instead. */
export function createTauriNativeSource(): NativeSource {
  const command = (name: string) => `plugin:iphone-duo-layout|${name}`;
  return {
    async subscribe(listener) {
      const subscription = await addPluginListener<LayoutSnapshot>('iphone-duo-layout', 'change', listener);
      try { await invoke(command('start')); }
      catch (error) { await subscription.unregister(); throw error; }
      return async () => {
        try { await subscription.unregister(); }
        finally { await invoke(command('stop')); }
      };
    },
    read: () => invoke<LayoutSnapshot | null>(command('get_snapshot')),
  };
}
