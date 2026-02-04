use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum JsonNode {
    #[serde(rename = "container")]
    Container(ContainerNode),
    #[serde(rename = "text")]
    Text(TextNode),
    #[serde(rename = "button")]
    Button(ButtonNode),
    #[serde(rename = "image")]
    Image(ImageNode),
    #[serde(rename = "slider")]
    Slider(SliderNode),
    #[serde(rename = "checkbox")]
    Checkbox(CheckboxNode),
    #[serde(rename = "radio")]
    RadioButton(RadioButtonNode),
    #[serde(rename = "textinput")]
    TextInput(TextInputNode),
    #[serde(rename = "progressbar")]
    ProgressBar(ProgressBarNode),
    #[serde(rename = "mesh3d")]
    Mesh3D(Mesh3DNode),
    #[serde(rename = "light")]
    Light(LightNode),
    #[serde(rename = "camera")]
    Camera(CameraNode),
    #[serde(rename = "audio")]
    Audio(AudioNode),
    #[serde(rename = "particles")]
    Particles(ParticleNode),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub children: Vec<JsonNode>,
    #[serde(default)]
    pub background_color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextNode {
    #[serde(default)]
    pub id: Option<String>,
    pub text: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub font_size: Option<f32>,
    #[serde(default)]
    pub color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ButtonNode {
    #[serde(default)]
    pub id: Option<String>,
    pub label: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub normal_color: Option<ColorDef>,
    #[serde(default)]
    pub hover_color: Option<ColorDef>,
    #[serde(default)]
    pub pressed_color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageNode {
    #[serde(default)]
    pub id: Option<String>,
    pub path: String,
    #[serde(default)]
    pub style: StyleDef,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SliderNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub min: f32,
    #[serde(default = "default_max")]
    pub max: f32,
    #[serde(default)]
    pub value: f32,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub on_change: Option<String>,
}

fn default_max() -> f32 {
    100.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckboxNode {
    #[serde(default)]
    pub id: Option<String>,
    pub label: String,
    #[serde(default)]
    pub checked: bool,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub on_change: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RadioButtonNode {
    #[serde(default)]
    pub id: Option<String>,
    pub label: String,
    pub group: String,
    #[serde(default)]
    pub checked: bool,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub on_change: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextInputNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub placeholder: String,
    #[serde(default)]
    pub value: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub on_change: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgressBarNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub value: f32,
    #[serde(default = "default_max")]
    pub max: f32,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub bar_color: Option<ColorDef>,
    #[serde(default)]
    pub background_color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mesh3DNode {
    #[serde(default)]
    pub id: Option<String>,
    pub mesh: MeshType,
    #[serde(default)]
    pub material: MaterialDef,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub animation: Option<AnimationDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LightNode {
    #[serde(default)]
    pub id: Option<String>,
    pub light_type: LightType,
    #[serde(default)]
    pub color: Option<ColorDef>,
    #[serde(default)]
    pub intensity: Option<f32>,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub animation: Option<AnimationDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CameraNode {
    #[serde(default)]
    pub id: Option<String>,
    pub camera_type: CameraType,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub animation: Option<AnimationDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioNode {
    #[serde(default)]
    pub id: Option<String>,
    pub path: String,
    #[serde(default)]
    pub volume: f32,
    #[serde(default)]
    pub looping: bool,
    #[serde(default)]
    pub autoplay: bool,
    #[serde(default)]
    pub spatial: bool,
    #[serde(default)]
    pub transform: Option<TransformDef>,
}

impl Default for AudioNode {
    fn default() -> Self {
        Self {
            id: None,
            path: String::new(),
            volume: 1.0,
            looping: false,
            autoplay: true,
            spatial: false,
            transform: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParticleNode {
    #[serde(default)]
    pub id: Option<String>,
    pub transform: TransformDef,
    #[serde(default)]
    pub emission_rate: f32,
    #[serde(default)]
    pub lifetime: f32,
    #[serde(default)]
    pub color: ColorDef,
    #[serde(default)]
    pub size: f32,
    #[serde(default)]
    pub velocity: Vec3Def,
    #[serde(default)]
    pub gravity: Vec3Def,
}

impl Default for ParticleNode {
    fn default() -> Self {
        Self {
            id: None,
            transform: TransformDef::default(),
            emission_rate: 10.0,
            lifetime: 1.0,
            color: ColorDef { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
            size: 0.1,
            velocity: Vec3Def { x: 0.0, y: 1.0, z: 0.0 },
            gravity: Vec3Def { x: 0.0, y: -9.8, z: 0.0 },
        }
    }
}

// Style definitions
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StyleDef {
    #[serde(default)]
    pub width: Option<DimensionDef>,
    #[serde(default)]
    pub height: Option<DimensionDef>,
    #[serde(default)]
    pub min_width: Option<DimensionDef>,
    #[serde(default)]
    pub min_height: Option<DimensionDef>,
    #[serde(default)]
    pub max_width: Option<DimensionDef>,
    #[serde(default)]
    pub max_height: Option<DimensionDef>,
    #[serde(default)]
    pub padding: Option<RectDef>,
    #[serde(default)]
    pub margin: Option<RectDef>,
    #[serde(default)]
    pub border: Option<RectDef>,
    #[serde(default)]
    pub flex_direction: Option<FlexDirection>,
    #[serde(default)]
    pub justify_content: Option<JustifyContent>,
    #[serde(default)]
    pub align_items: Option<AlignItems>,
    #[serde(default)]
    pub position_type: Option<PositionType>,
    #[serde(default)]
    pub top: Option<DimensionDef>,
    #[serde(default)]
    pub bottom: Option<DimensionDef>,
    #[serde(default)]
    pub left: Option<DimensionDef>,
    #[serde(default)]
    pub right: Option<DimensionDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum DimensionDef {
    Pixels(f32),
    Percent(String), // "50%"
    Auto,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RectDef {
    #[serde(default)]
    pub top: f32,
    #[serde(default)]
    pub bottom: f32,
    #[serde(default)]
    pub left: f32,
    #[serde(default)]
    pub right: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColorDef {
    #[serde(default)]
    pub r: f32,
    #[serde(default)]
    pub g: f32,
    #[serde(default)]
    pub b: f32,
    #[serde(default = "default_alpha")]
    pub a: f32,
}

impl Default for ColorDef {
    fn default() -> Self {
        Self {
            r: 1.0,
            g: 1.0,
            b: 1.0,
            a: 1.0,
        }
    }
}

fn default_alpha() -> f32 {
    1.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FlexDirection {
    Row,
    Column,
    RowReverse,
    ColumnReverse,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum JustifyContent {
    FlexStart,
    FlexEnd,
    Center,
    SpaceBetween,
    SpaceAround,
    SpaceEvenly,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AlignItems {
    FlexStart,
    FlexEnd,
    Center,
    Stretch,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PositionType {
    Relative,
    Absolute,
}

// 3D definitions
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum MeshType {
    Cube,
    Sphere { radius: f32, subdivisions: u32 },
    Plane { size: f32 },
    Capsule { radius: f32, depth: f32 },
    Cylinder { radius: f32, height: f32 },
    File { path: String }, // Load from .obj, .gltf, etc.
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MaterialDef {
    #[serde(default)]
    pub base_color: Option<ColorDef>,
    #[serde(default)]
    pub base_color_texture: Option<String>,
    #[serde(default)]
    pub emissive: Option<ColorDef>,
    #[serde(default)]
    pub emissive_texture: Option<String>,
    #[serde(default)]
    pub metallic: Option<f32>,
    #[serde(default)]
    pub roughness: Option<f32>,
    #[serde(default)]
    pub metallic_roughness_texture: Option<String>,
    #[serde(default)]
    pub normal_map_texture: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnimationDef {
    pub animation_type: AnimationType,
    #[serde(default)]
    pub duration: f32,
    #[serde(default)]
    pub looping: bool,
    #[serde(default)]
    pub easing: EasingType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AnimationType {
    Rotate {
        axis: Vec3Def,
        degrees: f32,
    },
    Translate {
        from: Vec3Def,
        to: Vec3Def,
    },
    Scale {
        from: Vec3Def,
        to: Vec3Def,
    },
    Bounce {
        height: f32,
    },
    Pulse {
        min_scale: f32,
        max_scale: f32,
    },
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub enum EasingType {
    #[default]
    Linear,
    EaseIn,
    EaseOut,
    EaseInOut,
    Bounce,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformDef {
    #[serde(default)]
    pub position: Option<Vec3Def>,
    #[serde(default)]
    pub rotation: Option<Vec3Def>, // Euler angles in degrees
    #[serde(default)]
    pub scale: Option<Vec3Def>,
}

impl Default for TransformDef {
    fn default() -> Self {
        Self {
            position: None,
            rotation: None,
            scale: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Vec3Def {
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
    #[serde(default)]
    pub z: f32,
}

impl Default for Vec3Def {
    fn default() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            z: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LightType {
    Point,
    Directional,
    Spot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CameraType {
    Perspective,
    Orthographic,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SceneDef {
    #[serde(default)]
    pub ui: Vec<JsonNode>,
    #[serde(default)]
    pub world: Vec<JsonNode>,
}
