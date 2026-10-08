/**
 * Image maps (`<img usemap="#m">` + `<map name="m"><area …></map>`): the
 * image is the first child; every following child is a tappable area whose
 * coordinates are in the image's natural pixels and are scaled to the
 * rendered size.
 */
import { RenderObject, constrain, type Constraints } from '../object.js';

export interface AreaSpec {
  shape: 'rect' | 'circle' | 'poly' | 'default';
  coords: number[];
}

export function areaBounds(area: AreaSpec, w: number, h: number): { x: number; y: number; width: number; height: number } {
  const c = area.coords;
  switch (area.shape) {
    case 'rect':
      return { x: Math.min(c[0], c[2]), y: Math.min(c[1], c[3]), width: Math.abs(c[2] - c[0]), height: Math.abs(c[3] - c[1]) };
    case 'circle':
      return { x: c[0] - c[2], y: c[1] - c[2], width: c[2] * 2, height: c[2] * 2 };
    case 'poly': {
      const xs = c.filter((_, i) => i % 2 === 0);
      const ys = c.filter((_, i) => i % 2 === 1);
      const x = Math.min(...xs);
      const y = Math.min(...ys);
      return { x, y, width: Math.max(...xs) - x, height: Math.max(...ys) - y };
    }
    default:
      return { x: 0, y: 0, width: w, height: h };
  }
}

/** Whether a point in natural image pixels lies inside [area]. */
export function areaContains(area: AreaSpec, px: number, py: number): boolean {
  const c = area.coords;
  switch (area.shape) {
    case 'rect':
      return px >= Math.min(c[0], c[2]) && px <= Math.max(c[0], c[2]) && py >= Math.min(c[1], c[3]) && py <= Math.max(c[1], c[3]);
    case 'circle':
      return (px - c[0]) ** 2 + (py - c[1]) ** 2 <= c[2] ** 2;
    case 'poly': {
      let inside = false;
      const n = Math.floor(c.length / 2);
      for (let i = 0, j = n - 1; i < n; j = i++) {
        const xi = c[2 * i], yi = c[2 * i + 1], xj = c[2 * j], yj = c[2 * j + 1];
        if (yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
      }
      return inside;
    }
    default:
      return true;
  }
}

/** props: { src, areas: AreaSpec[] } */
export class RenderImageMap extends RenderObject {
  scale = { x: 1, y: 1 };

  protected performLayout(c: Constraints): void {
    const [image, ...areas] = this.children;
    if (!image) {
      this.size = constrain(c, { width: 0, height: 0 });
      return;
    }
    image.layout(c);
    image.offset = { x: 0, y: 0 };
    this.size = { ...image.size };
    const natural = this.owner?.imageSize(this.props.src) ?? null;
    this.scale = natural && natural.width > 0 && natural.height > 0 ? { x: this.size.width / natural.width, y: this.size.height / natural.height } : { x: 1, y: 1 };
    const specs: AreaSpec[] = this.props.areas ?? [];
    areas.forEach((area, i) => {
      const spec = specs[i];
      if (!spec) {
        area.layout({ minWidth: 0, maxWidth: 0, minHeight: 0, maxHeight: 0 });
        return;
      }
      const b = areaBounds(spec, natural?.width ?? this.size.width, natural?.height ?? this.size.height);
      const w = b.width * this.scale.x;
      const h = b.height * this.scale.y;
      area.layout({ minWidth: w, maxWidth: w, minHeight: h, maxHeight: h });
      area.offset = { x: b.x * this.scale.x, y: b.y * this.scale.y };
    });
  }
}
