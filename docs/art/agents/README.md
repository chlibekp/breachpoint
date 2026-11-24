# Agent concept notes (code-built characters)

All eight agents are built in code (no Blender): `client/scripts/agents/`.

- `form_kit.gd` (FormKit, extends MeshKit) has smooth superellipse lofts, swept tubes, surface patches
  and colour-block panels. Vertex colour carries painted AO (darker toward the feet and in folds).
- `agent_body.gd` (AgentBody) is the shared anatomy: about 7.5 heads tall, tapered torso, shaped
  limbs, hands with a thumb and fingers, combat boots, a stylised face (brow/nose/jaw planes, large
  eyes with iris, pupil, catch-light and a lash line, plus lips, ears and brows). It also has the
  hair cap and hair mass, `beard`, `collar` and `open_shell` (double-sided coats, capes, hoods and
  ponchos).
- `agent_looks.gd` (AgentLooks) dresses each agent. Each agent gets one signature colour and one
  signature shape (spec §6.1).
- Pass 2 (look):
  - Detail textures: `tools/texgen/chargen.py` makes weave, canvas, quilt, knit, leather, metal,
    skin and hair detail sets. M_Character projects them triplanar in mesh space.
  - Shader: a painterly two-tone ramp with a warm terminator band, cool lifted shades, and crisp
    highlights on smooth surfaces.
  - Build-time bake (`AgentRig.finalize`): voxel ambient occlusion, a head-to-toe value gradient,
    skin tints (blush, nose, ears), and a slightly bigger head, hands and feet. The baked meshes
    are cached per agent.
  - Shapes: fabric folds and tucks (`FormKit.folds` / `tuck`), sculpted hair clumps
    (`AgentBody.hair_clumps`), eyelids, glove cuffs.
  - Animation: contrapposto idle with sway and breathing; elbows down when aiming.
- Review with `scenes/dev/charsheet.tscn` (`--view=turn|face|bust|busts|all`, `--pose=rest|aim`).
  It prints triangle counts.

The genders and builds below are open choices, recorded here. Only SABLE's ("her") is fixed by
`agents.json`.

| Agent | Build | Signature colour | Signature shape | Supporting read |
|---|---|---|---|---|
| KESTREL | F, fair, ash-blonde undercut | signal orange | cropped bomber jacket with an open stand collar (shearling lining), twin-thruster pack with nacelles in a V behind the shoulders | flying goggles on the forehead, reflective rescue bands, harness, slate flight-suit cargo trousers |
| MAMBA | M, deep skin, lean | acid green | deep green racing hood with a wrap-around glowing visor | satin-black suit with a green chevron livery and side stripes, sleek knee guards, white racing shoes, spine plates |
| VESPER | F, light, dark bob with a bun | deep violet | long split-skirt coat plus a star-chart cape to the calves | high lined collar, double row of brass buttons, glowing constellation on the cape, floating brass orrery |
| HALDOR | M, fair, bulky (bulk 1.14) | steam white + basalt | quilted heat-suit under a basalt plate rig, twin exhaust stacks above the head | heavy right gauntlet with a vent barrel, layered pauldrons, full auburn beard and braid |
| ORIN | M, tan | dusty ochre | wide-brim hat and a striped A-line poncho with a fringe | mechanical hawk on the left shoulder (amber eyes), stubble and moustache, rolled sleeves |
| SABLE | F, light, black bob with blunt bangs | electric blue + white trim | oversized boxy jacket with dropped shoulders and long sleeves | headphones round the neck, a back signal module with cables, holo tablet on the left forearm, chunky white sneakers |
| IMANI | F, deep skin, braids with gold beads | warm gold | gold medic plate carrier with shoulder guards and bracers, white medkit backpack with a glowing gold cross | cornrows into hanging braids, armband, olive fatigues |
| TOMAS | M, tan, sturdy | copper | copper hard hat with headlamp and goggles, mechanical right arm | loaded tool belt (pouches, hammer, wrench), moustache, rolled left sleeve, steel-toe boots |

Rules kept:

- All shapes, outfits and faces are original. The reference images set the quality bar only.
- Hitboxes are unchanged and identical for every agent (spec §6.2). Only the visual mesh differs.
- Triangle budget: 20k or less per agent (13.4k–20.1k after pass 2).
- Tiny face details (eyes, lashes, lips, brows, glows) skip the silhouette outline pass
  (`no_outline`), so the two-tone map outline never rings them.
- The first-person arm colours (`viewmodel.gd` `_arm_look`) match each agent's sleeves, cuffs and
  gloves.
