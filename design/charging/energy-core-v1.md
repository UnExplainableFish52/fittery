# Illuminated energy core - Build 20

The center of the charging gauge now uses cyan/teal and violet light pools, peripheral flowing contour lines, fine orbital arcs/nodes, a glass-like reflection, and a restrained rim halo. The percentage sits in a quiet central band with a small cyan text glow. All artwork is drawn in Flutter at the actual gauge size; no bitmap or dependency was added.

The decorative core is an independent `RepaintBoundary` with a constant painter that does not request animation frames. The measured neon track still uses the validated live battery percentage. Only the existing small charging glint animates, inside the filled arc. Decorative arcs are thin and subdued so they remain distinct from the thick green/cyan measurement track. The original supplied logo/card graphics and dashboard interactions are retained.

Physical-device feedback should focus on center contrast, the cyan/violet balance, and whether the extra detail stays readable at normal brightness. Automated checks cover the existing battery levels, unavailable data, compact layouts, reduced motion, and dismissal behavior.
