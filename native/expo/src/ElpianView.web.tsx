import { mountElpian, type ElpianSession } from '@elpian/web';
import { forwardRef, useEffect, useImperativeHandle, useMemo, useRef } from 'react';
import { View } from 'react-native';
import type { ElpianViewHandle, ElpianViewProps } from './types';

/** Web: the DOM host (@elpian/web) mounted in the view's element. */
export const ElpianView = forwardRef<ElpianViewHandle, ElpianViewProps>(function ElpianView(props, ref) {
  const { kind, options, style } = props;
  const host = useRef<View>(null);
  const session = useRef<ElpianSession | null>(null);
  const callbacks = useRef(props);
  callbacks.current = props;
  const optionsJson = useMemo(() => JSON.stringify(options ?? {}), [options]);

  useImperativeHandle(
    ref,
    () => ({
      async call(method: string, ...args: unknown[]) {
        if (!session.current) throw new Error('ElpianView is not mounted');
        return session.current.call(method, ...args);
      },
      async close() {
        await session.current?.close();
        session.current = null;
      },
    }),
    [],
  );

  useEffect(() => {
    const element = host.current as unknown as HTMLElement | null;
    if (!element) return;
    let cancelled = false;
    let mounted: ElpianSession | null = null;
    const deliver = (event: string, payload: unknown) => {
      const p = callbacks.current;
      p.onEvent?.({ event, payload });
      if (event === 'ready') p.onReady?.();
      if (event === 'error') {
        const m = payload as { message?: string } | string | null;
        p.onError?.(typeof m === 'string' ? m : m?.message ?? JSON.stringify(m));
      }
    };
    // Every session event (including those fired while opening) arrives as `elpian:event`.
    const onDom = (e: Event) => {
      const { event, payload } = (e as CustomEvent<{ event: string; payload: unknown }>).detail;
      deliver(event, payload);
    };
    element.addEventListener('elpian:event', onDom);
    mountElpian(element, kind, JSON.parse(optionsJson))
      .then((s) => {
        if (cancelled) return void s.close();
        mounted = s;
        session.current = s;
      })
      .catch((e) => deliver('error', { message: String(e instanceof Error ? e.message : e) }));
    return () => {
      cancelled = true;
      element.removeEventListener('elpian:event', onDom);
      if (mounted) void mounted.close();
      if (session.current === mounted) session.current = null;
    };
  }, [kind, optionsJson]);

  return <View ref={host} style={style} />;
});
