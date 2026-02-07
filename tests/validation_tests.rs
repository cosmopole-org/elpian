use elpian::graphics::plugin::JsonScene;

#[test]
fn validate_ui_example() {
    let scene = JsonScene::load_from_file("src/examples/ui_example.json").expect("Failed to load ui_example.json");
    // validation happens during load; ensure it's valid
    assert!(!scene.scene.ui.is_empty());
}

#[test]
fn validate_material_and_3d() {
    let path = "src/examples/material_and_3d.json";
    let s = std::fs::read_to_string(path).expect("read file");
    match serde_json::from_str::<elpian::graphics::schema::SceneDef>(&s) {
        Ok(scene) => assert!(!scene.world.is_empty()),
        Err(e) => panic!("Failed to deserialize {}: {}", path, e),
    }
}

#[test]
fn validate_rounded_ui() {
    let path = "src/examples/rounded_ui.json";
    let s = std::fs::read_to_string(path).expect("read file");
    let scene: elpian::graphics::schema::SceneDef = serde_json::from_str(&s).expect("deserialize");
    // ensure there's at least one card with corner_radius > 0
    let mut found = false;
    for node in scene.ui {
        if let elpian::graphics::schema::JsonNode::Card(card) = node {
            if card.corner_radius > 0.0 {
                found = true;
                break;
            }
        }
    }
    assert!(found, "Expected a card with corner_radius > 0 in rounded_ui.json");
}

#[test]
fn validate_rounded_shadow_demo() {
    let path = "src/examples/rounded_shadow_demo.json";
    let s = std::fs::read_to_string(path).expect("read file");
    let scene: elpian::graphics::schema::SceneDef = serde_json::from_str(&s).expect("deserialize");

    // expect an appbar with elevation and a card with corner_radius and elevation
    let mut found_appbar = false;
    let mut found_card = false;
    for node in scene.ui {
        match node {
            elpian::graphics::schema::JsonNode::AppBar(a) => {
                if a.elevation > 0 { found_appbar = true; }
            }
            elpian::graphics::schema::JsonNode::Card(c) => {
                if c.corner_radius > 0.0 && c.elevation > 0 { found_card = true; }
            }
            _ => {}
        }
    }

    assert!(found_appbar, "Expected appbar with elevation in rounded_shadow_demo.json");
    assert!(found_card, "Expected card with corner_radius and elevation in rounded_shadow_demo.json");
}

#[test]
fn parse_mesh_snippets() {
    use elpian::graphics::schema::MeshType;

    let s1 = "\"Cube\""; // string form
    let s2 = "{ \"radius\": 0.8, \"subdivisions\": 16 }"; // sphere-like
    let s3 = "{ \"size\": 10.0 }"; // plane-like
    let s0 = "null";
    let s_empty = "{}";

    let _m0: Result<MeshType, _> = serde_json::from_str(s0);
    let _m_empty: Result<MeshType, _> = serde_json::from_str(s_empty);
    let _m1: Result<MeshType, _> = serde_json::from_str(s1);
    let _m2: Result<MeshType, _> = serde_json::from_str(s2);
    let _m3: Result<MeshType, _> = serde_json::from_str(s3);

    println!("m0: {:?}, m_empty: {:?}, m1: {:?}, m2: {:?}, m3: {:?}", _m0, _m_empty, _m1, _m2, _m3);

    // string form is not accepted for unit variant; null represents `Cube` correctly
    assert!(_m0.is_ok());
    assert!(_m2.is_ok());
    assert!(_m3.is_ok());
}
