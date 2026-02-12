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
            
            // Material Design UI Elements
            schema::JsonNode::FloatingActionButton(fab) => Self::spawn_fab(commands, asset_server, fab, parent),
            schema::JsonNode::Card(card) => Self::spawn_card(commands, asset_server, card, parent),
            schema::JsonNode::Chip(chip) => Self::spawn_chip(commands, asset_server, chip, parent),
            schema::JsonNode::AppBar(appbar) => Self::spawn_appbar(commands, asset_server, appbar, parent),
            schema::JsonNode::Dialog(dialog) => Self::spawn_dialog(commands, asset_server, dialog, parent),
            schema::JsonNode::Menu(menu) => Self::spawn_menu(commands, menu, parent),
            schema::JsonNode::BottomSheet(sheet) => Self::spawn_bottom_sheet(commands, asset_server, sheet, parent),
            schema::JsonNode::Snackbar(snack) => Self::spawn_snackbar(commands, snack, parent),
            schema::JsonNode::Switch(switch) => Self::spawn_switch(commands, switch, parent),
            schema::JsonNode::Tabs(tabs) => Self::spawn_tabs(commands, asset_server, tabs, parent),
            schema::JsonNode::Badge(badge) => Self::spawn_badge(commands, badge, parent),
            schema::JsonNode::Tooltip(tooltip) => Self::spawn_tooltip(commands, tooltip, parent),
            schema::JsonNode::Rating(rating) => Self::spawn_rating(commands, rating, parent),
            schema::JsonNode::SegmentedButton(seg) => Self::spawn_segmented_button(commands, seg, parent),
            schema::JsonNode::IconButton(icon) => Self::spawn_icon_button(commands, asset_server, icon, parent),
            schema::JsonNode::Divider(div) => Self::spawn_divider(commands, div, parent),
            schema::JsonNode::List(list) => Self::spawn_list(commands, asset_server, list, parent),
            schema::JsonNode::Drawer(drawer) => Self::spawn_drawer(commands, asset_server, drawer, parent),
            
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
            
            // 3D Game Elements
            schema::JsonNode::Terrain(terrain) => Self::spawn_terrain(commands, meshes, materials, terrain),
            schema::JsonNode::Skybox(skybox) => Self::spawn_skybox(commands, asset_server, skybox),
            schema::JsonNode::Foliage(foliage) => Self::spawn_foliage(commands, meshes, materials, asset_server, foliage),
            schema::JsonNode::Decal(decal) => Self::spawn_decal(commands, asset_server, decal),
            schema::JsonNode::Billboard(billboard) => Self::spawn_billboard(commands, asset_server, billboard),
            schema::JsonNode::Water(water) => Self::spawn_water(commands, meshes, materials, water),
            schema::JsonNode::RigidBody(rb) => Self::spawn_rigidbody(commands, meshes, materials, asset_server, rb),
            schema::JsonNode::Environment(env) => Self::spawn_environment(commands, env),
            
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
        let normal_rgba = button_node
            .normal_color
            .as_ref()
            .map(|c| [c.r, c.g, c.b, c.a])
            .unwrap_or([0.15, 0.15, 0.15, 1.0]);

        let mut button_entity = commands.spawn((
            Button,
            Node{
                padding: UiRect::all(Val::Px(15.0)),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..style
            },
            // Use rounded background marker so apply_ui_images_system can convert to image+shadow
            crate::graphics::components::RoundedBackground {
                color: normal_color,
                color_rgba: normal_rgba,
                corner_radius: 8.0,
                elevation: 1,
                glass: button_node.glass,
                glass_opacity: button_node.glass_opacity,
            },
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

    // ===== MATERIAL DESIGN UI SPAWN FUNCTIONS =====

    fn spawn_fab(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        fab_node: &schema::FABNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&fab_node.style);
        let color = fab_node.color.as_ref().map(Self::convert_color).unwrap_or(Color::srgb(0.2, 0.6, 1.0));
        let fab_rgba = fab_node.color.as_ref().map(|c| [c.r, c.g, c.b, c.a]).unwrap_or([0.2, 0.6, 1.0, 1.0]);

        let size = match fab_node.fab_type {
            schema::FABType::Small => (40.0, 40.0),
            schema::FABType::Large => (96.0, 96.0),
            _ => (56.0, 56.0),
        };

        let mut entity = commands.spawn((
            Button,
            Node {
                width: Val::Px(size.0),
                height: Val::Px(size.1),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..style
            },
            // Use rounded background for FAB to support shadows and circular shape
            crate::graphics::components::RoundedBackground {
                color,
                color_rgba: fab_rgba,
                corner_radius: (size.0 / 2.0) as f32,
                elevation: fab_node.elevation,
                glass: fab_node.glass,
                glass_opacity: fab_node.glass_opacity,
            },
            FloatingActionButton {
                action: fab_node.action.clone(),
                fab_type: format!("{:?}", fab_node.fab_type),
                hovered: false,
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let id = entity.id();
        // Add elevation component for shadowing
        commands.entity(id).insert(Elevation {
            level: fab_node.elevation,
            shadow_blur: 6.0,
            shadow_offset: Vec2::new(0.0, -3.0),
        });

        Ok(id)
    }

    fn spawn_card(
        commands: &mut Commands,
        asset_server: &AssetServer,
        card_node: &schema::CardNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&card_node.style);
        let bg_color = card_node.background_color.as_ref().map(Self::convert_color).unwrap_or(Color::srgb(0.95, 0.95, 0.95));
        let bg_rgba = card_node.background_color.as_ref().map(|c| [c.r, c.g, c.b, c.a]).unwrap_or([0.95, 0.95, 0.95, 1.0]);

        let mut entity = commands.spawn((
            Node { ..style },
            BorderColor(if card_node.outlined { Color::srgb(0.7, 0.7, 0.7) } else { Color::NONE }),
            Card {
                elevation: card_node.elevation,
                corner_radius: card_node.corner_radius,
                on_click: card_node.on_click.clone(),
                outlined: card_node.outlined,
            },
            // mark for later replacement with rounded image background
            crate::graphics::components::RoundedBackground {
                color: bg_color,
                color_rgba: bg_rgba,
                corner_radius: card_node.corner_radius,
                elevation: card_node.elevation,
                glass: card_node.glass,
                glass_opacity: card_node.glass_opacity,
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let card_id = entity.id();

        // Apply elevation component for visual shadowing
        commands.entity(card_id).insert(Elevation {
            level: card_node.elevation,
            shadow_blur: 4.0,
            shadow_offset: Vec2::new(0.0, -2.0),
        });

        // Spawn children
        for child in &card_node.children {
            Self::spawn_ui(commands, asset_server, child, Some(card_id))?;
        }

        Ok(card_id)
    }

    fn spawn_chip(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        chip_node: &schema::ChipNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&chip_node.style);
        let color = chip_node.color.as_ref().map(Self::convert_color).unwrap_or(Color::srgb(0.3, 0.3, 0.3));

        let mut entity = commands.spawn((
            Button,
            Node {
                padding: UiRect::all(Val::Px(12.0)),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..style
            },
            BackgroundColor(color),
            Chip {
                chip_type: format!("{:?}", chip_node.chip_type),
                selected: chip_node.selected,
                on_click: chip_node.on_click.clone(),
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let chip_id = entity.id();

        // Add label
        commands.spawn((
            Text::new(chip_node.label.clone()),
            TextFont { font_size: 14.0, ..default() },
            TextColor(Color::WHITE),
        )).set_parent(chip_id);

        Ok(chip_id)
    }

    fn spawn_appbar(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        appbar_node: &schema::AppBarNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&appbar_node.style);
        let bg_color = appbar_node.background_color.as_ref().map(Self::convert_color).unwrap_or(Color::srgb(0.1, 0.5, 0.9));
        let appbar_rgba = appbar_node.background_color.as_ref().map(|c| [c.r, c.g, c.b, c.a]).unwrap_or([0.1, 0.5, 0.9, 1.0]);

        let mut entity = commands.spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Px(56.0),
                padding: UiRect::horizontal(Val::Px(16.0)),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..style
            },
            // Use image-based background to allow rounded corners and shadow
            crate::graphics::components::RoundedBackground {
                color: bg_color,
                color_rgba: appbar_rgba,
                corner_radius: 0.0,
                elevation: appbar_node.elevation,
                glass: appbar_node.glass,
                glass_opacity: appbar_node.glass_opacity,
            },
            AppBar {
                app_bar_type: format!("{:?}", appbar_node.app_bar_type),
                title: appbar_node.title.clone(),
                elevation: appbar_node.elevation,
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let appbar_id = entity.id();

        // Add elevation component for app bar
        commands.entity(appbar_id).insert(Elevation {
            level: appbar_node.elevation,
            shadow_blur: 3.0,
            shadow_offset: Vec2::new(0.0, -1.0),
        });

        // Add title
        commands.spawn((
            Text::new(appbar_node.title.clone()),
            TextFont { font_size: 20.0, ..default() },
            TextColor(Color::WHITE),
        )).set_parent(appbar_id);

        Ok(appbar_id)
    }

    fn spawn_dialog(
        commands: &mut Commands,
        asset_server: &AssetServer,
        dialog_node: &schema::DialogNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&dialog_node.style);

        let mut entity = commands.spawn((
            Node {
                width: Val::Px(400.0),
                height: Val::Auto,
                flex_direction: FlexDirection::Column,
                padding: UiRect::all(Val::Px(24.0)),
                ..style
            },
            // use rounded image background + optional glass overlay
            crate::graphics::components::RoundedBackground {
                color: Color::srgb(0.95, 0.95, 0.95),
                color_rgba: [0.95, 0.95, 0.95, 1.0],
                corner_radius: 12.0,
                elevation: 4,
                glass: dialog_node.glass,
                glass_opacity: dialog_node.glass_opacity,
            },
            Dialog {
                title: dialog_node.title.clone(),
                dismissible: dialog_node.dismissible,
                open: true,
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let dialog_id = entity.id();

        // Add title
        commands.spawn((
            Text::new(dialog_node.title.clone()),
            TextFont { font_size: 18.0, ..default() },
            TextColor(Color::BLACK),
        )).set_parent(dialog_id);

        // Add content
        for content in &dialog_node.content {
            Self::spawn_ui(commands, asset_server, content, Some(dialog_id))?;
        }

        Ok(dialog_id)
    }

    fn spawn_menu(
        commands: &mut Commands,
        menu_node: &schema::MenuNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&menu_node.style);

        let mut entity = commands.spawn((
            Node {
                flex_direction: FlexDirection::Column,
                ..style
            },
            crate::graphics::components::RoundedBackground {
                color: Color::srgb(0.98, 0.98, 0.98),
                color_rgba: [0.98, 0.98, 0.98, 1.0],
                corner_radius: 8.0,
                elevation: menu_node.elevation,
                glass: menu_node.glass,
                glass_opacity: menu_node.glass_opacity,
            },
            Menu {
                elevation: menu_node.elevation,
                open: true,
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        Ok(entity.id())
    }

    fn spawn_bottom_sheet(
        commands: &mut Commands,
        asset_server: &AssetServer,
        sheet_node: &schema::BottomSheetNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&sheet_node.style);

        let mut entity = commands.spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Px(sheet_node.height.unwrap_or(300.0)),
                flex_direction: FlexDirection::Column,
                position_type: PositionType::Absolute,
                bottom: Val::Px(0.0),
                ..style
            },
            BackgroundColor(Color::srgb(0.98, 0.98, 0.98)),
            BottomSheet {
                height: sheet_node.height,
                dismissible: sheet_node.dismissible,
                open: true,
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let sheet_id = entity.id();

        // Spawn content
        for content in &sheet_node.content {
            Self::spawn_ui(commands, asset_server, content, Some(sheet_id))?;
        }

        Ok(sheet_id)
    }

    fn spawn_snackbar(
        commands: &mut Commands,
        snack_node: &schema::SnackbarNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&snack_node.style);

        let mut entity = commands.spawn((
            Node {
                width: Val::Px(300.0),
                height: Val::Px(48.0),
                position_type: PositionType::Absolute,
                bottom: Val::Px(20.0),
                left: Val::Px(20.0),
                padding: UiRect::all(Val::Px(16.0)),
                align_items: AlignItems::Center,
                ..style
            },
            // use rounded background so shadow and glass can be applied
            crate::graphics::components::RoundedBackground {
                color: Color::srgb(0.32, 0.32, 0.32),
                color_rgba: [0.32, 0.32, 0.32, 1.0],
                corner_radius: 8.0,
                elevation: 2,
                glass: snack_node.glass,
                glass_opacity: snack_node.glass_opacity,
            },
            Snackbar {
                message: snack_node.message.clone(),
                duration_ms: snack_node.duration_ms,
                elapsed_ms: 0,
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let snack_id = entity.id();

        // Add message
        commands.spawn((
            Text::new(snack_node.message.clone()),
            TextFont { font_size: 14.0, ..default() },
            TextColor(Color::WHITE),
        )).set_parent(snack_id);

        Ok(snack_id)
    }

    fn spawn_switch(
        commands: &mut Commands,
        switch_node: &schema::SwitchNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&switch_node.style);

        let bg_color = if switch_node.enabled {
            Color::srgb(0.2, 0.8, 0.3)
        } else {
            Color::srgb(0.7, 0.7, 0.7)
        };

        let mut entity = commands.spawn((
            Button,
            Node {
                width: Val::Px(50.0),
                height: Val::Px(26.0),
                ..style
            },
            BackgroundColor(bg_color),
            SwitchComponent {
                enabled: switch_node.enabled,
                on_change: switch_node.on_change.clone(),
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        Ok(entity.id())
    }

    fn spawn_tabs(
        commands: &mut Commands,
        asset_server: &AssetServer,
        tabs_node: &schema::TabsNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&tabs_node.style);

        let mut entity = commands.spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Auto,
                flex_direction: FlexDirection::Column,
                ..style
            },
            BackgroundColor(Color::srgb(0.98, 0.98, 0.98)),
            Tabs {
                selected_index: tabs_node.selected_index,
                tab_count: tabs_node.tabs.len(),
                on_change: tabs_node.on_change.clone(),
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let tabs_id = entity.id();

        // Spawn tabs
        for (index, tab) in tabs_node.tabs.iter().enumerate() {
            commands.spawn((
                Button,
                Node {
                    padding: UiRect::all(Val::Px(12.0)),
                    ..default()
                },
                BackgroundColor(if index == tabs_node.selected_index {
                    Color::srgb(0.2, 0.6, 1.0)
                } else {
                    Color::srgb(0.85, 0.85, 0.85)
                }),
            )).set_parent(tabs_id);

            // Spawn tab content
            for content in &tab.content {
                Self::spawn_ui(commands, asset_server, content, Some(tabs_id))?;
            }
        }

        Ok(tabs_id)
    }

    fn spawn_badge(
        commands: &mut Commands,
        badge_node: &schema::BadgeNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&badge_node.style);
        let color = badge_node.color.as_ref().map(Self::convert_color).unwrap_or(Color::srgb(1.0, 0.0, 0.0));

        let mut entity = commands.spawn((
            Node {
                width: Val::Px(24.0),
                height: Val::Px(24.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..style
            },
            BackgroundColor(color),
            Badge {
                count: badge_node.count,
                label: badge_node.label.clone(),
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let badge_id = entity.id();

        let display_text = badge_node.count.map(|c| c.to_string()).unwrap_or(badge_node.label.clone());
        commands.spawn((
            Text::new(display_text),
            TextFont { font_size: 12.0, ..default() },
            TextColor(Color::WHITE),
        )).set_parent(badge_id);

        Ok(badge_id)
    }

    fn spawn_tooltip(
        commands: &mut Commands,
        tooltip_node: &schema::TooltipNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&tooltip_node.style);

        let mut entity = commands.spawn((
            Node {
                padding: UiRect::all(Val::Px(8.0)),
                ..style
            },
            crate::graphics::components::RoundedBackground {
                color: Color::srgb(0.3, 0.3, 0.3),
                color_rgba: [0.3, 0.3, 0.3, 1.0],
                corner_radius: 6.0,
                elevation: 1,
                glass: tooltip_node.glass,
                glass_opacity: tooltip_node.glass_opacity,
            },
            Tooltip {
                message: tooltip_node.message.clone(),
                visible: true,
                position: format!("{:?}", tooltip_node.position),
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        let tooltip_id = entity.id();

        commands.spawn((
            Text::new(tooltip_node.message.clone()),
            TextFont { font_size: 12.0, ..default() },
            TextColor(Color::WHITE),
        )).set_parent(tooltip_id);

        Ok(tooltip_id)
    }

    fn spawn_rating(
        commands: &mut Commands,
        rating_node: &schema::RatingNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&rating_node.style);

        let mut entity = commands.spawn((
            Node {
                flex_direction: FlexDirection::Row,
                ..style
            },
            BackgroundColor(Color::NONE),
            Rating {
                value: rating_node.value,
                max: rating_node.max,
                on_change: rating_node.on_change.clone(),
                read_only: rating_node.read_only,
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        Ok(entity.id())
    }

    fn spawn_segmented_button(
        commands: &mut Commands,
        seg_node: &schema::SegmentedButtonNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&seg_node.style);

        let mut entity = commands.spawn((
            Node {
                flex_direction: FlexDirection::Row,
                ..style
            },
            BackgroundColor(Color::srgb(0.85, 0.85, 0.85)),
            SegmentedButton {
                selected_index: seg_node.selected_index,
                option_count: seg_node.options.len(),
                multiple_selection: seg_node.multiple_selection,
                on_change: seg_node.on_change.clone(),
            },
        ));

        if let Some(parent) = parent {
            entity.set_parent(parent);
        }

        Ok(entity.id())
    }

    fn spawn_icon_button(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        icon_node: &schema::IconButtonNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&icon_node.style);

        let entity_id = commands.spawn((
            Button,
            Node {
                width: Val::Px(40.0),
                height: Val::Px(40.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..style
            },
            BackgroundColor(Color::NONE),
            IconButton {
                icon: icon_node.icon.clone(),
                action: icon_node.action.clone(),
                hovered: false,
            },
        )).id();

        if let Some(parent) = parent {
            commands.entity(entity_id).set_parent(parent);
        }

        // Optionally add tooltip text as a child (if provided)
        if let Some(tt) = &icon_node.tooltip {
            commands.spawn((
                Text::new(tt.clone()),
                TextFont { font_size: 12.0, ..default() },
                TextColor(Color::WHITE),
            )).set_parent(entity_id);
        }

        Ok(entity_id)
    }

    fn spawn_divider(
        commands: &mut Commands,
        div_node: &schema::DividerNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&div_node.style);

        let color = div_node.color.as_ref().map(Self::convert_color).unwrap_or(Color::srgb(0.6, 0.6, 0.6));
        let thickness = if div_node.thickness <= 0.0 { 1.0 } else { div_node.thickness };

        let entity_id = commands.spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Px(thickness),
                ..style
            },
            BackgroundColor(color),
            Divider { thickness, color },
        )).id();

        if let Some(parent) = parent {
            commands.entity(entity_id).set_parent(parent);
        }

        Ok(entity_id)
    }

    fn spawn_list(
        commands: &mut Commands,
        asset_server: &AssetServer,
        list_node: &schema::ListNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&list_node.style);

        let list_id = commands.spawn((
            Node { flex_direction: FlexDirection::Column, ..style },
            BackgroundColor(Color::NONE),
            ListComponent { item_count: list_node.items.len() },
        )).id();

        if let Some(parent) = parent {
            commands.entity(list_id).set_parent(parent);
        }

        for item in &list_node.items {
            Self::spawn_ui(commands, asset_server, item, Some(list_id))?;
        }

        Ok(list_id)
    }

    fn spawn_drawer(
        commands: &mut Commands,
        asset_server: &AssetServer,
        drawer_node: &schema::DrawerNode,
        parent: Option<Entity>,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        let style = Self::convert_style(&drawer_node.style);

        let width = drawer_node.width.unwrap_or(300.0);

        let node = Node {
            width: Val::Px(width),
            height: Val::Percent(100.0),
            position_type: PositionType::Absolute,
            left: if drawer_node.open { Val::Px(0.0) } else { Val::Px(-width) },
            top: Val::Px(0.0),
            ..style
        };

        let drawer_id = commands.spawn((
            node,
            BackgroundColor(Color::srgb(0.98, 0.98, 0.98)),
            Drawer { open: drawer_node.open, width },
        )).id();

        if let Some(parent) = parent {
            commands.entity(drawer_id).set_parent(parent);
        }

        for child in &drawer_node.content {
            Self::spawn_ui(commands, asset_server, child, Some(drawer_id))?;
        }

        Ok(drawer_id)
    }

    // ===== 3D GAME ELEMENT SPAWN FUNCTIONS =====

    fn spawn_terrain(
        commands: &mut Commands,
        meshes: &mut ResMut<Assets<Mesh>>,
        materials: &mut ResMut<Assets<StandardMaterial>>,
        terrain_node: &schema::TerrainNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let mesh = meshes.add(Plane3d::default().mesh().size(terrain_node.size, terrain_node.size));
        let mut material = StandardMaterial::default();
        if let Some(color) = &terrain_node.material.base_color {
            material.base_color = Self::convert_color(color);
        }
        let transform = Self::convert_transform(&terrain_node.transform);

        let mut entity = commands.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(materials.add(material)),
            transform,
            Terrain {
                size: terrain_node.size,
                height: terrain_node.height,
                subdivisions: terrain_node.subdivisions,
            },
        ));

        if let Some(physics) = &terrain_node.physics {
            entity.insert(Physics {
                mass: physics.mass,
                friction: physics.friction,
                restitution: physics.restitution,
                gravity_scale: physics.gravity_scale,
                use_gravity: physics.use_gravity,
                collider_type: format!("{:?}", physics.collider_type),
            });
        }

        Ok(entity.id())
    }

    fn spawn_skybox(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        skybox_node: &schema::SkyboxNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let transform = if let Some(rot) = &skybox_node.rotation {
            Transform {
                rotation: Quat::from_euler(
                    EulerRot::XYZ,
                    rot.x.to_radians(),
                    rot.y.to_radians(),
                    rot.z.to_radians(),
                ),
                ..default()
            }
        } else {
            Transform::default()
        };

        let entity = commands.spawn((
            transform,
            SkyboxComponent {
                rotation: transform.rotation,
                brightness: skybox_node.brightness,
            },
        )).id();

        Ok(entity)
    }

    fn spawn_foliage(
        commands: &mut Commands,
        meshes: &mut ResMut<Assets<Mesh>>,
        materials: &mut ResMut<Assets<StandardMaterial>>,
        _asset_server: &AssetServer,
        foliage_node: &schema::FoliageNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let mesh = meshes.add(Plane3d::default());
        let mut material = StandardMaterial::default();
        if let Some(color) = &foliage_node.material.base_color {
            material.base_color = Self::convert_color(color);
        }
        let transform = Self::convert_transform(&foliage_node.transform);

        let entity = commands.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(materials.add(material)),
            transform,
            Foliage {
                foliage_type: format!("{:?}", foliage_node.foliage_type),
                density: foliage_node.density,
                color_variation: foliage_node.color_variation,
            },
        )).id();

        Ok(entity)
    }

    fn spawn_decal(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        decal_node: &schema::DecalNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let transform = Self::convert_transform(&decal_node.transform);

        let entity = commands.spawn((
            transform,
            Decal {
                size: Vec3::new(decal_node.size.x, decal_node.size.y, decal_node.size.z),
                sort_order: decal_node.sort_order,
            },
        )).id();

        Ok(entity)
    }

    fn spawn_billboard(
        commands: &mut Commands,
        _asset_server: &AssetServer,
        billboard_node: &schema::BillboardNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let transform = Self::convert_transform(&billboard_node.transform);

        let entity = commands.spawn((
            transform,
            Billboard {
                billboard_type: format!("{:?}", billboard_node.billboard_type),
                size: Vec3::new(billboard_node.size.x, billboard_node.size.y, billboard_node.size.z),
            },
        )).id();

        Ok(entity)
    }

    fn spawn_water(
        commands: &mut Commands,
        meshes: &mut ResMut<Assets<Mesh>>,
        materials: &mut ResMut<Assets<StandardMaterial>>,
        water_node: &schema::WaterNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let mesh = meshes.add(Plane3d::default().mesh().size(water_node.size.x, water_node.size.z));
        let mut material = StandardMaterial::default();
        if let Some(color) = &water_node.water_color {
            material.base_color = Self::convert_color(color);
        } else {
            material.base_color = Color::srgba(0.0, 0.5, 1.0, water_node.transparency);
        }
        let transform = Self::convert_transform(&water_node.transform);

        let entity = commands.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(materials.add(material)),
            transform,
            Water {
                wave_amplitude: water_node.wave_amplitude,
                wave_frequency: water_node.wave_frequency,
                wave_speed: 1.0,
                elapsed_time: 0.0,
            },
        )).id();

        Ok(entity)
    }

    fn spawn_rigidbody(
        commands: &mut Commands,
        meshes: &mut ResMut<Assets<Mesh>>,
        materials: &mut ResMut<Assets<StandardMaterial>>,
        asset_server: &AssetServer,
        rb_node: &schema::RigidBodyNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let mesh = Self::create_mesh(&rb_node.mesh, meshes, asset_server);
        let material = Self::create_material(&rb_node.material, materials, asset_server);
        let transform = Self::convert_transform(&rb_node.transform);

        let entity = commands.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            transform,
            RigidBodyComponent {
                mass: rb_node.physics.mass,
                velocity: Vec3::ZERO,
                angular_velocity: Vec3::ZERO,
            },
            Physics {
                mass: rb_node.physics.mass,
                friction: rb_node.physics.friction,
                restitution: rb_node.physics.restitution,
                gravity_scale: rb_node.physics.gravity_scale,
                use_gravity: rb_node.physics.use_gravity,
                collider_type: format!("{:?}", rb_node.physics.collider_type),
            },
        )).id();

        Ok(entity)
    }

    fn spawn_environment(
        commands: &mut Commands,
        env_node: &schema::EnvironmentNode,
    ) -> Result<Entity> {
        use crate::graphics::components::*;
        
        let entity = commands.spawn(Environment {
            ambient_light_intensity: env_node.ambient_intensity,
            fog_enabled: env_node.fog_enabled,
            fog_distance: env_node.fog_distance,
        }).id();

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
            schema::MeshType::Cone { radius, height } => {
                meshes.add(Cone::new(*radius, *height))
            }
            schema::MeshType::Torus { radius, tube_radius } => {
                meshes.add(Torus::new(*radius, *tube_radius))
            }
            schema::MeshType::Icosphere { radius, subdivisions } => {
                meshes.add(Sphere::new(*radius).mesh().uv(*subdivisions, *subdivisions))
            }
            schema::MeshType::UvSphere { radius, sectors, stacks } => {
                meshes.add(Sphere::new(*radius).mesh().uv(*sectors, *stacks))
            }
            schema::MeshType::Grid { width, height, spacing } => {
                meshes.add(Plane3d::default().mesh().size((*width as f32) * spacing, (*height as f32) * spacing))
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

        // Additional PBR properties
        if let Some(ao_texture) = &material_def.ambient_occlusion_texture {
            material.occlusion_texture = Some(asset_server.load(ao_texture.clone()));
        }

        if let Some(_height_map) = &material_def.height_map_texture {
            // Parallax mapping would be implemented here with custom shaders
            if let Some(_parallax) = material_def.parallax_depth {
                // This is a placeholder; actual parallax mapping needs custom shader support
                material.perceptual_roughness = (material.perceptual_roughness * 0.9).min(1.0);
            }
        }

        if let Some(ior) = material_def.ior {
            // Store IOR for potential future use
            // Bevy's StandardMaterial doesn't directly support IOR, but this can be used with custom shaders
            material.metallic = (material.metallic * (1.0 - (ior - 1.0).abs().min(0.1))).max(0.0);
        }

        if material_def.double_sided {
            material.cull_mode = None; // Disable back-face culling
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