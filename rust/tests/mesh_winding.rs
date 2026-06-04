//! Winding-consistency guard for the procedural mesh generators.
//!
//! Back-face culling (added to keep the CPU rasterizer from filling hidden
//! triangles) tests the *screen-space winding* of each triangle. For that to be
//! correct, every generator must wind its triangles counter-clockwise as seen
//! from outside — i.e. the vertex-order normal `(v1-v0)×(v2-v0)` must point the
//! same way as the triangle's assigned (shading) normal.
//!
//! Historically the generators were inconsistent (the sphere/plane were wound
//! the opposite way to the cube); culling exposed that. This test locks every
//! generator to one convention so a future generator can't silently render
//! inside-out.

use elpian_vm::bevy_scene::renderer::generate_mesh_triangles;
use elpian_vm::bevy_scene::schema::{MeshType, MeshTypeName, MeshTypeParam};

/// Assert every non-degenerate triangle is wound CCW-outward (its vertex-order
/// normal agrees with its assigned normal).
fn assert_ccw_outward(name: &str, mesh: &MeshType) {
    let tris = generate_mesh_triangles(mesh);
    assert!(!tris.is_empty(), "{name}: generator produced no triangles");

    let mut backwards = 0;
    let mut checked = 0;
    for (i, t) in tris.iter().enumerate() {
        let e1 = t.v1 - t.v0;
        let e2 = t.v2 - t.v0;
        let face = e1.cross(e2);
        // Skip degenerate triangles (zero area) — their winding is undefined.
        if face.length_squared() < 1e-12 {
            continue;
        }
        checked += 1;
        let n = t.normal;
        // Assigned normals may be smooth (per-vertex radial) rather than the exact
        // face normal, so use the sign of the dot, not equality. A correctly wound
        // outward face has a strictly positive dot.
        if face.dot(n) <= 0.0 {
            backwards += 1;
            if backwards <= 3 {
                eprintln!(
                    "  {name}: triangle {i} wound backwards (face·normal = {:.4})",
                    face.normalize().dot(n)
                );
            }
        }
    }

    assert!(
        backwards == 0,
        "{name}: {backwards}/{checked} triangles are wound the wrong way \
         (vertex order disagrees with the assigned normal)"
    );
}

#[test]
fn cube_is_ccw_outward() {
    assert_ccw_outward("cube", &MeshType::Named(MeshTypeName::Cube));
}

#[test]
fn sphere_is_ccw_outward() {
    assert_ccw_outward(
        "sphere",
        &MeshType::Parameterized(MeshTypeParam::Sphere {
            radius: 1.0,
            subdivisions: 16,
        }),
    );
}

#[test]
fn plane_is_ccw_outward() {
    assert_ccw_outward(
        "plane",
        &MeshType::Parameterized(MeshTypeParam::Plane { size: 2.0 }),
    );
}

#[test]
fn cylinder_is_ccw_outward() {
    assert_ccw_outward(
        "cylinder",
        &MeshType::Parameterized(MeshTypeParam::Cylinder {
            radius: 0.7,
            height: 2.0,
            segments: 20,
        }),
    );
}

#[test]
fn cone_is_ccw_outward() {
    assert_ccw_outward(
        "cone",
        &MeshType::Parameterized(MeshTypeParam::Cone {
            radius: 0.6,
            height: 1.5,
            segments: 16,
        }),
    );
}

#[test]
fn torus_is_ccw_outward() {
    // The torus assigns winding-derived normals, so `assert_ccw_outward` would
    // pass trivially. Instead verify each face normal points *outward* relative
    // to the tube's ring center (the genuine front-facing direction).
    let radius = 1.0_f32;
    let tris = generate_mesh_triangles(&MeshType::Parameterized(MeshTypeParam::Torus {
        radius,
        tube_radius: 0.25,
    }));
    assert!(!tris.is_empty());
    let mut inward = 0;
    for t in &tris {
        let face = (t.v1 - t.v0).cross(t.v2 - t.v0);
        if face.length_squared() < 1e-12 {
            continue;
        }
        let centroid = (t.v0 + t.v1 + t.v2) / 3.0;
        // Center of the tube circle nearest this triangle: project the centroid
        // onto the ring of radius `radius` in the XZ plane. Build the XZ vector by
        // zeroing Y on a copy (avoids naming the glam type in the test crate).
        let mut xz = centroid;
        xz.y = 0.0;
        let ring_center = if xz.length() > 1e-6 {
            xz.normalize() * radius
        } else {
            xz
        };
        let outward = (centroid - ring_center).normalize();
        if face.normalize().dot(outward) <= 0.0 {
            inward += 1;
        }
    }
    assert!(
        inward == 0,
        "torus: {inward} triangles face inward (winding/normal point into the tube)"
    );
}

#[test]
fn capsule_is_ccw_outward() {
    // Capsule = cylinder + two hemispheres; guards the composed result.
    assert_ccw_outward(
        "capsule",
        &MeshType::Parameterized(MeshTypeParam::Capsule {
            radius: 0.4,
            depth: 1.0,
        }),
    );
}
