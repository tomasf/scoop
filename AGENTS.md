# Scoop design constraints

- Offer Round bottom (default) and Cylindrical (slightly tapered) bowl shapes. The round variant's outer bottom must be a smooth, true hemisphere; apply its overhang relief only to the inner cavity. The cylindrical variant has a flat bottom, with wall taper capped at 3° and total radius reduction capped at 10%.
- Always use fine segmentation (1° minimum angle, 0.15 mm minimum segment size). Do not expose a quality parameter.
- Keep the model oriented for printing with the bowl opening on the bed and the handle resting on the bed. Only the customizer preview is flipped 180° about X to show the scoop as used.
- The handle's bottom chamfer must continue beneath the brace and around the hanging hole. Apply it to the assembled footprint after joining the brace and cutting openings.
- Apply the handle's top fillet after joining the curved brace, so the rounding continues smoothly onto the flat grip.
- Use the bundled Fredoka font at weight 550 for handle lettering, matching qr-code-cadova.
- Optional text is engraved only, on the bed-facing underside of the handle, mirrored to read correctly when the scoop is flipped for use. Target a 0.4 mm nozzle; default to 7 mm font size, which is also the minimum, and 0.6 mm engraving depth. Size and align text from font metrics, never from the glyph outlines of the particular string. Report the fitted size if the label shrinks; never shrink below the minimum, and report text that doesn't fit instead. Right-align the label against the hanging hole, or the handle's rounded end when there is no hole.
- Size the bowl from capacity and a Proportions control (inner depth ÷ inner diameter), not a diameter control, so it keeps its shape as capacity changes. Always show the resulting inner diameter in the description.
- Keep customizer copy concise. The main description contains only inner diameter, bowl height, bridge span and actual automatic adjustments; never repeat selected parameter values or general model features. Show fitted text size only when it differs from the requested size.
- Use a single Hole diameter control, defaulting to 0 mm for no hole; do not expose a separate switch. Positive diameters enable the hole and its bottom chamfer. Limit the hole to the handle width minus a 3 mm margin on each side.
- Blend the handle into the bowl with a curve tangent to its outer surface: toward the sphere center for round bowls, and into the tapered wall for cylindrical bowls. The handle keeps its full width with straight sides all the way into the bowl, and its width must not exceed the bowl's outside diameter.
- Preserve the requested capacity and minimum wall thickness when changing cavity geometry. Report any automatic deepening and the internal bridge span in the customizer.
- Verify geometry changes with the tests and actual cadova-viewer renders, including an axial section through the bowl and handle.
