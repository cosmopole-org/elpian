// Geometric invariant: for every generated primitive, each triangle's winding
// (cross(p1-p0, p2-p0)) must point along its averaged vertex normal. The
// renderer backface-culls in screen space from exactly this winding, so a
// primitive that violates the invariant disappears when viewed from its
// normal's side — the "invisible ground plane" bug (a horizontal Plane was
// wound clockwise and was culled when seen from above).

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void expectWindingMatchesNormals(String name, Mesh mesh) {
  expect(mesh.triangles, isNotEmpty, reason: '$name generated no triangles');
  var checked = 0;
  for (final t in mesh.triangles) {
    final a = t.v1.position - t.v0.position;
    final b = t.v2.position - t.v0.position;
    final winding = a.cross(b);
    // Skip degenerate triangles (zero area) — nothing to cull.
    if (winding.length < 1e-9) continue;
    final n = (t.v0.normal + t.v1.normal + t.v2.normal) / 3.0;
    if (n.length < 1e-9) continue;
    final dot = winding.normalized.dot(n.normalized);
    expect(
      dot,
      greaterThan(0),
      reason:
          '$name: triangle wound against its normal (dot=$dot) — it will be '
          'backface-culled when viewed from the normal side. '
          'v0=${t.v0.position} v1=${t.v1.position} v2=${t.v2.position}',
    );
    checked++;
  }
  expect(checked, greaterThan(0), reason: '$name: no non-degenerate triangles');
}

/// For a closed mesh wound CCW-from-outside, the signed volume
/// `Σ dot(v0, cross(v1, v2)) / 6` is strictly positive. A mesh that is
/// winding↔normal consistent but *inward*-oriented (normals derived from an
/// inverted winding) passes the normal check yet fails this one.
void expectOutwardOrientation(String name, Mesh mesh) {
  var signedVolume = 0.0;
  for (final t in mesh.triangles) {
    signedVolume +=
        t.v0.position.dot(t.v1.position.cross(t.v2.position)) / 6.0;
  }
  expect(
    signedVolume,
    greaterThan(0),
    reason: '$name: signed volume $signedVolume ≤ 0 — the closed mesh is '
        'inward-oriented (renders its backfaces).',
  );
}

void main() {
  test('Plane winds along its +Y normal (visible from above)', () {
    expectWindingMatchesNormals('Plane', MeshGen.plane(size: 10));
    expectWindingMatchesNormals(
        'Plane(subdivided)', MeshGen.plane(size: 10, subdivisions: 4));
  });

  test('all primitives wind along their normals', () {
    expectWindingMatchesNormals('Cube', MeshGen.cube(size: 2));
    expectWindingMatchesNormals('Sphere', MeshGen.sphere(radius: 1, segments: 12));
    expectWindingMatchesNormals(
        'Cylinder', MeshGen.cylinder(radius: 1, height: 2, segments: 12));
    expectWindingMatchesNormals('Cone', MeshGen.cone(radius: 1, height: 2, segments: 12));
    expectWindingMatchesNormals(
        'Torus', MeshGen.torus(radius: 1, tubeRadius: 0.3, radial: 8, tubular: 12));
    expectWindingMatchesNormals(
        'Capsule', MeshGen.capsule(radius: 0.5, height: 1, segments: 12));
    expectWindingMatchesNormals('Pyramid', MeshGen.pyramid(base: 1, height: 1));
    expectWindingMatchesNormals('Wedge', MeshGen.wedge());
    expectWindingMatchesNormals('IcoSphere', MeshGen.icosphere(radius: 1));
  });

  test('closed primitives are outward-oriented (positive signed volume)', () {
    expectOutwardOrientation('Cube', MeshGen.cube(size: 2));
    expectOutwardOrientation('Sphere', MeshGen.sphere(radius: 1, segments: 12));
    expectOutwardOrientation(
        'Cylinder', MeshGen.cylinder(radius: 1, height: 2, segments: 12));
    expectOutwardOrientation('Cone', MeshGen.cone(radius: 1, height: 2, segments: 12));
    expectOutwardOrientation(
        'Capsule', MeshGen.capsule(radius: 0.5, height: 2, segments: 12));
    expectOutwardOrientation('Pyramid', MeshGen.pyramid(base: 1, height: 1));
    expectOutwardOrientation('Wedge', MeshGen.wedge());
    expectOutwardOrientation('IcoSphere', MeshGen.icosphere(radius: 1));
  });
}
