# Elpian branding

| File | Use |
|---|---|
| `elpian-logo.png` | The logo, 1024×1024, transparent |
| `elpian-logo-512.png` | The logo, 512×512, transparent (README header) |
| `elpian-social-preview.png` | GitHub social preview, 1280×640 (Settings → General → Social preview) |
| `elpian-avatar.png` | Square avatar on a solid background, 1024×1024 (organization or profile picture) |

The logo is a real 3D render. It shows an isometric **E** built from three
glass UI cards, each with a title line, text and a control: the layered widgets
Elpian renders, stacked on a spine. A glowing **agent orb** circles it on its
orbit, standing for the VM and the AI agents that generate the UI. Its palette
runs from Elpian violet to cyan.

## Re-rendering

`source/scene.html` is the Three.js scene (r169), with physically based
materials, studio environment lighting and soft shadows. `source/render.mjs`
renders it in headless Chromium:

```sh
cd branding/source
npm init -y && npm install three@0.169.0          # the scene imports ./node_modules/three
node render.mjs "" ../elpian-logo.png 1024 1024    # transparent background
node render.mjs "bg=%230d1117" dark.png 1024 1024  # or on a solid colour
```

`source/social.html` composes the social preview from `elpian-logo.png`. Open
it at 1280×640 and take a screenshot.
