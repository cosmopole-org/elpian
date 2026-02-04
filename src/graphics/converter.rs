use bevy::prelude::*;
use anyhow::Result;

use crate::graphics::schema;

pub struct JsonToBevy;

impl JsonToBevy {
    pub fn spawn_ui(
        commands: &mut Commands,
        asset_server: &AssetServer,
        node: &schema::JsonNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        match node {
            schema::JsonNode::Container(container) => {
                Self::spawn_container(commands, asset_server, container, parent)
            }
            schema::JsonNode::Text(text) => Self::spawn_text(commands, asset_server, text, parent),
            schema::JsonNode::Button(button) => Self::spawn_button(commands, asset_server, button, parent),
            schema::JsonNode::Image(image) => Self::spawn_image(commands, asset_server, image, parent),
            schema::JsonNode::Slider(slider) => Self::spawn_slider(commands, slider, parent),
            schema::JsonNode::Checkbox(checkbox) => Self::spawn_checkbox(commands, checkbox, parent),
            schema::JsonNode::RadioButton(radio) => Self::spawn_radio(commands, radio, parent),
            schema::JsonNode::TextInput(input) => Self::spawn_text_input(commands, input, parent),
            schema::JsonNode::ProgressBar(progress) => Self::spawn_progress_bar(commands, progress, parent),
            _ => Err(anyhow::anyhow!("Invalid UI node type")),
        }
    }

    pub fn spawn_world(
        commands: &mut Commands,
        meshes: &mut ResMut<Assets<Mesh>>,
        materials: &mut ResMut<Assets<StandardMaterial>>,
        asset_server: &AssetServer,
        node: &schema::JsonNode,
    ) -> Result<Entity> {
        match node {
            schema::JsonNode::Mesh3D(mesh) => Self::spawn_mesh3d(commands, meshes, materials, asset_server, mesh),
            schema::JsonNode::Light(light) => Self::spawn_light(commands, light),
            schema::JsonNode::Camera(camera) => Self::spawn_camera(commands, camera),
            schema::JsonNode::Audio(audio) => Self::spawn_audio(commands, asset_server, audio),
            schema::JsonNode::Particles(particles) => Self::spawn_particles(commands, particles),
            _ => Err(anyhow::anyhow!("Invalid world node type")),
        }
    }

    fn spawn_container(
        commands: &mut Commands,
        asset_server: &AssetServer,
        container: &schema::ContainerNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        let style = Self::convert_style(&container.style);
        let background_color = container
            .background_color
            .as_ref()
            .map(Self::convert_color)
            .unwrap_or(Color::NONE);

        let mut entity_commands = commands.spawn((
            Node{..style},
            BackgroundColor(background_color),
        ));

        if let Some(parent) = parent {
            entity_commands.set_parent(parent);
        }

        let entity = entity_commands.id();

        // Spawn children
        for child in &container.children {
            Self::spawn_ui(commands, asset_server, child, Some(entity))?;
        }

        Ok(entity)
    }

    fn spawn_text(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        text_node: &schema::TextNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        let style = Self::convert_style(&text_node.style);
        let font_size = text_node.font_size.unwrap_or(24.0);
        let color = text_node
            .color
            .as_ref()
            .map(Self::convert_color)
            .unwrap_or(Color::WHITE);

        let mut entity_commands = commands.spawn((
            Text::new(text_node.text.clone()),
            TextFont {
                font_size,
                ..default()
            },
            TextColor(color),
            Node{..style},
        ));

        if let Some(parent) = parent {
            entity_commands.set_parent(parent);
        }

        Ok(entity_commands.id())
    }

    fn spawn_button(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        button_node: &schema::ButtonNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        let style = Self::convert_style(&button_node.style);
        let normal_color = button_node
            .normal_color
            .as_ref()
            .map(Self::convert_color)
            .unwrap_or(Color::srgb(0.15, 0.15, 0.15));

        let mut button_entity = commands.spawn((
            Button,
            Node{
                padding: UiRect::all(Val::Px(15.0)),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..style
            },
            BackgroundColor(normal_color),
        ));

        if let Some(parent) = parent {
            button_entity.set_parent(parent);
        }

        let button_id = button_entity.id();

        // Add text label
        commands.spawn((
            Text::new(button_node.label.clone()),
            TextFont {
                font_size: 20.0,
                ..default()
            },
            TextColor(Color::WHITE),
        )).set_parent(button_id);

        Ok(button_id)
    }

