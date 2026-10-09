import { requireNativeView } from 'expo';
import { forwardRef, useCallback, useImperativeHandle, useMemo, useRef, type Ref } from 'react';
import type { NativeSyntheticEvent } from 'react-native';
import type { ElpianViewHandle, ElpianViewProps } from './types';

interface NativeProps {
  ref?: Ref<NativeRef>;
  kind: string;
  optionsJson: string;
  onElpianEvent: (e: NativeSyntheticEvent<{ event: string; payloadJson: string }>) => void;
  style?: ElpianViewProps['style'];
}

interface NativeRef {
  call(method: string, argsJson: string): Promise<string>;
  close(): Promise<void>;
}

const NativeElpianView = requireNativeView<NativeProps>('Elpian');

function parse(json: string): unknown {
  try {
    return JSON.parse(json);
  } catch {
    return json;
  }
}

/**
 * Renders an Elpian session with the platform's native core: Android Views
 * (Kotlin) and UIKit (Swift). No JavaScript runs on the render path; JS only
 * runs inside sandboxed QuickJS / JavaScriptCore guests for JS mini apps.
 */
export const ElpianView = forwardRef<ElpianViewHandle, ElpianViewProps>(function ElpianView(props, ref) {
  const { kind, options, onEvent, onReady, onError, style } = props;
  const nativeRef = useRef<NativeRef>(null);
  const optionsJson = useMemo(() => JSON.stringify(options ?? {}), [options]);

  useImperativeHandle(
    ref,
    () => ({
      async call(method: string, ...args: unknown[]) {
        const view = nativeRef.current;
        if (!view) throw new Error('ElpianView is not mounted');
        return parse(await view.call(method, JSON.stringify(args)));
      },
      async close() {
        await nativeRef.current?.close();
      },
    }),
    [],
  );

  const handle = useCallback(
    (e: NativeSyntheticEvent<{ event: string; payloadJson: string }>) => {
      const { event, payloadJson } = e.nativeEvent;
      const payload = parse(payloadJson);
      onEvent?.({ event, payload });
      if (event === 'ready') onReady?.();
      if (event === 'error') {
        const p = payload as { message?: string } | string | null;
        onError?.(typeof p === 'string' ? p : p?.message ?? JSON.stringify(p));
      }
    },
    [onEvent, onReady, onError],
  );

  return <NativeElpianView ref={nativeRef} kind={kind} optionsJson={optionsJson} onElpianEvent={handle} style={style} />;
});
