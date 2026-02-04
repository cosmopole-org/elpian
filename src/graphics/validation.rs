use crate::graphics::schema::*;
use anyhow::{anyhow, Result};

pub struct JsonValidator;

impl JsonValidator {
    /// Validate a complete scene definition
    pub fn validate_scene(scene: &SceneDef) -> Result<()> {
        // Validate UI nodes
        for (index, node) in scene.ui.iter().enumerate() {
            Self::validate_ui_node(node)
                .map_err(|e| anyhow!("UI node {} validation failed: {}", index, e))?;
        }
        
        // Validate world nodes
        for (index, node) in scene.world.iter().enumerate() {
            Self::validate_world_node(node)
                .map_err(|e| anyhow!("World node {} validation failed: {}", index, e))?;
        }
        
        Ok(())
    }
    
    /// Validate a UI node
    fn validate_ui_node(node: &JsonNode) -> Result<()> {
        match node {
            JsonNode::Container(c) => {
                Self::validate_style(&c.style)?;
                if let Some(color) = &c.background_color {
                    Self::validate_color(color)?;
                }
                for child in &c.children {
                    Self::validate_ui_node(child)?;
                }
            }
            JsonNode::Text(t) => {
                if t.text.is_empty() {
                    return Err(anyhow!("Text node cannot have empty text"));
                }
                Self::validate_style(&t.style)?;
                if let Some(color) = &t.color {
                    Self::validate_color(color)?;
                }
                if let Some(size) = t.font_size {
                    if size <= 0.0 {
                        return Err(anyhow!("Font size must be positive"));
                    }
                }
            }
            JsonNode::Button(b) => {
                if b.label.is_empty() {
                    return Err(anyhow!("Button must have a label"));
                }
                Self::validate_style(&b.style)?;
            }
            JsonNode::Image(i) => {
                if i.path.is_empty() {
                    return Err(anyhow!("Image must have a path"));
                }
                Self::validate_style(&i.style)?;
            }
            JsonNode::Slider(s) => {
                if s.min >= s.max {
                    return Err(anyhow!("Slider min must be less than max"));
                }
                if s.value < s.min || s.value > s.max {
                    return Err(anyhow!("Slider value must be between min and max"));
                }
                Self::validate_style(&s.style)?;
            }
            JsonNode::Checkbox(c) => {
                if c.label.is_empty() {
                    return Err(anyhow!("Checkbox must have a label"));
                }
                Self::validate_style(&c.style)?;
            }
            JsonNode::RadioButton(r) => {
                if r.label.is_empty() {
                    return Err(anyhow!("Radio button must have a label"));
                }
                if r.group.is_empty() {
                    return Err(anyhow!("Radio button must have a group"));
                }
                Self::validate_style(&r.style)?;
            }
            JsonNode::TextInput(t) => {
                Self::validate_style(&t.style)?;
            }
            JsonNode::ProgressBar(p) => {
                if p.max <= 0.0 {
                    return Err(anyhow!("Progress bar max must be positive"));
                }
                if p.value < 0.0 || p.value > p.max {
                    return Err(anyhow!("Progress bar value must be between 0 and max"));
                }
                Self::validate_style(&p.style)?;
            }
            _ => {
                return Err(anyhow!("Invalid node type for UI"));
            }
        }
        Ok(())
    }
    
    /// Validate a world node
    fn validate_world_node(node: &JsonNode) -> Result<()> {
        match node {
            JsonNode::Mesh3D(m) => {
                Self::validate_mesh(&m.mesh)?;
                Self::validate_material(&m.material)?;
                Self::validate_transform(&m.transform)?;
                if let Some(anim) = &m.animation {
                    Self::validate_animation(anim)?;
                }
            }
            JsonNode::Light(l) => {
                if let Some(color) = &l.color {
                    Self::validate_color(color)?;
                }
                if let Some(intensity) = l.intensity {
                    if intensity < 0.0 {
                        return Err(anyhow!("Light intensity cannot be negative"));
                    }
                }
                Self::validate_transform(&l.transform)?;
                if let Some(anim) = &l.animation {
                    Self::validate_animation(anim)?;
                }
            }
            JsonNode::Camera(c) => {
                Self::validate_transform(&c.transform)?;
                if let Some(anim) = &c.animation {
                    Self::validate_animation(anim)?;
                }
            }
            JsonNode::Audio(a) => {
                if a.path.is_empty() {
                    return Err(anyhow!("Audio must have a path"));
                }
                if a.volume < 0.0 || a.volume > 1.0 {
                    return Err(anyhow!("Audio volume must be between 0.0 and 1.0"));
                }
            }
            JsonNode::Particles(p) => {
                if p.emission_rate <= 0.0 {
                    return Err(anyhow!("Particle emission rate must be positive"));
                }
                if p.lifetime <= 0.0 {
                    return Err(anyhow!("Particle lifetime must be positive"));
                }
                if p.size <= 0.0 {
                    return Err(anyhow!("Particle size must be positive"));
                }
                Self::validate_color(&p.color)?;
                Self::validate_transform(&p.transform)?;
            }
            _ => {
                return Err(anyhow!("Invalid node type for world"));
            }
        }
        Ok(())
    }
    
