import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { mockIPC, clearMocks } from '@tauri-apps/api/mocks';
import { createTauriNativeSource } from '../dist/tauri.js';

test('official Tauri IPC mock verifies listener-before-start, read and cleanup command names', async () => {
  const dom = new JSDOM(''), previous = globalThis.window;
  globalThis.window = dom.window;
  const calls = [], output = [];
  let channel;
  const snapshot = { revision: 1, width: 466, height: 678, safeArea: { top: 0, right: 84, bottom: 34, left: 0 },
    source: 'native', foldState: 'unknown', regions: [] };
  try {
    mockIPC((command, args) => {
      calls.push(command);
      if (command.endsWith('|register_listener')) channel = args.handler;
      if (command.endsWith('|start')) channel.onmessage(snapshot);
      if (command.endsWith('|get_snapshot')) return snapshot;
    });
    const source = createTauriNativeSource(), remove = await source.subscribe(value => output.push(value));
    assert.deepEqual(output, [snapshot]);
    assert.deepEqual(await source.read(), snapshot);
    await remove();
    assert.deepEqual(calls, ['register_listener', 'start', 'get_snapshot', 'remove_listener', 'stop'].map(s => `plugin:iphone-duo-layout|${s}`));
  } finally { clearMocks(); globalThis.window = previous; dom.window.close(); }
});
