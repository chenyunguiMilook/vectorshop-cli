---
name: vectorshop-design
description: Create, render, inspect, revise, and export editable vector designs with the VectorShop MCP tools. Use for posters, menus, flyers, banners, social graphics, business cards, signs, invitations, covers, and other requests that should deliver a polished PNG plus an editable .vsp source file.
---

# VectorShop Design

Use the VectorShop MCP tools for the complete design loop. Do not replace them with shell commands or hand-written `.vsp` files.

## Workflow

1. Read the user's brief, target dimensions, copy, assets, language, and delivery location. Make conservative assumptions when details are missing.
2. Call `list_categories` when the category is unclear. Call `emit` with the brief and selected category before writing DSL.
3. Use `get_skill` and `get_example` only when the emitted guidance points to a relevant foundation, category, or example. Do not load unrelated material.
4. Build one coherent component-DSL document from the returned guidance. Use user-supplied assets through the tools' `assets` argument; do not invent local paths.
5. Call `render`. Inspect the returned image itself, not only the DSL or validation text. Check hierarchy, spacing, alignment, contrast, cropping, legibility, and visual balance.
6. Fix every reported red line and any visible design defect, then render again. Continue until the image is polished and `redLineCount` is zero.
7. Call `export` only after the final render is satisfactory. Pass the same DSL used for that render and an absolute `.vsp` output path. Do not set `replace:true` unless the user explicitly approved overwriting existing output.
8. Deliver both the PNG and `.vsp`. In a messaging channel, attach the generated files when the host provides a file-send tool; otherwise report their absolute paths clearly.

## Quality and delivery rules

- Preserve the user's exact factual copy unless they ask for rewriting. Flag missing facts instead of fabricating prices, dates, addresses, claims, or contact details.
- Prefer a small number of strong visual ideas over crowded decoration.
- Keep text inside safe margins and make the main message readable at thumbnail size.
- Treat `render` as read-only iteration and `export` as the only file-writing design tool.
- Default to free 1x output. Request 2x or 3x only when the user asks for it; if Pro entitlement is unavailable, deliver 1x and explain the limitation.
- Never claim completion before inspecting the final rendered image.