    fn validate_style(_style: &StyleDef) -> Result<()> {
        // Could validate dimensions, etc.
        Ok(())
    }
    
    fn validate_color(color: &ColorDef) -> Result<()> {
        if color.r < 0.0 || color.r > 1.0 {
            return Err(anyhow!("Color red component must be between 0.0 and 1.0"));
        }
        if color.g < 0.0 || color.g > 1.0 {
            return Err(anyhow!("Color green component must be between 0.0 and 1.0"));
        }
        if color.b < 0.0 || color.b > 1.0 {
            return Err(anyhow!("Color blue component must be between 0.0 and 1.0"));
        }
        if color.a < 0.0 || color.a > 1.0 {
            return Err(anyhow!("Color alpha component must be between 0.0 and 1.0"));
        }
        Ok(())
    }
    
    fn validate_mesh(mesh: &MeshType) -> Result<()> {
        match mesh {
            MeshType::Sphere { radius, subdivisions } => {
                if *radius <= 0.0 {
                    return Err(anyhow!("Sphere radius must be positive"));
                }
                if *subdivisions < 3 {
                    return Err(anyhow!("Sphere subdivisions must be at least 3"));
                }
            }
            MeshType::Plane { size } => {
                if *size <= 0.0 {
                    return Err(anyhow!("Plane size must be positive"));
                }
            }
            MeshType::Capsule { radius, depth } => {
                if *radius <= 0.0 || *depth <= 0.0 {
                    return Err(anyhow!("Capsule dimensions must be positive"));
                }
            }
            MeshType::Cylinder { radius, height } => {
                if *radius <= 0.0 || *height <= 0.0 {
                    return Err(anyhow!("Cylinder dimensions must be positive"));
                }
            }
            MeshType::File { path } => {
                if path.is_empty() {
                    return Err(anyhow!("Mesh file path cannot be empty"));
                }
            }
            _ => {}
        }
        Ok(())
    }
    
    fn validate_material(material: &MaterialDef) -> Result<()> {
        if let Some(color) = &material.base_color {
            Self::validate_color(color)?;
        }
        if let Some(emissive) = &material.emissive {
            Self::validate_color(emissive)?;
        }
        if let Some(metallic) = material.metallic {
            if metallic < 0.0 || metallic > 1.0 {
                return Err(anyhow!("Metallic must be between 0.0 and 1.0"));
            }
        }
        if let Some(roughness) = material.roughness {
            if roughness < 0.0 || roughness > 1.0 {
                return Err(anyhow!("Roughness must be between 0.0 and 1.0"));
            }
        }
        Ok(())
    }
    
    fn validate_transform(_transform: &TransformDef) -> Result<()> {
        // Could validate scale is not zero, etc.
        Ok(())
    }
    
    fn validate_animation(animation: &AnimationDef) -> Result<()> {
        if animation.duration < 0.0 {
            return Err(anyhow!("Animation duration cannot be negative"));
        }
        
        match &animation.animation_type {
            AnimationType::Rotate { axis, degrees } => {
                let len = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).sqrt();
                if len < 0.001 {
                    return Err(anyhow!("Rotation axis cannot be zero vector"));
                }
                if *degrees == 0.0 {
                    return Err(anyhow!("Rotation degrees cannot be zero"));
                }
            }
            AnimationType::Scale { from, to } => {
                if from.x <= 0.0 || from.y <= 0.0 || from.z <= 0.0 ||
                   to.x <= 0.0 || to.y <= 0.0 || to.z <= 0.0 {
                    return Err(anyhow!("Scale values must be positive"));
                }
            }
            AnimationType::Bounce { height } => {
                if *height <= 0.0 {
                    return Err(anyhow!("Bounce height must be positive"));
                }
            }
            AnimationType::Pulse { min_scale, max_scale } => {
                if *min_scale <= 0.0 || *max_scale <= 0.0 {
                    return Err(anyhow!("Pulse scale values must be positive"));
                }
                if *min_scale >= *max_scale {
                    return Err(anyhow!("Pulse min_scale must be less than max_scale"));
                }
            }
            _ => {}
        }
        
        Ok(())
    }
}