    fn spawn_image(
        commands: &mut Commands,
        asset_server: &AssetServer,
        image_node: &schema::ImageNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        let style = Self::convert_style(&image_node.style);
        let image_handle = asset_server.load(&image_node.path);

        let mut entity_commands = commands.spawn((
            ImageNode::default(),
            ImageNode::new(image_handle),
            Node{..style},
        ));

        if let Some(parent) = parent {
            entity_commands.set_parent(parent);
        }

        Ok(entity_commands.id())
    }

    fn spawn_slider(
        commands: &mut Commands,
        slider_node: &schema::SliderNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let style = Self::convert_style(&slider_node.style);
        
        let mut container = commands.spawn((
            Node{
                width: Val::Px(200.0),
                height: Val::Px(20.0),
                ..style
            },
            BackgroundColor(Color::srgb(0.2, 0.2, 0.2)),
            Slider {
                min: slider_node.min,
                max: slider_node.max,
                value: slider_node.value,
                on_change: slider_node.on_change.clone(),
            },
        ));

        if let Some(parent) = parent {
            container.set_parent(parent);
        }

        let container_id = container.id();

        // Add slider handle
        commands.spawn((
            Node{
                width: Val::Px(10.0),
                height: Val::Px(30.0),
                position_type: PositionType::Absolute,
                left: Val::Percent(
                    ((slider_node.value - slider_node.min) / (slider_node.max - slider_node.min)) * 100.0
                ),
                top: Val::Px(-5.0),
                ..default()
            },
            BackgroundColor(Color::srgb(0.8, 0.8, 0.8)),
            SliderHandle,
        )).set_parent(container_id);

        Ok(container_id)
    }

    fn spawn_checkbox(
        commands: &mut Commands,
        checkbox_node: &schema::CheckboxNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let style = Self::convert_style(&checkbox_node.style);
        
        let mut container = commands.spawn(Node{
            flex_direction: FlexDirection::Row,
            align_items: AlignItems::Center,
            ..style
        });

        if let Some(parent) = parent {
            container.set_parent(parent);
        }

        let container_id = container.id();

        // Checkbox box
        let checkbox_color = if checkbox_node.checked {
            Color::srgb(0.2, 0.8, 0.2)
        } else {
            Color::srgb(0.3, 0.3, 0.3)
        };

        commands.spawn((
            Button,
            Node{
                width: Val::Px(20.0),
                height: Val::Px(20.0),
                margin: UiRect::right(Val::Px(10.0)),
                ..default()
            },
            BackgroundColor(checkbox_color),
            Checkbox {
                checked: checkbox_node.checked,
                on_change: checkbox_node.on_change.clone(),
            },
        )).set_parent(container_id);

        // Label
        commands.spawn((
            Text::new(checkbox_node.label.clone()),
            TextFont {
                font_size: 18.0,
                ..default()
            },
            TextColor(Color::WHITE),
        )).set_parent(container_id);

        Ok(container_id)
    }

    fn spawn_radio(
        commands: &mut Commands,
        radio_node: &schema::RadioButtonNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let style = Self::convert_style(&radio_node.style);
        
        let mut container = commands.spawn(Node{
            flex_direction: FlexDirection::Row,
            align_items: AlignItems::Center,
            ..style
        });

        if let Some(parent) = parent {
            container.set_parent(parent);
        }

        let container_id = container.id();

        // Radio button circle
        let radio_color = if radio_node.checked {
            Color::srgb(0.2, 0.6, 0.9)
        } else {
            Color::srgb(0.3, 0.3, 0.3)
        };

        commands.spawn((
            Button,
            Node{
                width: Val::Px(20.0),
                height: Val::Px(20.0),
                margin: UiRect::right(Val::Px(10.0)),
                border: UiRect::all(Val::Px(2.0)),
                ..default()
            },
            BackgroundColor(radio_color),
            RadioButton {
                group: radio_node.group.clone(),
                checked: radio_node.checked,
                on_change: radio_node.on_change.clone(),
            },
        )).set_parent(container_id);

        // Label
        commands.spawn((
            Text::new(radio_node.label.clone()),
            TextFont {
                font_size: 18.0,
                ..default()
            },
            TextColor(Color::WHITE),
        )).set_parent(container_id);

        Ok(container_id)
    }

