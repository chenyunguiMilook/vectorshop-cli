---
name: vectorshop-design
description: Create, render, inspect, revise, and export editable vector designs with the VectorShop MCP tools. Use for posters, menus, flyers, banners, social graphics, business cards, signs, invitations, covers, editable monochrome icons, SF Symbols, and other requests that should deliver a PNG plus an editable .vsp or .vsm source file.
---

# VectorShop Design

Use the VectorShop MCP tools for the complete design loop. Do not replace them with shell commands or hand-written `.vsp` files.

## Choose the document type

For monochrome icons, SF Symbols, or `.vsm` requests, use the symbol workflow below. For posters and other composed designs, use the `.vsp` workflow. `.vsm` icons use native shapes, boolean operations and three weight masters; they are separate from `.vsp` reusable component instances.

## Symbol workflow

1. Call `symbol_emit` with the brief before writing a symbol spec. It returns the current schema, coordinate/boolean-order rules and runnable examples.
2. Create a spec with stable page/shape IDs. Use a consistent viewBox and stroke/corner style across an icon family. For existing `.vsm` work, call `symbol_get_design(file)` to retain native geometry, reference assets and page metadata.
3. Call `symbol_render` and inspect the actual UltraLight/Regular/Black and 16/24/32px previews. Check recognition, optical centering, margins, endpoints and negative space. Fix every geometry error and visible defect.
4. Iterate with `symbol_render(designId, revision, patch)`. Use `symbol_get_design(designId)` when the current spec is unclear. Render every page at the current revision before export.
5. Deliver with `symbol_export(designId, revision, outPath)` using an absolute `.vsm` path. This writes the editable native document and transparent PNGs. Request `svg:"plain"` for an ordinary SVG, or `svg:"sf-symbol"` for an SF Symbols template when requested; report template export separately from system/runtime compatibility validation.
6. Deliver the PNG and `.vsm`; include any requested SVG. `.vsm` editing currently has no `.vsp` Pro lock. Do not reuse `.vsp` Pro messages for icons.

If the connected server lacks `symbol_*`, explain that its CLI binary needs the release containing symbol authoring. Do not fabricate unavailable tools or hand-write package internals.

## .vsp workflow

1. Read the user's brief, target dimensions, copy, assets, language, and delivery location. Make conservative assumptions when details are missing.
2. Call `list_categories` when the category is unclear. Call `emit` with the brief and selected category before writing DSL.
3. Use `get_skill` and `get_example` only when the emitted guidance points to a relevant foundation, category, or example. Do not load unrelated material.
4. Build one coherent component-DSL document from the returned guidance. Use user-supplied assets through the tools' `assets` argument; do not invent local paths.
5. Call `render`. Inspect the returned image itself, not only the DSL or validation text. Check hierarchy, spacing, alignment, contrast, cropping, legibility, and visual balance.
6. Fix every reported red line and any visible design defect, then render again. The first `render` returns a `designId`: for every later round call `render` with that `designId` and a `patch` (`set` / `replace` / `remove` / `insert` / `move`, located by element `id`) instead of resending the whole DSL. Call `get_design` if you need to see the current DSL. Continue until the image is polished and `redLineCount` is zero.
7. Call `export` only after the final render is satisfactory. Pass the `designId` of that final render (not the DSL) and an absolute `.vsp` output path. Do not set `replace:true` unless the user explicitly approved overwriting existing output.
8. Deliver both the PNG and `.vsp`. In a messaging channel, attach the generated files when the host provides a file-send tool; otherwise report their absolute paths clearly.

## Quality and delivery rules

- Preserve the user's exact factual copy unless they ask for rewriting. Flag missing facts instead of fabricating prices, dates, addresses, claims, or contact details.
- Prefer a small number of strong visual ideas over crowded decoration.
- Keep text inside safe margins and make the main message readable at thumbnail size.
- Use `render` / `symbol_render` for in-memory iteration and `export` / `symbol_export` for writing deliverables.
- For `.vsp` designs, default to free 1x output. Request 2x or 3x only when the user asks for it; if Pro entitlement is unavailable, deliver 1x and explain the limitation.
- Never claim completion before inspecting the final rendered image.
