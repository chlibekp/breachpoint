BREACHPOINT — Master Build Prompt
Nov 23, 2026 · @Petr Chlíbek
1. Your role and how to use this prompt
You are the lead engineer, technical artist and art director for BREACHPOINT, a 5v5 tactical hero shooter built in Godot 4 with an authoritative Node.js multiplayer server, playable both as a desktop build and in the browser. Treat this document as the complete specification. Where it is silent, make the choice a senior developer at a top tactical-shooter studio would make, and write that choice down in docs/DECISIONS.md.
Priority order when trade-offs collide:
1.  Visual quality — models, textures, materials, lighting and readability. This is the number-one priority. The game must look like a finished, polished commercial tactical shooter, not a prototype.
2.  Game feel — crisp movement, precise hitreg, punchy weapons, instant feedback.
3.  Competitive integrity — authoritative server, fair netcode, readable silhouettes.
4.  Browser support — the same game runs in a modern browser with a scaled fidelity tier.
5.  Feature breadth — more agents, maps and modes come last.
Reference images. I will attach reference images alongside this prompt. Use them like this:
• Study them for style, not for copying. Extract shape language, palette, value structure, material treatment, level of detail and lighting mood.
• Before producing any asset category (agents, weapons, a map, UI), write a short style note in docs/art/ that names which references you used and what you took from each (for example "rounded bevels and flat painted albedo from ref 03; warm sun / cool shadow split from ref 07").
• When a reference conflicts with this document, this document wins on gameplay and readability; the reference wins on look and feel.
• Never trace, rip or recreate any specific asset from another game. Every model, texture, icon, sound and name must be original.
Working rules for you, the building AI:
• Work in milestones (section 18). Do not move on until the current milestone runs, looks right and passes its checklist.
• After every milestone, capture screenshots of each map from fixed camera bookmarks and compare them against the reference images and the art bible (section 4). Fix anything that looks placeholder, flat, noisy or muddy before continuing.
• Never ship grey-box or programmer art in a milestone marked "art complete". Grey-box is allowed only in the blockout phase and must be tagged BLOCKOUT_ so it is easy to find.
• Keep everything data-driven: agents, abilities, weapons, maps and economy values live in resource/JSON files shared by the client and the server.
• Ask me before changing anything in sections 2, 4 or 10.
2. Vision, pillars and originality
BREACHPOINT is a round-based 5v5 tactical shooter. Precise gunplay decides fights; agent abilities create the openings. Attackers plant a Breach Charge on one of two or three sites; defenders stop the plant or defuse it. It should feel like a top-tier tactical hero shooter in the same genre as Valorant: clean, stylized, bright, readable and expensive-looking.
Setting. Near-future Earth, around 2040. A dimensional event called the Fracture left "Rift energy" seeping into cities. Agents are elite operatives from a global task force, PRISM, who use Rift-infused tech. Maps are real-world-inspired places with one sci-fi twist each.
Pillars:
1.  Gunplay first. Every kill is earned by aim and positioning. Abilities never deal more damage than a rifle body shot, and none kill reliably on their own.
2.  Readability over realism. At any distance and in any lighting, an enemy player must be the highest-contrast thing on screen. The environment never camouflages a character.
3.  Stylized premium. Hand-crafted, painterly-clean materials on sharp, chunky, bevelled forms. Never photoreal, never cartoony, never cheap.
4.  Instant clarity. HUD, sounds and VFX tell the player exactly what happened, where and by whom, in under 200 ms.
5.  Runs everywhere. A mid-range laptop at 144 fps on desktop and 60 fps in Chrome at the browser tier.
Target feel, in one line: a stylized tactical shooter with crisp hand-painted PBR surfaces, bold silhouettes, warm sunlight against cool shadows, and weapons that snap.
Originality and IP rules (mandatory):
• Do not use any Riot Games or Valorant names, agents, ability names, map names, weapon names (Vandal, Phantom, Operator and so on), logos, UI layouts copied pixel-for-pixel, fonts, sounds, music or ripped assets.
• Genre conventions are fine: buy phase, bomb plant/defuse, ability charges, ultimate points, 13-round halves, tagging slows, headshot multipliers.
• All names in this document (BREACHPOINT, PRISM, Breach Charge, agent, weapon and map names) are original placeholders I own. Use them.
• Fonts: use open-licence fonts only (for example Rajdhani, Chakra Petch, Barlow Condensed, Inter). Record each font and licence in docs/CREDITS.md.
• Any third-party asset (CC0 textures from ambientCG/Poly Haven, CC0 sounds) must be logged in docs/CREDITS.md with source URL and licence, and must be restyled to match the art bible, never used raw.
3. Tech stack and platform targets
One Godot project ships two builds from the same scenes: a desktop build on the Forward+ renderer and a browser build on the Compatibility (WebGL2) renderer. Godot's web export only supports the Compatibility renderer, so the art must be built to look great without Forward+-only features, then gain extra polish on desktop.
Layer
Choice
Notes
Engine
Godot 4.x, latest stable (4.5 or newer)
Pin the exact version in README.md and .godot-version.
Client language
GDScript, statically typed
No C#: .NET web export is not production-ready. Hot paths may move to GDExtension (C++) later, compiled for web too.
Desktop renderer
Forward+
Windows and Linux first, macOS after.
Web renderer
GL Compatibility (WebGL2)
Set with the per-platform override rendering/renderer/rendering_method.web = gl_compatibility.
Server
Node.js 22 LTS + TypeScript
Authoritative game server, separate from the client.
Transport
WebSocket (binary) for every client
Browsers cannot use ENet/UDP. Phase 2: optional WebRTC unreliable data channels for movement.
Shared data
JSON schemas in /shared
Weapons, agents, abilities, maps, economy. Read by both Godot and Node.
Database
PostgreSQL + Redis
Accounts, match history, matchmaking queues.
Hosting
Docker containers; static web build behind a CDN
See section 14.
Renderer strategy — build for the Compatibility renderer first.
• Every map, material and VFX must look finished in the Compatibility renderer. Desktop Forward+ adds SSAO, SSIL, SSR, volumetric fog, better shadows and glow on top. It never replaces missing baked lighting.
• Lighting is mainly baked (LightmapGI) plus a few real-time lights. This is also how stylized tactical shooters stay sharp and fast. Check lightmap rendering in the Compatibility renderer on your exact Godot version during milestone 1 and record the result in DECISIONS.md.
• Use a QualityManager autoload that detects the platform and sets the fidelity tier (section 9). No scene may assume Forward+ features exist.
• Write custom shaders so they compile on both renderers. Avoid compute shaders and features that need Forward+.
Browser build requirements:
• Target the latest Chrome, Edge and Firefox on desktop; Safari as best-effort. Mobile browsers are out of scope.
• Use a single-threaded web export by default so it works without special headers. Offer a threaded build behind Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy: require-corp headers, and pick the faster one after profiling.
• Enable WebAssembly SIMD in the export if your Godot version offers it.
• Compress textures with Basis Universal / ETC2+S3TC (VRAM-compressed) for web. Total first download under 150 MB, with maps streamed as separate .pck files after the main menu loads.
• Show a branded loading screen with a real progress bar while the .wasm and .pck files download.
• Pointer Lock API for mouse look, with raw (unaccelerated) input where the browser supports it. Handle the Escape key releasing the lock gracefully.
• Watch the community WebGPU backend for Godot. Do not depend on it, but keep shaders portable so the game can switch if it becomes official.
4. Art direction bible (priority one)
The look is stylized, hand-crafted realism: real-world materials and proportions, simplified into clean shapes and painted surfaces with controlled detail. Think of a high-end illustration that came to life, with comic-book clarity but solid, believable materials. Every asset should hold up in a close-up screenshot and still read clearly at 50 metres.
4.1 Shape language
• Chunky, confident forms. Large primary shapes, medium secondary shapes, minimal tertiary noise. Ratio guide: 60% large, 30% medium, 10% small detail.
• Bevelled everything. No razor-sharp 90° edges on anything the player looks at. Use chamfers (2–6 cm on props, 1–3 mm on weapons) with weighted normals so edges catch light and read as premium.
• Readable silhouettes. Each agent must be recognisable from silhouette alone at 30 m. Each weapon must be recognisable from its first-person silhouette.
• Architecture uses clean planar walls, strong horizontal trims, slightly exaggerated proportions (thicker frames, bigger cornices) and clear cover shapes. Cover is always a visibly solid object: crates, low walls, pillars, vehicles.
4.2 Colour and value
• Environments are mid-value and moderately saturated. No pure black, no pure white. Albedo range sRGB 40–220, with most surfaces between 70 and 190.
• Characters own the saturated accents. Environment saturation stays lower than agents'. Never paint large map surfaces in team colours.
• Each map has a 3-colour palette: one dominant base (around 60%), one secondary (30%) and one accent (10%), plus warm key light and cool fill. Write each map's palette as hex values in docs/art/maps/<map>.md before modelling.
• Team colours: allies cyan #3FE0D0, enemies red #FF4655-family. Make both configurable and add colour-blind presets (deuteranopia, protanopia, tritanopia) for enemy highlight, HUD and minimap.
• Light split: warm sunlight (about 5200 K, slightly golden) and cool sky shadows (blue-violet tint). Shadows are never grey-black; they are tinted and lifted.
4.3 Surface treatment
• PBR (metallic/roughness) but art-directed: albedo is hand-painted over a photo base, with baked soft gradients (darker at the bottom of walls, lighter at the top), gentle hue variation and painted edge wear.
• Detail comes from shape and normal map, not from high-frequency albedo noise. If a texture reads as noisy at 10 m, it is wrong.
• Edge highlights: worn, lighter edges on painted metal and stone (curvature-driven in Substance/Material Maker or via a curvature mask in-shader).
• Roughness has broad, readable variation: polished floors, matte plaster, satin metal. Avoid uniform mid-grey roughness.
4.4 Characters versus environment (the readability contract)
• Characters use a custom toon-PBR shader with a soft rim light (fresnel) and slightly higher saturation and contrast than the environment.
• Characters never use the same dominant hue as the map behind them in common sightlines. Test with the readability capture tool (section 9.5).
• Enemy outline: a subtle red fresnel/outline appears only when an enemy is spotted or revealed, never as a permanent wallhack.
4.5 What "done" looks like
An asset is art-complete only when:
• It has final mesh, LODs, collision and correct pivot and scale (1 unit = 1 m).
• It has full texture set (albedo, normal, ORM) at the texel density in section 5.
• It is lit by a baked lightmap with no visible seams, leaks or splotches.
• It reads correctly in a greyscale screenshot (value check) and at 50 m (silhouette check).
• It looks good in both the Forward+ and Compatibility renderers.
5. Textures, materials and shader pipeline
Every surface uses a consistent texel density, a packed three-texture set and a small library of master shaders, so the whole game looks like one art team made it.
5.1 Texel density and resolution
Asset class
Texel density
Max texture size (desktop / web)
First-person weapon
2048 px per 0.5 m (very high)
2048 / 2048
First-person arms and gloves
2048 per agent
2048 / 1024
Agent body (third person)
1024 px/m
2048 / 1024
Hero props near sightlines
512 px/m
2048 / 1024
Architecture (tiling + trims)
512 px/m
2048 / 1024
Background and skybox props
128–256 px/m
1024 / 512
The web build uses the same source files, imported at half resolution through import presets, never separate hand-made assets.
5.2 Texture set convention
• T_<Asset>_A — albedo (sRGB), with alpha only when needed.
• T_<Asset>_N — normal map, OpenGL (+Y) convention, as Godot expects.
• T_<Asset>_ORM — packed linear: R = ambient occlusion, G = roughness, B = metallic.
• T_<Asset>_E — emissive, only when the asset glows.
• Optional T_<Asset>_M — mask texture for tint zones, wear or Rift glow (RGBA channels documented per asset).
5.3 Environment texturing method
1.  Trim sheets for architecture: one 2048×2048 trim sheet per material family per map (stone trims, metal trims, wood trims, signage). Model walls and edges to map onto trim strips.
2.  Tiling materials (8–12 per map): plaster, stone tiles, concrete, painted metal, wood, sand, roof tiles. Each tileable at 2–4 m with no obvious repetition.
3.  Vertex-colour blending in a master terrain/wall shader to paint dirt, moss, sand drifts and wear across tiling materials, with a height-based blend so transitions look natural.
4.  Decals (Godot Decal nodes on desktop; mesh decals with alpha on web) for graffiti, posters, cracks, puddles, stains and the site letters A/B/C.
5.  Unique hero assets (statues, vehicles, Rift machinery) get their own texture set.
5.4 Tools for creating textures
Create textures procedurally and by hand, then paint over:
• Material Maker (open source) or Substance 3D Designer/Painter if available for tileables, trims and smart-material wear.
• Blender for modelling, UVs, baking (high-to-low normals, AO, curvature) and vertex paint.
• Krita for hand-painted overlays on albedo: gradients, colour variation, painted edge highlights.
• CC0 scans from ambientCG and Poly Haven are allowed as a base layer only, and must then be stylized: reduce high-frequency detail, push hue shifts, paint gradients and repaint edges.
5.5 Master shaders (write these as .gdshader files)
• M_Env_Standard — PBR with ORM, a detail normal at close range, a triplanar option for rocks, vertex-colour tint and wear, and a top-down "dust" layer driven by world normal.
• M_Env_Blend — up to 3 layered tiling materials blended by vertex colour plus height map.
• M_Character — toon-PBR: wrap lighting (softened half-Lambert), a 2-step soft-shaded ramp that is mixed 30–40% with PBR, fresnel rim light with a team-tinted option, and a mask-driven emissive for Rift tech.
• M_Weapon — high-quality PBR for first person: clear-coat look on painted parts, anisotropic hint on brushed metal (desktop), and skin-ready mask channels (base, accent, emissive) so weapon skins are just new masks and colours.
• M_Glass, M_Water, M_Foliage (with wind sway), M_Hologram, M_RiftEnergy (scrolling noise, fresnel and distortion), M_AbilityWall (for smokes and walls, see section 9).
• All shaders expose quality branches through a global uniform quality_tier so the browser tier skips expensive paths.
5.6 Import settings
• Albedo/emissive: VRAM compressed, sRGB, mipmaps on, anisotropic filtering x8 on desktop.
• Normal maps: VRAM compressed with "Normal Map" mode (RGTC/BC5 on desktop).
• ORM/masks: VRAM compressed, linear.
• UI: lossless, no mipmaps, filter linear.
• Make reusable import presets named Albedo, Normal, ORM, UI and apply them with a script so nothing is imported by hand.
6. Agent models, first-person arms and animation
Agents are the face of the game: each must look like a character from a premium hero shooter, with a distinct silhouette, a personality you can read from the outfit, and production-quality topology, textures and animation.
6.1 Proportions and style
• Heroic but grounded: about 7.5 heads tall, slightly enlarged hands and feet, clear shoulders, gear that tells you their role at a glance.
• Faces are stylized-realistic: simplified planes, clean painted skin with soft subsurface tint (warm ears, nose and cheeks), large readable eyes and clear brows. No uncanny photoreal skin.
• Hair is modelled as chunky stylized clumps (cards only for fine ends), with painted highlight bands.
• Each agent has one signature colour and one signature shape (a long coat, a big hood, a shoulder rig, a visor) that sets their silhouette apart from every other agent.
• Clothing materials read clearly: leather, nylon webbing, knit, armour plate, Rift crystal. Use the M_Character shader with material-ID masks.
6.2 Technical specs per agent
Item
Desktop
Web
Third-person body LOD0
35–50k triangles
20–25k (LOD1 used as LOD0)
LOD1 / LOD2 / LOD3
50% / 25% / 8%
same ratios from web LOD0
Texture sets
Body, Head, Gear: 2048 each
1024 each
Skeleton
Shared humanoid rig, about 70 bones + face bones
same rig, fewer face bones
First-person arms
15–20k triangles, 2048 textures
10k, 1024 textures
• One shared humanoid skeleton for all agents (retargetable in Godot via SkeletonProfileHumanoid), so locomotion animations are shared and only signature abilities need unique animations.
• Separate first-person arms mesh per agent with its own gloves, sleeves and wrist gear. The camera never shows the third-person body in first person.
• Hitboxes are separate simple shapes (capsules/boxes) on bones: head, upper torso, lower torso, arms, legs. They must be identical for every agent so no agent has a size advantage. Visual mesh may differ; hitbox may not.
6.3 Animation set
Third person (seen by others): idle, walk (8-way), run (8-way), crouch idle and crouch walk (8-way), jump start/loop/land, ladder climb, plant and defuse loops, death variations (3+), ability casts per agent, weapon holds per weapon class (sidearm, SMG, rifle, sniper, shotgun, heavy, melee), with upper-body aim offsets (yaw ±90°, pitch ±80°) layered by AnimationTree blend spaces.
First person (viewmodel): per weapon draw, idle (subtle breathing), walk and run bob, fire (per weapon, with recoil kick), ADS in and out, reload (tactical and empty), inspect (an elaborate showcase animation), equip ability, cast ability, melee swing (2 variations), spike plant and defuse.
Animation quality rules:
• Snappy, with strong anticipation and follow-through. Weapon draws feel weighty but take under 0.75 s.
• Inspect animations must be showpieces: the camera should love the weapon.
• Procedural layers on top of animation clips: weapon sway from mouse movement, inertia lag, landing dip, strafe tilt (2–3°), all tunable and disableable in settings.
• Death: a short animated reaction blending into ragdoll (Godot PhysicalBoneSimulator3D) on desktop; animation-only on web.
6.4 Pipeline
1.  Concept sheet per agent (front, side and back silhouette + colour callouts) saved in docs/art/agents/.
2.  Blockout in Blender, check silhouette in-game against both maps.
3.  High-poly sculpt (clothing folds, armour details) and retopology to the budgets above.
4.  UVs, bake normals/AO/curvature, texture with smart materials plus hand-painting.
5.  Rig on the shared skeleton, skin, test deformation in extreme poses.
6.  Export as .glb with materials replaced by M_Character instances in Godot.
7. Weapon models, viewmodels and weapon feel
Weapons fill a third of the screen for the whole match, so they get the highest detail in the game: hero-quality models, crisp textures, and animation and effects that make every shot feel powerful.
7.1 Design language
• Near-future, grounded firearms: recognisable as real weapon classes, with original designs. Never copy a real-world gun or another game's weapon one-to-one.
• Clean manufactured shapes: machined aluminium receivers, polymer furniture, painted steel, exposed screws and rails, small Rift-tech emissive accents on some models.
• Each weapon has a clear, unique first-person silhouette and colour block so players can identify it from a killfeed icon, from first person and when held by an enemy.
• The default skin is the "PRISM Standard" finish: matte graphite polymer, satin dark metal, and one muted accent colour per weapon class.
7.2 Technical specs
Item
Desktop
Web
First-person LOD0
15–25k triangles (sniper/heavy up to 30k)
10–15k
Third-person / world LOD
3–5k triangles
same
Textures
2048 set (A, N, ORM, E, M)
2048 albedo/normal, 1024 others
Moving parts
Separate nodes: magazine, bolt/charging handle, trigger, slide, ejection port cover
same
• Model at real scale, pivot at the grip, consistent socket names (muzzle, eject, mag, sight_aim, left_hand_ik).
• Rendered in first person with a separate camera FOV for the viewmodel (fixed around 68°, independent of the world FOV setting) so weapons never look stretched, and drawn so they never clip into walls.
• Magazine and casings are real meshes; shell casings eject with a pooled physics-lite effect.
7.3 Weapon feel checklist
Every weapon must have all of these before it counts as done:
1.  Visual recoil: viewmodel kick back + up with a spring return, a small camera punch, and a camera shake proportional to calibre.
2.  Muzzle flash: a 3-frame stylized flipbook flash plus a short point light (desktop) and a smoke puff.
3.  Tracer: a thin bright tracer for every bullet, visible to all players, team-tinted for the shooter's team on spectate.
4.  Impact effects per surface: concrete, metal, wood, glass, sand, water, flesh. Each gets a decal, sparks/dust particles and its own sound.
5.  Shell ejection with sound when casings land.
6.  Sound layers: mechanical close, body, tail (indoor/outdoor reverb), and a distant variant (section 16).
7.  Hit feedback: hitmarker, headshot sound and a distinct crit flash; kill confirmation icon and sound.
8.  Reload and equip timing that matches the animation frame-perfectly, with a cancel window.
7.4 Skins system (built in from day one)
• Weapon materials read colour and pattern from mask channels, so a skin is a small data resource: colours, a pattern texture, emissive colour, optional custom mesh parts and a custom kill/inspect VFX.
• Ship with 2 example skin lines per weapon class to prove the system: "Lumen" (white ceramic with gold trims and a soft glow) and "Hazard" (yellow-black industrial with stencil decals).
• Skins are cosmetic only and must never change silhouette enough to confuse identification.
8. Maps and environment art
Launch with two fully art-complete maps and one training range. Each map is a real-world-inspired place with a single Rift twist, a 3-lane layout and strict competitive metrics. A map is not done until it is beautiful from every playable position.
8.1 Layout rules (all maps)
• Three lanes (left, mid, right) with two bomb sites (A and B). One map may have a third site C later.
• Attacker spawn to site: 18–22 s running. Defender spawn to site: 8–12 s. Defender rotate between sites: 15–20 s.
• Every site has 2–3 entrances, at least 4 standard plant spots, solid hard cover, and post-plant positions for both teams.
• Grid scale: 1 unit = 1 m. Player capsule 0.6 m wide, 1.8 m tall (1.2 m crouched). Standard doors 2 m wide; chokes 3–4 m; main lanes 6–10 m.
• No pixel-angles, no random clutter that blocks bullets unpredictably. Every piece of cover is either fully bullet-blocking or clearly penetrable (wood, thin metal) and coded as such with a material tag.
• One-way surfaces are forbidden. Collision is hand-authored simple geometry, not the render mesh.
• Clear landmarks so callouts are natural: every area gets a name painted or signed in the world ("A Main", "Heaven", "Garage", "Market").
8.2 Map 1: SOLSTICE (Mediterranean coastal town)
• Place: a sun-bleached cliffside town above a turquoise bay. Lime-washed walls, terracotta roofs, blue shutters, a harbour, a small cathedral plaza.
• Rift twist: a frozen wave of Rift crystal hangs over the bay, casting faint violet caustics on the cliffs.
• Palette: warm cream #EFE3C8 (base), terracotta #C8643B (secondary), sea teal #2BA6A4 (accent). Golden late-morning sun, cool turquoise bounce light.
• Sites: A = harbour warehouse with stacked cargo, cranes and a boathouse. B = cathedral plaza with a fountain, market stalls and an upper balcony.
• Mid: a stepped alley with an arched bridge, laundry lines and potted plants.
8.3 Map 2: NEON DISTRICT (rainy East Asian city night)
• Place: a dense night-time city block after rain: wet asphalt, signage, shopfronts, a metro station and a rooftop garden.
• Rift twist: a slow-turning Rift monolith above the block, projecting hologram ads that glitch.
• Palette: deep indigo #1E2240 (base), warm sodium amber #F2A33A (secondary), magenta/cyan neon accents used sparingly. Readability rule: lit so characters are always brighter than the backdrop; neon stays in the background and above head height.
• Sites: A = metro concourse with turnstiles, tiled pillars and a stationary train. B = market street with food stalls, scooters and a parking structure.
• Mid: a covered arcade with vending machines and a noodle bar.
• Wet-surface look: low roughness puddle masks with planar or screen-space reflections on desktop; baked reflection probes plus roughness tricks on web.
8.4 The Range (training map)
A clean PRISM facility with a shooting lane at 10/20/30/50 m, moving bots, a strafing bot track, a plant/defuse practice site and an ability sandbox. It is the showroom for weapons and agents, so it must look as polished as the competitive maps.
8.5 Environment production pipeline
1.  Paper layout: 2D top-down plan with lanes, timings and callouts in docs/maps/<map>.md.
2.  Blockout in Godot with CSG/simple meshes (BLOCKOUT_ prefix). Playtest with bots, measure timings and sightlines, iterate.
3.  Modular kit in Blender: wall segments on a 1 m / 0.5 m grid, door and window frames, stairs, trims, roofs, plus 40–80 props per map.
4.  Set dressing: layered storytelling detail — laundry, cables, signs, plants, debris — kept out of combat lines.
5.  Lighting bake (section 9). Fix every leak and seam.
6.  Polish pass: decals, vertex-paint grime, foliage wind, ambient life (birds, flags, steam, flickering signs, drifting dust particles), skybox and distant vista meshes.
7.  Optimization: occlusion culling (OccluderInstance3D), LODs, visibility ranges, merged static meshes, material count under 60 per map.
8.6 Skybox and vista
Each map gets a hand-made panoramic sky (HDR for desktop, LDR for web) and a distant 3D vista ring (cliffs, skyline) with simple unlit or lightly lit materials, so the horizon is never empty.
9. Lighting, post-processing and VFX
Lighting is what makes stylized art look expensive. Bake rich global illumination, add a small number of real-time lights, grade the image carefully and keep effects bold but readable.
9.1 Lighting setup per map
• One DirectionalLight3D sun with real-time shadows for dynamic objects (players, dropped weapons) and baked contribution for static geometry.
• LightmapGI bake for all static geometry: high quality, with bounces 3+, denoiser on, and texel scale tuned so walls show soft bounce colour (terracotta bouncing warm light in SOLSTICE, neon spilling onto wet ground in NEON DISTRICT).
• Lightmap UVs on UV2 for every static mesh, with padding and no overlaps. Fix seams by hand.
• Light probes from LightmapGI light dynamic objects so characters sit naturally in the scene.
• ReflectionProbe per major area (interior/exterior split), box-projected indoors.
• Characters receive an extra subtle rim from the M_Character shader so they never sink into shadow.
9.2 WorldEnvironment and post-processing
• Tonemapper: ACES or AgX (choose by comparing against references), exposure fixed per map (no auto-exposure in competitive play).
• Colour grading: a 3D LUT per map, authored to match the palette in section 4.2. Gentle contrast S-curve, warm highlights, cool lifted shadows.
• Glow/bloom: subtle, threshold high, only emissives and muzzle flashes bloom.
• SSAO and SSIL (desktop only), low intensity, to ground props and characters.
• Fog: light depth fog for atmosphere; volumetric fog only in desktop high and ultra tiers, never thick enough to hide players.
• Anti-aliasing: TAA or FSR2 on desktop high; MSAA 2x + FXAA on web; sharpen pass after TAA to keep the image crisp.
• No chromatic aberration, no film grain, no motion blur, no depth of field in gameplay. They hurt readability. Allow them only in menus and kill cams.
9.3 Fidelity tiers
Setting
Web
Desktop Low
Desktop Medium
Desktop High/Ultra
Renderer
Compatibility
Forward+
Forward+
Forward+
Texture size
half
half
full
full
Shadows
1 cascade, 2048
2 cascades, 2048
3 cascades, 4096
4 cascades, 4096 + soft
SSAO / SSIL / SSR
off
off
SSAO
all on
Volumetric fog
off
off
off
on (light)
Anti-aliasing
MSAA 2x + FXAA
FXAA
TAA + sharpen
TAA/FSR2 + sharpen
Particles
50%
50%
100%
100% + extra debris
Target fps
60
144
144
144+
The web tier must still look like the same game in a screenshot: same baked lighting, same LUT, same textures at half size.
9.4 VFX language
• Stylized, hand-designed effects: flipbook textures and mesh-based effects with crisp shapes, stepped alpha and bright cores. No generic soft-particle mush.
• Every ability has its own colour identity tied to its agent, but team readability always wins: the edge or rim of hostile ability effects glows enemy red, friendly ones team cyan.
• Smokes are opaque, volumetric-looking spheres (layered meshes with a noise shader), never transparent enough to see through, identical to both teams and on both renderers.
• Walls and barriers use M_AbilityWall: a scrolling pattern, fresnel edges and a visible thickness.
• Ultimate effects get a cinematic flourish (screen-edge tint, a unique sound sting) but last under 1 s of screen obstruction.
• Use GPUParticles3D on desktop and CPUParticles3D on web (auto-converted by the QualityManager).
9.5 Visual QA tools you must build
• Screenshot bookmarks: 20+ fixed camera positions per map; a command captures all of them on every renderer and tier into qa/screens/<date>/.
• Readability capture: spawns a default-skinned dummy of each agent at common angles and outputs the contrast ratio between character and background. Flag anything under 3:1.
• Greyscale and silhouette view modes toggled by a debug key.
• Texel density checker overlay and lightmap UV / overdraw views.
10. Core gameplay
The core is a precision shooter: movement that punishes running-and-gunning, first-shot accuracy that rewards discipline, and a round economy that makes every buy a decision. All numbers below are starting values in /shared/config/*.json, tuned through playtests.
10.1 Movement
Parameter
Value
Run speed (knife/sidearm)
6.75 m/s; heavier weapons scale to 5.4–6.5 m/s
Walk speed (hold Shift)
3.0 m/s, silent footsteps
Crouch speed
2.4 m/s; crouch transition 0.12 s
Acceleration / deceleration
Reach full speed in ~0.15 s; stop in ~0.1 s (counter-strafe)
Jump
1.0 m high; landing slows to 50% for 0.25 s
Air control
Low; no bunny-hop speed gain
Step height / max slope
0.4 m / 45°
• Movement accuracy: weapon inaccuracy scales with horizontal speed. Under ~20% of max speed counts as standing. Counter-strafing must feel crisp.
• Footsteps are audible to enemies within 40 m while running, with surface-specific sounds. Walking and crouching are silent.
• Ladders, rope ascenders and one-way drop-downs are allowed; no wall-running or sliding.
10.2 Gunplay
• Hitscan bullets for all guns (server-validated with lag compensation, section 13). Wall penetration by material tag: light/medium/heavy weapons lose a set share of damage per centimetre of material.
• First-shot accuracy: rifles and sidearms are pinpoint on the first shot while standing still.
• Recoil: deterministic spray pattern per weapon (learnable) + small random spread that grows with sustained fire. Recoil recovery after ~0.35 s of not firing. The pattern data is shared by client and server.
• Damage multipliers: head ×4 (rifles one-tap at any range), body ×1, legs ×0.85. Damage falloff ranges per weapon.
• Health: 100 HP; light shield 25 (400 credits), heavy shield 50 (1000 credits). Shields absorb 66% of damage until depleted.
• Tagging: taking damage slows movement by 70% for 0.2 s (tunable per weapon).
• Aim down sights: zoom 1.15–1.25× on rifles/SMGs with a small accuracy bonus and fire-rate penalty; scopes on snipers with 2–5× zoom.
10.3 Match structure (Breach Charge mode)
• 5v5. First to 13 rounds. Halftime swap after round 12. At 12–12, overtime: win by 2, swapping sides each round, with a team vote to accept a draw after 2 overtime pairs.
• Round phases: Buy phase 30 s (barriers block spawn) → Combat 100 s → if planted, Breach Charge detonates after 45 s → round end 7 s.
• Breach Charge: one attacker carries it. Plant takes 4 s inside a marked site. Defuse takes 7 s, with a checkpoint at 3.5 s. Planting and defusing make loud sounds and visible beams. The carrier is shown to teammates on the minimap; a dropped charge is visible to attackers only.
• Win conditions: attackers win by eliminating all defenders or detonating the charge. Defenders win by eliminating all attackers before a plant, defusing, or running out the clock before a plant.
• Spectating: dead players spectate teammates. Death recap shows who dealt how much damage with what.
10.4 Economy
Event
Credits
Start of each half
800
Kill
+200
Round win
+3000
Round loss
+1900, +2400, +2900 for 1, 2, 3+ consecutive losses
Planting the charge (whole attacking team)
+300
Max credits
9000
• Buy menu opens during buy phase in the spawn zone, with team-request buttons ("request a rifle") and the ability to buy a weapon for a teammate by dropping it.
• Weapons and shields carry over between rounds if the player survives; abilities persist as charges.
• Show predicted next-round credits in the buy menu.
10.5 Abilities and ultimates (system rules)
• Each agent has four slots: C and Q (bought with credits, 1–2 charges), E (signature: one free charge each round, some recharge on a timer) and X (ultimate: costs 6–8 ultimate points).
• Ultimate points: +1 per kill, +1 per death, +1 per plant or defuse, +1 for picking up a Rift Orb (two orbs spawn on each map).
• Abilities are data-driven Resources: cast type (instant, throwable, placeable, aimed), cast time, cooldown, charges, cost, effect scripts and VFX/SFX references. The server validates every cast.
11. Agent roster (launch: 8 agents)
Launch with eight original agents across four roles, two per role. Each needs a concept sheet, full model, first-person arms, all four abilities with VFX and SFX, voice-line placeholders and a select-screen pose.
Roles: Vanguard (entry fraggers), Shroud (vision control: smokes, walls), Seeker (information: scans, flashes, reveals), Warden (site anchors: traps, slows, healing).
Vanguards
KESTREL — Norwegian ex-rescue pilot. Signature colour: signal orange. Silhouette: cropped flight jacket, tall collar, shoulder-mounted thruster pack.
• C — Updraft: short vertical boost (3 m).
• Q — Flare Round: bouncing flash that pops 0.6 s after leaving the hand.
• E — Slipstream: 5 m directional dash; recharges after 2 kills.
• X — Talon Barrage: 5 throwing blades; one-shot to body at under 15 m; refunds on kill.
MAMBA — Kenyan street racer turned Rift runner. Signature colour: acid green. Silhouette: hooded racing suit, glowing visor, sleek knee guards.
• C — Burnout: trail of fire on the ground (damage over time, area denial for 4 s).
• Q — Afterimage: sends a decoy running forward that flashes enemies who look at it.
• E — Gearshift: 2 s sprint boost with silent footsteps.
• X — Redline: 10 s of faster reload, faster equip and health regeneration on kill.
Shrouds
VESPER — French astronomer. Signature colour: deep violet. Silhouette: long tailored coat, star-chart cape, floating orrery.
• C — Eclipse Veil: curved vision-blocking wall up to 18 m long, placed from a top-down map view, lasting 12 s.
• Q — Nebula Mine: a trap that slows anyone who walks through.
• E — Starfall: 3 smoke domes placed from a map view (lasting 15 s each, recharge 40 s per charge).
• X — Gravity Well: a large zone that pulls enemies to its centre and slows them for 4 s.
HALDOR — Icelandic geothermal engineer. Signature colour: steam white and basalt black. Silhouette: bulky heat-suit, exhaust stacks on his back, gauntlet nozzle.
• C — Vent: deploys a steam column that blocks vision and muffles sound inside.
• Q — Basalt Pillar: raises a 2 m pillar of rock as cover (destructible, 800 HP).
• E — Geyser Smoke: 2 thrown smokes that inflate on landing (lasting 14 s).
• X — Eruption: 3 delayed blasts on a line, dealing heavy damage and leaving smoke.
Seekers
ORIN — Australian outback tracker. Signature colour: dusty ochre. Silhouette: wide-brim hat, poncho, a mechanical hawk drone.
• C — Hawk: pilotable drone that tags one enemy with a reveal dart.
• Q — Dust Burst: thrown flashbang that bursts in a cone.
• E — Echo Arrow: a bouncing scan arrow that reveals enemies in line of sight of its landing point, twice.
• X — Apex Hunt: reveals all enemies on the map 3 times over 6 s.
SABLE — Korean signal hacker. Signature colour: electric cyan-blue (distinct from ally cyan by a white trim). Silhouette: oversized jacket, cables, holographic tablet.
• C — Tripwire Trace: an invisible laser across a doorway that reveals and slows on contact.
• Q — Static: a blinding hologram glitch through walls (near-sighting effect).
• E — Ping: a placeable sensor that scans a 10 m radius every 3 s.
• X — Blackout: disables enemy minimap and ability HUD for 8 s.
Wardens
IMANI — Nigerian combat medic. Signature colour: warm gold. Silhouette: field medic armour, glowing medkit backpack, braided hair with beads.
• C — Barricade: a slowly deploying bullet-blocking wall (destructible, 1000 HP).
• Q — Mend: heals an ally 60 HP over 3 s, or herself at half the rate.
• E — Lattice: a slowing net thrown at the ground.
• X — Second Wind: revives a fallen ally with full health.
TOMAS — Chilean mining engineer. Signature colour: copper. Silhouette: hard hat with goggles, tool belt, mechanical arm.
• C — Proximity Charge: a hidden trap that tethers and slows an enemy, then explodes after 1.5 s.
• Q — Sentry Drill: a turret that fires at visible enemies (low damage, slowing).
• E — Alarm Spike: a hidden sensor that reveals and makes enemies vulnerable for 4 s.
• X — Lockdown: a large zone that detains (disarms and slows) everyone inside after a 13 s warm-up.
Balance rules for every ability: no ability one-shots through cover; every flash is avoidable by turning away; every trap is visible to an alert player at close range; every effect has a clear sound cue for both teams.
12. Weapon roster (launch: 15 weapons + knife)
All names are original. Damage is per bullet at close range (head ×4 for rifles and sidearms, ×3 for SMGs and heavies, legs ×0.85). Every value lives in /shared/config/weapons.json.
Name
Class
Cost (credits)
Fire rate (shots/s)
Mag
Body dmg
Run speed (m/s)
Identity
Wasp
Sidearm (default)
0
6.75
12
26
6.75
Free starter pistol; alt-fire 3-round burst
Pike
Sidearm
300
4
6
50
6.75
Heavy revolver-style pistol; rewards headshots
Hornet
Sidearm
200
10 (auto)
13
24
6.75
Silenced machine pistol
Grifter
Sidearm
200
2.2
4
4×20 pellets
6.75
Pocket shotgun
Jolt
SMG
900
16
25
27
6.75
Fast, cheap, accurate while moving
Halcyon
SMG
1600
13.3
30
26
6.5
Accurate SMG with a 1.25× zoom
Breaker
Shotgun
1850
3.3 (auto)
7
8×11 pellets
6.5
Close-range pump shotgun
Mauler
Shotgun
2100
4 (auto)
8
9×10 pellets
6.5
Fully-automatic drum shotgun
Lancer
Rifle
950
4 (burst)
24
30
6.5
Cheap 3-round burst rifle
Kite
Rifle
2050
6 (semi)
12
75
6.5
Marksman rifle; 2× scope
Saber
Rifle
2900
9.75
25
40
6.0
Hard-hitting rifle; one-tap head at all ranges
Specter
Rifle
2900
11
30
39
6.0
Silenced, no tracer from distance; falloff after 15 m
Shrike
Sniper
1100
1.35
5
75
6.5
Light bolt sniper; one-tap head, quick scope
Longbow
Sniper
4700
0.75
5
150
5.4
Heavy sniper; one-shot body kill; 2.5×/5× zoom
Bulwark
Heavy
3200
10 → 13 (spin-up)
100
34
5.4
Light machine gun; best wall penetration
Tactical knife
Melee
0
—
—
50 / 75 heavy
6.75
Always equipped; fastest movement
Rules shared by every weapon:
• Each has a data-defined recoil pattern (array of (x, y) offsets per shot), spread curve, falloff ranges, wall-penetration tier (low/medium/high), reload time, equip time and movement-spread multiplier.
• Rifles (Saber, Specter) and the two snipers are the core. Spend extra art and animation time on them.
• Every weapon has a world model, a killfeed icon and a buy-menu icon, rendered from the actual model with a consistent studio lighting rig so icons match.
13. Multiplayer architecture (authoritative Node.js server)
The Node.js server is the single source of truth: it simulates movement, shots, abilities, the economy and the round state at a fixed 64 Hz tick. Clients only send inputs and render predicted and interpolated results. Never trust anything else the client says.
13.1 Server process layout
• Gateway (Node + uWebSockets.js or ws): terminates WebSocket connections (TLS), authenticates the session token and routes players to a match.
• Match workers: each match runs in its own worker_threads worker with a fixed-timestep loop (tick = 1/64 s, using a drift-corrected high-resolution timer, not setInterval). One process hosts many matches; scale horizontally across machines.
• Shared simulation package /server/sim in TypeScript: movement, collision, hitscan, abilities, economy, round state machine. Pure, deterministic functions with no I/O, so they can be unit-tested and replayed.
13.2 Map collision on the server
• A Godot editor tool exports each map's collision geometry (the hand-authored simple collision shapes, not render meshes) plus material tags (for wall penetration), site volumes, spawn zones, plant zones, ladders and Rift Orb positions to /shared/maps/<map>.collision.bin and <map>.meta.json.
• The server builds a BVH over those triangles and boxes for raycasts and capsule sweeps (use a proven library such as three-mesh-bvh running headless, or write a focused BVH).
• Add a CI check: the exported collision must match the Godot scene, or the build fails.
13.3 Movement: prediction and reconciliation
• Clients send input commands every tick: sequence number, tick, buttons bitmask, view yaw/pitch (quantized), weapon slot. Inputs are sent redundantly (last 3) to survive packet loss.
• The client runs the same movement code locally (GDScript port of /server/sim/movement.ts) for instant response.
• The server returns the authoritative state with the last processed input sequence. The client rewinds to it and replays pending inputs. Corrections under 2 cm are smoothed over 100 ms; larger ones snap.
• Parity guarantee: keep a set of golden test vectors (input sequences and expected positions) in /shared/tests/movement/*.json. Both the TypeScript and GDScript implementations must pass them in CI, with a tolerance of 1 mm.
13.4 Shooting and lag compensation
• Remote players are rendered with entity interpolation about 2 ticks (~31 ms) plus a jitter buffer behind the newest snapshot.
• On fire, the client sends the shot with its input tick and interpolation time. The server rewinds every hitbox to where that client saw them (history buffer of 250 ms max), performs the raycast against hitboxes and map geometry, then applies damage at the present tick.
• Hard cap on rewind (250 ms): players on very high ping must lead targets rather than get unfair hits.
• The client plays local effects (muzzle flash, tracer, impact decal) immediately, but hitmarkers and damage numbers only appear after server confirmation to avoid false hits.
• Spray patterns, spread and random seeds are server-side; the client predicts using the same seed sent at round start.
13.5 Anti-wallhack visibility culling (fog of war)
The server never sends an enemy's position to a client that cannot plausibly see or hear them:
• Precompute a potentially visible set (PVS) between map cells offline.
• Each tick, for enemies in the PVS, do a few raycasts from the viewer's eye (with a lead margin for latency) to the enemy's bounding points.
• Enemies that fail are not sent. Enemies that become visible are sent slightly early (by about 1 tick of movement + ping) to avoid pop-in.
• Audible events (footsteps, gunshots, abilities) are sent as sound events with position, only within hearing range.
13.6 Network protocol
• Binary WebSocket frames. Define every message in a schema file in /shared/protocol/ and generate the TypeScript and GDScript encoders/decoders from it, so the two never drift.
• Quantize: positions to 1 mm in 32-bit ints, angles to 16 bits, velocities to 16 bits.
• Snapshots at 64 Hz (adjustable to 32 Hz for weak connections), delta-compressed against the last acknowledged snapshot.
• Reliable events (kills, round state, purchases, chat) go in a reliable channel with sequence/ack inside the same socket.
• Target bandwidth: under 25 KB/s down and under 6 KB/s up per player in a full 10-player fight.
• Message types to start with: Hello, AuthOk, JoinMatch, MatchState, Input, Snapshot, Fire, HitConfirm, Damage, Kill, AbilityCast, AbilityEvent, BuyRequest, BuyResult, PlantStart, DefuseStart, RoundPhase, Chat, Ping/Pong, Disconnect.
13.7 Latency handling and quality of service
• Ping, packet loss and jitter shown in a net graph (toggle in settings).
• Region-based servers; matchmaking prefers players under 60 ms to the chosen region.
• Reconnect: a dropped player can rejoin the same match within the round, with state restored.
• Optional phase 2: WebRTC unreliable data channels (server side via node-datachannel, client via Godot's WebRTC API) for inputs and snapshots, keeping WebSocket for reliable traffic. Only do this if measurements show WebSocket head-of-line blocking hurts gameplay.
14. Backend services, anti-cheat and deployment
Around the match servers, build a small, solid backend: accounts, parties, matchmaking, match history and a deployment setup one person can run.
14.1 Services (Node.js + TypeScript, all in the monorepo)
• Auth service: email + password (argon2id hashing) and OAuth (Google, Discord). Issues short-lived JWT access tokens and rotating refresh tokens. Guest accounts for quick play in the browser.
• Profile service: player name + tag (Name#1234), level, owned skins, loadout, settings sync, match history.
• Party service: invite friends, party up to 5, party chat, ready check.
• Matchmaking: queues for Unrated, Competitive (ranked), a quick 7-round mode called Rapid Breach (later), and Custom games. Glicko-2 rating with hidden MMR + visible rank tiers with original names and icons (Shard, Prism, Lumen, Nova, Zenith, Apex). Match by MMR, region ping and party size, widening the search over time.
• Match allocator: picks a match worker with capacity in the right region, sends it the roster and map, hands players a one-time join ticket.
• Agent select service: 80 s lock-in phase with hover, lock, and duplicate prevention per team.
• Stats service: writes match results, per-round events (kills, damage, economy) to PostgreSQL for match history and post-game scoreboards.
14.2 Data stores
• PostgreSQL for durable data (accounts, profiles, matches, ratings, inventory). Use migrations (for example node-pg-migrate or Prisma).
• Redis for sessions, queues, party state and pub/sub between services.
14.3 Anti-cheat (server-side first)
• Authoritative simulation and fog-of-war culling (section 13.5) remove most wallhack and speedhack value.
• Validate every input: max turn rate per tick, fire-rate limits, ability cooldowns, buy-zone and buy-phase checks, position sanity.
• Statistical detection: flag accounts with inhuman reaction time, snap-to-head patterns or impossible accuracy over many rounds, for review.
• Rate-limit all endpoints, sign join tickets and never expose internal server addresses.
• The browser build cannot run kernel anti-cheat. Accept that and rely on server authority; keep ranked queues desktop-preferred if abuse appears.
• Report button in game, with replays stored for 14 days for review.
14.4 Replays
Record every match as the ordered stream of server inputs and snapshots (it is deterministic), compressed. Provide a replay viewer in the client with free camera, player POV and timeline scrubbing.
14.5 Deployment
• Docker images for each service and for match servers. docker-compose.yml for local development (all services + Postgres + Redis + a static web server for the browser build).
• Production: match servers on dedicated or bare-metal VMs per region (for low jitter), other services on a container platform. Use an orchestrator such as Agones-style allocation or a simple custom allocator to start.
• The web build (index.html, .wasm, .pck) is served from a CDN with long-cache hashed filenames, gzip/brotli, and the COOP/COEP headers if the threaded build is used.
• CI (GitHub Actions): lint, type-check, unit tests, movement parity tests, headless Godot export for desktop and web, Docker build. A failed parity test blocks merges.
• Observability: structured logs, Prometheus metrics (tick duration, players, bandwidth, packet loss) and Grafana dashboards. Alert if tick time exceeds 10 ms at the 99th percentile.
15. UI/UX, HUD and menus
The interface is clean, angular and confident: dark translucent panels, sharp cut corners, one accent colour, crisp condensed type and smooth, fast motion. Everything must be readable at 1080p on a laptop and scale correctly from 720p to 4K and ultrawide.
15.1 Visual style
• Base: near-black blue #0F1923 panels at 85% opacity, off-white text #ECE8E1, accent red #FF4655-family for primary actions, cyan for allies. Avoid copying any existing game's layout pixel-for-pixel; design your own grid.
• Type: Chakra Petch or Rajdhani for headings (uppercase, wide tracking), Inter for body and numbers.
• Motion: 150–250 ms ease-out transitions, subtle slide and fade, hover states with an accent bar. Every button has a click sound.
• Build UI in Godot Control scenes with a shared Theme resource; no hard-coded colours or fonts in scenes.
15.2 In-game HUD
• Bottom centre: health and shield numbers with bars; ability icons (C, Q, E, X) with charges, cooldown sweeps and ultimate point pips.
• Bottom right: weapon name, ammo in magazine / reserve, a small weapon icon.
• Top centre: round timer, score, team portraits with alive/dead state, ultimate readiness and equipped weapon icons for allies; Breach Charge timer after plant (as a pulsing icon, no exact number, so players rely on sound).
• Top left: minimap with rotation option, allies, spotted enemies (red, fading), ability areas, the Charge carrier.
• Top right: killfeed with weapon icons, headshot and wallbang markers.
• Crosshair editor: colour, outline, centre dot, inner and outer lines (length, thickness, offset, opacity), movement and firing error toggles, import/export codes.
• Damage indicators: directional arcs; a hit sound and hitmarker variant for headshots.
• Buy menu: a full-screen grid by weapon class, shields and abilities, with cost, team requests and the predicted next-round credits.
• Scoreboard (Tab): K/D/A, credits, ultimate points, ping.
15.3 Menus and flows
• Main menu: a 3D scene with the selected agent in a lit showroom, idle animation and subtle camera drift. Buttons: Play, Agents, Collection, Career, Settings.
• Play: mode select, party panel, queue timer with cancel.
• Agent select: full-screen agent portraits, ability previews with short looping videos (recorded in-engine), lock-in animation and sound.
• Loading screen: the map's key art, callouts, team rosters and tips.
• End of match: victory/defeat cinematic shot, MVP card, per-player stats and a timeline of rounds.
• Collection: weapon skins viewer with 3D rotation and inspect animation preview.
• Settings: video (all section 9 options + FOV 80–103), audio (master, SFX, voice, music), controls (rebinding, sensitivity, ADS sensitivity multiplier, raw input), crosshair, accessibility (colour-blind modes, subtitle size, reduced camera shake).
15.4 Communication
• Ping wheel ("Enemy here", "Need help", "Planting", "Rotate") with world markers and voice lines.
• Text chat (team and all), with mute and report.
• Voice chat: WebRTC peer audio inside the party/team via the server as signalling, with push-to-talk and per-player volume.
16. Audio
Sound is half of the information in a tactical shooter. Every footstep, reload and ability must be locatable by ear, and weapons must sound powerful and distinct.
• Spatial audio: Godot AudioStreamPlayer3D with HRTF-style panning where available, distance attenuation curves per sound category, and occlusion: sounds behind walls are low-pass filtered and slightly quieter (raycast from listener to source, 2–4 rays, updated at 15 Hz).
• Weapons: each has 3 layers (close mechanical, body, tail) and indoor/outdoor tail variants chosen by the area the shooter stands in, plus a distant variant beyond 30 m. Minimum 4 random variations per layer to avoid repetition.
• Footsteps: per surface (stone, metal, wood, sand, tile, water, carpet), at least 6 variations each; landing sounds after jumps.
• Abilities: unique cast, travel and impact sounds; enemy versions are slightly louder and more distinct than friendly ones.
• Breach Charge: a plant sound, a beeping that speeds up as detonation nears, a defuse sound with a half-way cue.
• Announcer and agent voice lines: round start, last player alive, charge planted, ability callouts ("Smoke going out"). Use placeholder text-to-speech until real voice acting; keep lines in data files.
• Music: an original main-menu theme, an agent-select loop, a short buy-phase sting and a match-win/loss cue. No music during combat.
• Mix: an AudioBus layout with Master, SFX, Weapons, Footsteps, Abilities, Voice, Music, UI; sidechain ducking of music under voice; a limiter on Master.
• Sources: create or commission original sounds; CC0 libraries (for example Freesound CC0 items or Sonniss GDC bundles, licence permitting) are allowed as raw material, layered and processed so they feel unique. Log every source in docs/CREDITS.md.
• Web build: audio starts only after the first user click (browser autoplay rules). Use OGG Vorbis for music and WAV/OGG for short SFX; preload weapon and footstep sounds before the match starts.
17. Project structure, code standards and performance budgets
Use one monorepo so client, server and shared data change together, with strict conventions and hard performance budgets checked in CI.
17.1 Repository layout
breachpoint/
  client/                 # Godot project
    addons/               # editor tools (collision exporter, QA capture)
    assets/
      agents/<name>/      # meshes, textures, materials, anims
      weapons/<name>/
      maps/<map>/         # kit, props, textures, lightmaps
      vfx/  sfx/  music/  ui/  fonts/
    scenes/               # main_menu, agent_select, match, range
    scripts/
      core/               # autoloads: Game, Net, QualityManager, Settings, Audio
      net/                # protocol (generated), prediction, interpolation
      sim/                # GDScript port of shared movement and weapon logic
      gameplay/  abilities/  ui/
    shaders/
  server/
    gateway/  match/  sim/  services/   # TypeScript
  shared/
    config/               # weapons.json, agents.json, economy.json
    protocol/             # message schema + code generator
    maps/                 # exported collision + meta
    tests/                # golden movement and weapon vectors
  docs/                   # DECISIONS, CREDITS, art bible notes, map docs
  qa/                     # screenshot captures, perf reports
  docker/  .github/workflows/
17.2 Code standards
• GDScript: static typing everywhere (var speed: float), class_name for reusable classes, signals for decoupling, no logic in _process that belongs in _physics_process. Treat warnings as errors.
• Gameplay runs in a fixed 64 Hz physics tick on the client too (physics_ticks_per_second = 64), with rendering interpolated between ticks for smoothness at any frame rate.
• TypeScript: strict: true, ESLint + Prettier, no any, Vitest for tests.
• Data-driven: no balance number may live in code. Validate all JSON against JSON Schemas at startup on both sides.
• Object pooling for bullets, decals, particles and sounds. No allocations in the hot loop.
• Naming: SM_ static mesh, SK_ skinned mesh, T_ texture, M_ shader, MI_ material instance, VFX_, SFX_, UI_.
17.3 Performance budgets
Budget
Desktop (GTX 1060 / RX 580 class, 1080p)
Web (integrated GPU laptop, Chrome, 1080p)
Frame rate
144 fps at Medium
60 fps stable
Frame time CPU / GPU
6.9 ms / 6.9 ms
16.6 ms / 16.6 ms
Draw calls in view
under 1,500
under 600
Triangles in view
under 3 M
under 1 M
Texture memory
under 2 GB
under 600 MB
Map load time
under 8 s from SSD
under 20 s on 50 Mbit/s first time; under 5 s cached
Server tick time (10 players)
under 2 ms average, 10 ms p99
—
• Build a perf capture scene that flies the camera along a fixed path on each map and writes average, 1% low and worst frame times to qa/perf/. Run it in CI on desktop headless export where possible, and manually in Chrome each milestone.
• Tools to hit the budgets: LODs with visibility_range, occlusion culling, mesh merging for static props, MultiMesh for repeated props, texture atlases, shader variant control.
18. Build order and definition of done
Build in ten milestones. Prove the look and the feel early with one vertical slice, then widen. Each milestone ends with a playable build on desktop and web, screenshots from the bookmark cameras, a perf report and a short changelog.
1.  Foundations. Monorepo, CI, Godot project with both export presets, QualityManager, the shared JSON configs and protocol generator. Confirm the Compatibility renderer's lightmap support on the pinned Godot version.
2.  Look-dev vertical slice (art first). One finished corner of SOLSTICE (about 40 × 40 m): modular kit, trims, tiling materials, 20 props, baked lighting, LUT, sky. One agent (KESTREL) fully modelled and textured, and the Saber rifle with first-person arms, all animations and effects. It must look like a shipped game on both renderers before anything else proceeds. Send me screenshots for approval.
3.  Offline game feel. Movement, gunplay, recoil patterns, hit effects, sounds and the Range map with bots. Tune until counter-strafing and first-shot taps feel crisp.
4.  Authoritative server core. Node match worker with 64 Hz sim, collision export, prediction and reconciliation, interpolation, lag-compensated hitscan, golden-vector parity tests. 10 bots + real players in one match.
5.  Round loop. Buy phase, economy, Breach Charge plant/defuse, rounds, halftime, overtime, scoreboard, spectate and death recap.
6.  Full SOLSTICE. Blockout of the whole map → playtests → full art pass, lighting and optimization. Fog-of-war culling.
7.  Agents and abilities. All eight agents with all abilities, VFX, SFX, first-person arms and third-person animations.
8.  Front end and backend. Accounts, guest login, parties, matchmaking, agent select, menus, settings, crosshair editor, match history.
9.  NEON DISTRICT and the full weapon roster. Second map art-complete; all 15 weapons and the knife with icons and the skin system.
10.  Polish and launch prep. Replays, anti-cheat heuristics, colour-blind modes, voice chat, load-testing (200 concurrent matches), browser loading optimizations, final art polish pass on every bookmark camera.
Definition of done for the whole game
[ ] Two competitive maps and the Range are art-complete and pass the readability capture (character contrast 3:1 or better everywhere).
[ ] Eight agents and 16 weapons are fully modelled, textured, animated and voiced with placeholders.
[ ] Desktop hits 144 fps at Medium and the browser build holds 60 fps on the reference laptop.
[ ] Ten players can finish a full 13-round match on the Node server with ping under 80 ms and no desyncs.
[ ] Movement parity tests pass; hit registration is server-validated with lag compensation.
[ ] The browser build loads in under 20 s on a first visit and supports full matches with desktop players.
[ ] Every third-party asset, font and sound is logged with its licence in docs/CREDITS.md, and nothing comes from another game.
[ ] Screenshots from every bookmark camera look like a finished, premium tactical shooter and match the reference images' quality bar.
Final instruction: start with milestone 1 now. At the end of each milestone, summarise what you built, show the screenshots and perf numbers, list open problems, and wait for my approval before starting the next one.