    fn spawn_text_input(
        commands: &mut Commands,
        input_node: &schema::TextInputNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let style = Self::convert_style(&input_node.style);
        
        let mut container = commands.spawn((
            Node{
                width: Val::Px(200.0),
                height: Val::Px(30.0),
                padding: UiRect::all(Val::Px(5.0)),
                border: UiRect::all(Val::Px(1.0)),
                ..style
            },
            BackgroundColor(Color::srgb(0.15, 0.15, 0.15)),
            BorderColor(Color::srgb(0.5, 0.5, 0.5)),
            TextInputComponent {
                value: input_node.value.clone(),
                placeholder: input_node.placeholder.clone(),
                on_change: input_node.on_change.clone(),
                focused: false,
            },
        ));

        if let Some(parent) = parent {
            container.set_parent(parent);
        }

        let container_id = container.id();

        // Text display
        let display_text = if input_node.value.is_empty() {
            input_node.placeholder.clone()
        } else {
            input_node.value.clone()
        };

        commands.spawn((
            Text::new(display_text),
            TextFont {
                font_size: 16.0,
                ..default()
            },
            TextColor(Color::srgb(0.8, 0.8, 0.8)),
        )).set_parent(container_id);

        Ok(container_id)
    }

    fn spawn_progress_bar(
        commands: &mut Commands,
        progress_node: &schema::ProgressBarNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let style = Self::convert_style(&progress_node.style);
        let bg_color = progress_node
            .background_color
            .as_ref()
            .map(Self::convert_color)
            .unwrap_or(Color::srgb(0.2, 0.2, 0.2));
        
        let mut container = commands.spawn((
            Node{
                width: Val::Px(200.0),
                height: Val::Px(20.0),
                ..style
            },
            BackgroundColor(bg_color),
            ProgressBarComponent {
                value: progress_node.value,
                max: progress_node.max,
            },
        ));

        if let Some(parent) = parent {
            container.set_parent(parent);
        }

        let container_id = container.id();

        // Progress fill
        let bar_color = progress_node
            .bar_color
            .as_ref()
            .map(Self::convert_color)
            .unwrap_or(Color::srgb(0.2, 0.8, 0.3));

        commands.spawn((
            Node{
                width: Val::Percent((progress_node.value / progress_node.max) * 100.0),
                height: Val::Percent(100.0),
                ..default()
            },
            BackgroundColor(bar_color),
            ProgressBarFill,
        )).set_parent(container_id);

        Ok(container_id)
    }

