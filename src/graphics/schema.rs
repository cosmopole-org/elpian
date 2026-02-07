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
    
    // Material Design UI Elements
    #[serde(rename = "fab")]
    FloatingActionButton(FABNode),
    #[serde(rename = "card")]
    Card(CardNode),
    #[serde(rename = "chip")]
    Chip(ChipNode),
    #[serde(rename = "appbar")]
    AppBar(AppBarNode),
    #[serde(rename = "dialog")]
    Dialog(DialogNode),
    #[serde(rename = "menu")]
    Menu(MenuNode),
    #[serde(rename = "bottomsheet")]
    BottomSheet(BottomSheetNode),
    #[serde(rename = "snackbar")]
    Snackbar(SnackbarNode),
    #[serde(rename = "switch")]
    Switch(SwitchNode),
    #[serde(rename = "tabs")]
    Tabs(TabsNode),
    #[serde(rename = "badge")]
    Badge(BadgeNode),
    #[serde(rename = "tooltip")]
    Tooltip(TooltipNode),
    #[serde(rename = "rating")]
    Rating(RatingNode),
    #[serde(rename = "segment")]
    SegmentedButton(SegmentedButtonNode),
    #[serde(rename = "iconbutton")]
    IconButton(IconButtonNode),
    #[serde(rename = "divider")]
    Divider(DividerNode),
    #[serde(rename = "list")]
    List(ListNode),
    #[serde(rename = "drawer")]
    Drawer(DrawerNode),
    
    // 3D World Elements
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
    #[serde(rename = "terrain")]
    Terrain(TerrainNode),
    #[serde(rename = "skybox")]
    Skybox(SkyboxNode),
    #[serde(rename = "foliage")]
    Foliage(FoliageNode),
    #[serde(rename = "decal")]
    Decal(DecalNode),
    #[serde(rename = "billboard")]
    Billboard(BillboardNode),
    #[serde(rename = "water")]
    Water(WaterNode),
    #[serde(rename = "rigidbody")]
    RigidBody(RigidBodyNode),
    #[serde(rename = "environment")]
    Environment(EnvironmentNode),
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
    #[serde(default)]
    pub glass: bool,
    #[serde(default)]
    pub glass_opacity: f32,
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
    
    // Material Design properties
    #[serde(default)]
    pub elevation: Option<u32>,
    #[serde(default)]
    pub corner_radius: Option<f32>,
    #[serde(default)]
    pub shadow_color: Option<ColorDef>,
    #[serde(default)]
    pub border_color: Option<ColorDef>,
    #[serde(default)]
    pub border_width: Option<f32>,
    #[serde(default)]
    pub opacity: Option<f32>,
    #[serde(default)]
    pub rotation: Option<f32>,
    #[serde(default)]
    pub scale: Option<f32>,
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
    Cone { radius: f32, height: f32 },
    Torus { radius: f32, tube_radius: f32 },
    Icosphere { radius: f32, subdivisions: u32 },
    UvSphere { radius: f32, sectors: u32, stacks: u32 },
    Grid { width: u32, height: u32, spacing: f32 },
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
    
    // Additional PBR properties
    #[serde(default)]
    pub ambient_occlusion_texture: Option<String>,
    #[serde(default)]
    pub height_map_texture: Option<String>,
    #[serde(default)]
    pub parallax_depth: Option<f32>,
    #[serde(default)]
    pub alpha_mode: Option<AlphaMode>,
    #[serde(default)]
    pub double_sided: bool,
    #[serde(default)]
    pub ior: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AlphaMode {
    Opaque,
    Mask,
    Blend,
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

// ===== MATERIAL DESIGN UI ELEMENTS =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FABNode {
    #[serde(default)]
    pub id: Option<String>,
    pub icon: String,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub fab_type: FABType,
    #[serde(default)]
    pub color: Option<ColorDef>,
    #[serde(default)]
    pub elevation: u32,
    #[serde(default)]
    pub glass: bool,
    #[serde(default)]
    pub glass_opacity: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FABType {
    FAB,
    ExtendedFAB,
    Small,
    Large,
}

impl Default for FABType {
    fn default() -> Self {
        FABType::FAB
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub children: Vec<JsonNode>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub elevation: u32,
    #[serde(default)]
    pub corner_radius: f32,
    #[serde(default)]
    pub background_color: Option<ColorDef>,
    #[serde(default)]
    pub on_click: Option<String>,
    #[serde(default)]
    pub outlined: bool,
    #[serde(default)]
    pub glass: bool,
    #[serde(default)]
    pub glass_opacity: f32,
}

impl Default for CardNode {
    fn default() -> Self {
        Self {
            id: None,
            children: Vec::new(),
            style: StyleDef::default(),
            elevation: 1,
            corner_radius: 12.0,
            background_color: None,
            on_click: None,
            outlined: false,
            glass: false,
            glass_opacity: 0.12,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChipNode {
    #[serde(default)]
    pub id: Option<String>,
    pub label: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub chip_type: ChipType,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub selected: bool,
    #[serde(default)]
    pub color: Option<ColorDef>,
    #[serde(default)]
    pub on_click: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ChipType {
    Input,
    Filter,
    Suggestion,
    Assist,
}

impl Default for ChipType {
    fn default() -> Self {
        ChipType::Assist
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppBarNode {
    #[serde(default)]
    pub id: Option<String>,
    pub title: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub app_bar_type: AppBarType,
    #[serde(default)]
    pub navigation_icon: Option<String>,
    #[serde(default)]
    pub actions: Vec<AppBarAction>,
    #[serde(default)]
    pub background_color: Option<ColorDef>,
    #[serde(default)]
    pub elevation: u32,
    #[serde(default)]
    pub glass: bool,
    #[serde(default)]
    pub glass_opacity: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AppBarType {
    Center,
    Small,
    Medium,
    Large,
}

impl Default for AppBarType {
    fn default() -> Self {
        AppBarType::Center
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppBarAction {
    pub icon: String,
    #[serde(default)]
    pub tooltip: String,
    #[serde(default)]
    pub action: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DialogNode {
    #[serde(default)]
    pub id: Option<String>,
    pub title: String,
    #[serde(default)]
    pub content: Vec<JsonNode>,
    #[serde(default)]
    pub actions: Vec<DialogAction>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub dismissible: bool,
    #[serde(default)]
    pub glass: bool,
    #[serde(default)]
    pub glass_opacity: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DialogAction {
    pub label: String,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub is_primary: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MenuNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub items: Vec<MenuItem>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub elevation: u32,
    #[serde(default)]
    pub glass: bool,
    #[serde(default)]
    pub glass_opacity: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MenuItem {
    pub label: String,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub sub_items: Vec<MenuItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BottomSheetNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub content: Vec<JsonNode>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub height: Option<f32>,
    #[serde(default)]
    pub dismissible: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnackbarNode {
    #[serde(default)]
    pub id: Option<String>,
    pub message: String,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub duration_ms: u32,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub glass: bool,
    #[serde(default)]
    pub glass_opacity: f32,
}

impl Default for SnackbarNode {
    fn default() -> Self {
        Self {
            id: None,
            message: String::new(),
            action: None,
            duration_ms: 4000,
            style: StyleDef::default(),
            glass: false,
            glass_opacity: 0.35,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwitchNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub on_change: Option<String>,
    #[serde(default)]
    pub icon_enabled: Option<String>,
    #[serde(default)]
    pub icon_disabled: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TabsNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub tabs: Vec<TabItem>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub selected_index: usize,
    #[serde(default)]
    pub on_change: Option<String>,
    #[serde(default)]
    pub tab_type: TabType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TabItem {
    pub label: String,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub content: Vec<JsonNode>,
    #[serde(default)]
    pub badge_count: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TabType {
    Fixed,
    Scrollable,
}

impl Default for TabType {
    fn default() -> Self {
        TabType::Fixed
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BadgeNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub count: Option<u32>,
    pub label: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TooltipNode {
    #[serde(default)]
    pub id: Option<String>,
    pub message: String,
    #[serde(default)]
    pub position: TooltipPosition,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub glass: bool,
    #[serde(default)]
    pub glass_opacity: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TooltipPosition {
    Top,
    Bottom,
    Left,
    Right,
}

impl Default for TooltipPosition {
    fn default() -> Self {
        TooltipPosition::Top
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RatingNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub value: f32,
    #[serde(default)]
    pub max: u32,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub on_change: Option<String>,
    #[serde(default)]
    pub read_only: bool,
}

impl Default for RatingNode {
    fn default() -> Self {
        Self {
            id: None,
            value: 0.0,
            max: 5,
            style: StyleDef::default(),
            on_change: None,
            read_only: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SegmentedButtonNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub options: Vec<SegmentOption>,
    #[serde(default)]
    pub selected_index: usize,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub on_change: Option<String>,
    #[serde(default)]
    pub multiple_selection: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SegmentOption {
    pub label: String,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub selected: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IconButtonNode {
    #[serde(default)]
    pub id: Option<String>,
    pub icon: String,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub tooltip: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DividerNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub thickness: f32,
    #[serde(default)]
    pub color: Option<ColorDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub items: Vec<JsonNode>,
    #[serde(default)]
    pub style: StyleDef,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DrawerNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub content: Vec<JsonNode>,
    #[serde(default)]
    pub style: StyleDef,
    #[serde(default)]
    pub open: bool,
    #[serde(default)]
    pub width: Option<f32>,
}

// ===== 3D GAME ELEMENTS =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerrainNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub size: f32,
    #[serde(default)]
    pub height: f32,
    #[serde(default)]
    pub subdivisions: u32,
    #[serde(default)]
    pub heightmap: Option<String>,
    #[serde(default)]
    pub material: MaterialDef,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub physics: Option<PhysicsDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkyboxNode {
    #[serde(default)]
    pub id: Option<String>,
    pub texture_path: String,
    #[serde(default)]
    pub rotation: Option<Vec3Def>,
    #[serde(default)]
    pub brightness: f32,
}

impl Default for SkyboxNode {
    fn default() -> Self {
        Self {
            id: None,
            texture_path: String::new(),
            rotation: None,
            brightness: 1.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FoliageNode {
    #[serde(default)]
    pub id: Option<String>,
    pub foliage_type: FoliageType,
    #[serde(default)]
    pub density: f32,
    #[serde(default)]
    pub color_variation: f32,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub material: MaterialDef,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FoliageType {
    Trees,
    Grass,
    Bushes,
    Custom { model_path: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecalNode {
    #[serde(default)]
    pub id: Option<String>,
    pub texture: String,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub size: Vec3Def,
    #[serde(default)]
    pub sort_order: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BillboardNode {
    #[serde(default)]
    pub id: Option<String>,
    pub texture: String,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub size: Vec3Def,
    #[serde(default)]
    pub billboard_type: BillboardType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BillboardType {
    ScreenAligned,
    AxisAligned,
    Cylindrical,
}

impl Default for BillboardType {
    fn default() -> Self {
        BillboardType::ScreenAligned
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaterNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub size: Vec3Def,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub wave_amplitude: f32,
    #[serde(default)]
    pub wave_frequency: f32,
    #[serde(default)]
    pub water_color: Option<ColorDef>,
    #[serde(default)]
    pub transparency: f32,
}

impl Default for WaterNode {
    fn default() -> Self {
        Self {
            id: None,
            size: Vec3Def::default(),
            transform: TransformDef::default(),
            wave_amplitude: 0.5,
            wave_frequency: 1.0,
            water_color: None,
            transparency: 0.7,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RigidBodyNode {
    #[serde(default)]
    pub id: Option<String>,
    pub mesh: MeshType,
    #[serde(default)]
    pub material: MaterialDef,
    #[serde(default)]
    pub transform: TransformDef,
    #[serde(default)]
    pub physics: PhysicsDef,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysicsDef {
    #[serde(default)]
    pub mass: f32,
    #[serde(default)]
    pub friction: f32,
    #[serde(default)]
    pub restitution: f32,
    #[serde(default)]
    pub gravity_scale: f32,
    #[serde(default)]
    pub use_gravity: bool,
    #[serde(default)]
    pub collider_type: ColliderType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ColliderType {
    Box,
    Sphere,
    Capsule,
    Mesh,
}

impl Default for ColliderType {
    fn default() -> Self {
        ColliderType::Box
    }
}

impl Default for PhysicsDef {
    fn default() -> Self {
        Self {
            mass: 1.0,
            friction: 0.3,
            restitution: 0.0,
            gravity_scale: 1.0,
            use_gravity: true,
            collider_type: ColliderType::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvironmentNode {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub ambient_light: Option<ColorDef>,
    #[serde(default)]
    pub ambient_intensity: f32,
    #[serde(default)]
    pub fog_enabled: bool,
    #[serde(default)]
    pub fog_color: Option<ColorDef>,
    #[serde(default)]
    pub fog_distance: f32,
}

impl Default for EnvironmentNode {
    fn default() -> Self {
        Self {
            id: None,
            ambient_light: None,
            ambient_intensity: 0.8,
            fog_enabled: false,
            fog_color: None,
            fog_distance: 100.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SceneDef {
    #[serde(default)]
    pub ui: Vec<JsonNode>,
    #[serde(default)]
    pub world: Vec<JsonNode>,
}