    fn spawn_mesh3d(
        commands: &mut Commands,
        meshes: &mut ResMut<Assets<Mesh>>,
        materials: &mut ResMut<Assets<StandardMaterial>>,
        asset_server: &AssetServer,
        mesh_node: &schema::Mesh3DNode,
    ) -> Result<Entity> {
        let mesh = Self::create_mesh(&mesh_node.mesh, meshes, asset_server);
        let material = Self::create_material(&mesh_node.material, materials, asset_server);
        let transform = Self::convert_transform(&mesh_node.transform);

        let mut entity = commands.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            transform,
        ));

        // Add animation if present
        if let Some(animation) = &mesh_node.animation {
            use crate::graphics::components::*;
            entity.insert(Animation {
                animation_type: animation.animation_type.clone(),
                duration: animation.duration,
                looping: animation.looping,
                easing: animation.easing.clone(),
                elapsed: 0.0,
            });
        }

        Ok(entity.id())
    }

    fn spawn_light(commands: &mut Commands, light_node: &schema::LightNode) -> Result<Entity> {
        let transform = Self::convert_transform(&light_node.transform);
        let color = light_node
            .color
            .as_ref()
            .map(Self::convert_color)
            .unwrap_or(Color::WHITE);
        let intensity = light_node.intensity.unwrap_or(1000.0);

        let mut entity_cmd = match light_node.light_type {
            schema::LightType::Point => commands
                .spawn((
                    PointLight {
                        color,
                        intensity,
                        ..default()
                    },
                    transform,
                )),
            schema::LightType::Directional => commands
                .spawn((
                    DirectionalLight {
                        color,
                        illuminance: intensity,
                        ..default()
                    },
                    transform,
                )),
            schema::LightType::Spot => commands
                .spawn((
                    SpotLight {
                        color,
                        intensity,
                        ..default()
                    },
                    transform,
                )),
        };

        // Add animation if present
        if let Some(animation) = &light_node.animation {
            use crate::graphics::components::*;
            entity_cmd.insert(Animation {
                animation_type: animation.animation_type.clone(),
                duration: animation.duration,
                looping: animation.looping,
                easing: animation.easing.clone(),
                elapsed: 0.0,
            });
        }

        Ok(entity_cmd.id())
    }

    fn spawn_camera(commands: &mut Commands, camera_node: &schema::CameraNode) -> Result<Entity> {
        let transform = Self::convert_transform(&camera_node.transform);

        let mut entity_cmd = match camera_node.camera_type {
            schema::CameraType::Perspective => commands
                .spawn((Camera3d::default(), transform)),
            schema::CameraType::Orthographic => commands
                .spawn((
                    Camera3d::default(),
                    Projection::Orthographic(OrthographicProjection {
                        scaling_mode: bevy::render::camera::ScalingMode::FixedVertical {
                            viewport_height: 10.0,
                        },
                        ..OrthographicProjection::default_3d()
                    }),
                    transform,
                )),
        };

        // Add animation if present
        if let Some(animation) = &camera_node.animation {
            use crate::graphics::components::*;
            entity_cmd.insert(Animation {
                animation_type: animation.animation_type.clone(),
                duration: animation.duration,
                looping: animation.looping,
                easing: animation.easing.clone(),
                elapsed: 0.0,
            });
        }

        Ok(entity_cmd.id())
    }

    fn spawn_audio(
        commands: &mut Commands,
        asset_server: &AssetServer,
        audio_node: &schema::AudioNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let audio_source = asset_server.load(&audio_node.path);
        
        let mut entity_cmd = commands.spawn(AudioPlayer::new(audio_source));
        
        if audio_node.spatial {
            if let Some(transform) = &audio_node.transform {
                entity_cmd.insert((
                    Self::convert_transform(transform),
                    SpatialAudioComponent,
                ));
            }
        }

        entity_cmd.insert(AudioComponent {
            volume: audio_node.volume,
            looping: audio_node.looping,
            autoplay: audio_node.autoplay,
        });

        Ok(entity_cmd.id())
    }

    fn spawn_particles(
        commands: &mut Commands,
        particle_node: &schema::ParticleNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let transform = Self::convert_transform(&particle_node.transform);
        
        let entity = commands.spawn((
            transform,
            ParticleEmitter {
                emission_rate: particle_node.emission_rate,
                lifetime: particle_node.lifetime,
                color: Self::convert_color(&particle_node.color),
                size: particle_node.size,
                velocity: Vec3::new(
                    particle_node.velocity.x,
                    particle_node.velocity.y,
                    particle_node.velocity.z,
                ),
                gravity: Vec3::new(
                    particle_node.gravity.x,
                    particle_node.gravity.y,
                    particle_node.gravity.z,
                ),
                timer: 0.0,
            },
        )).id();

        Ok(entity)
    }

    fn convert_style(style_def: &schema::StyleDef) -> Node {
        Node {
            width: style_def.width.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            height: style_def.height.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            min_width: style_def.min_width.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            min_height: style_def.min_height.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            max_width: style_def.max_width.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            max_height: style_def.max_height.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            padding: style_def
                .padding
                .as_ref()
                .map(Self::convert_rect)
                .unwrap_or(UiRect::all(Val::Px(0.0))),
            margin: style_def
                .margin
                .as_ref()
                .map(Self::convert_rect)
                .unwrap_or(UiRect::all(Val::Px(0.0))),
            border: style_def
                .border
                .as_ref()
                .map(Self::convert_rect)
                .unwrap_or(UiRect::all(Val::Px(0.0))),
            flex_direction: style_def
                .flex_direction
                .as_ref()
                .map(Self::convert_flex_direction)
                .unwrap_or(FlexDirection::Row),
            justify_content: style_def
                .justify_content
                .as_ref()
                .map(Self::convert_justify_content)
                .unwrap_or(JustifyContent::FlexStart),
            align_items: style_def
                .align_items
                .as_ref()
                .map(Self::convert_align_items)
                .unwrap_or(AlignItems::FlexStart),
            position_type: style_def
                .position_type
                .as_ref()
                .map(Self::convert_position_type)
                .unwrap_or(PositionType::Relative),
            top: style_def.top.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            bottom: style_def.bottom.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            left: style_def.left.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            right: style_def.right.as_ref().map(Self::convert_dimension).unwrap_or(Val::Auto),
            ..default()
        }
    }

    fn convert_dimension(dim: &schema::DimensionDef) -> Val {
        match dim {
            schema::DimensionDef::Pixels(px) => Val::Px(*px),
            schema::DimensionDef::Percent(s) => {
                let num = s.trim_end_matches('%').parse::<f32>().unwrap_or(0.0);
                Val::Percent(num)
            }
            schema::DimensionDef::Auto => Val::Auto,
        }
    }

    fn convert_rect(rect: &schema::RectDef) -> UiRect {
        UiRect {
            top: Val::Px(rect.top),
            bottom: Val::Px(rect.bottom),
            left: Val::Px(rect.left),
            right: Val::Px(rect.right),
        }
    }

    fn convert_color(color: &schema::ColorDef) -> Color {
        Color::srgba(color.r, color.g, color.b, color.a)
    }

    fn convert_flex_direction(dir: &schema::FlexDirection) -> FlexDirection {
        match dir {
            schema::FlexDirection::Row => FlexDirection::Row,
            schema::FlexDirection::Column => FlexDirection::Column,
            schema::FlexDirection::RowReverse => FlexDirection::RowReverse,
            schema::FlexDirection::ColumnReverse => FlexDirection::ColumnReverse,
        }
    }

    fn convert_justify_content(jc: &schema::JustifyContent) -> JustifyContent {
        match jc {
            schema::JustifyContent::FlexStart => JustifyContent::FlexStart,
            schema::JustifyContent::FlexEnd => JustifyContent::FlexEnd,
            schema::JustifyContent::Center => JustifyContent::Center,
            schema::JustifyContent::SpaceBetween => JustifyContent::SpaceBetween,
            schema::JustifyContent::SpaceAround => JustifyContent::SpaceAround,
            schema::JustifyContent::SpaceEvenly => JustifyContent::SpaceEvenly,
        }
    }

    fn convert_align_items(ai: &schema::AlignItems) -> AlignItems {
        match ai {
            schema::AlignItems::FlexStart => AlignItems::FlexStart,
            schema::AlignItems::FlexEnd => AlignItems::FlexEnd,
            schema::AlignItems::Center => AlignItems::Center,
            schema::AlignItems::Stretch => AlignItems::Stretch,
        }
    }

    fn convert_position_type(pt: &schema::PositionType) -> PositionType {
        match pt {
            schema::PositionType::Relative => PositionType::Relative,
            schema::PositionType::Absolute => PositionType::Absolute,
        }
    }

    fn create_mesh(mesh_type: &schema::MeshType, meshes: &mut ResMut<Assets<Mesh>>, asset_server: &AssetServer) -> Handle<Mesh> {
        match mesh_type {
            schema::MeshType::Cube => meshes.add(Cuboid::default()),
            schema::MeshType::Sphere { radius, subdivisions } => {
                meshes.add(Sphere::new(*radius).mesh().uv(*subdivisions, *subdivisions))
            }
            schema::MeshType::Plane { size } => {
                meshes.add(Plane3d::default().mesh().size(*size, *size))
            }
            schema::MeshType::Capsule { radius, depth } => {
                meshes.add(Capsule3d::new(*radius, *depth))
            }
            schema::MeshType::Cylinder { radius, height } => {
                meshes.add(Cylinder::new(*radius, *height))
            }
            schema::MeshType::File { path } => {
                // Load mesh from file (GLTF, OBJ, etc.)
                asset_server.load(path.clone())
            }
        }
    }

    fn create_material(
        material_def: &schema::MaterialDef,
        materials: &mut ResMut<Assets<StandardMaterial>>,
        asset_server: &AssetServer,
    ) -> Handle<StandardMaterial> {
        let mut material = StandardMaterial::default();

        if let Some(base_color) = &material_def.base_color {
            material.base_color = Self::convert_color(base_color);
        }

        if let Some(texture_path) = &material_def.base_color_texture {
            material.base_color_texture = Some(asset_server.load(texture_path.clone()));
        }

        if let Some(emissive) = &material_def.emissive {
            material.emissive = Self::convert_color(emissive).into();
        }

        if let Some(emissive_texture) = &material_def.emissive_texture {
            material.emissive_texture = Some(asset_server.load(emissive_texture.clone()));
        }

        if let Some(metallic) = material_def.metallic {
            material.metallic = metallic;
        }

        if let Some(roughness) = material_def.roughness {
            material.perceptual_roughness = roughness;
        }

        if let Some(mr_texture) = &material_def.metallic_roughness_texture {
            material.metallic_roughness_texture = Some(asset_server.load(mr_texture.clone()));
        }

        if let Some(normal_map) = &material_def.normal_map_texture {
            material.normal_map_texture = Some(asset_server.load(normal_map.clone()));
        }

        materials.add(material)
    }

    fn convert_transform(transform_def: &schema::TransformDef) -> Transform {
        let mut transform = Transform::default();

        if let Some(pos) = &transform_def.position {
            transform.translation = Vec3::new(pos.x, pos.y, pos.z);
        }

        if let Some(rot) = &transform_def.rotation {
            transform.rotation = Quat::from_euler(
                EulerRot::XYZ,
                rot.x.to_radians(),
                rot.y.to_radians(),
                rot.z.to_radians(),
            );
        }

        if let Some(scale) = &transform_def.scale {
            transform.scale = Vec3::new(scale.x, scale.y, scale.z);
        }

        transform
    }
}