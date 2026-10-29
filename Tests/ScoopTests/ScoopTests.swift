import Cadova
import Testing
@testable import scoop

@Test("Level capacity matches the generated cavity", arguments: BowlShape.allCases, [
    (5.0, 0.5), (30.0, 0.6), (100.0, 1.0), (250.0, 2.0)
])
func capacity(shape: BowlShape, proportions: (Double, Double)) async throws {
    let (capacity, depthRatio) = proportions
    let c = ScoopConfiguration(bowlShape: shape, capacity: capacity, depthRatio: depthRatio)
    let volume = try await ModelFileGenerator.evaluate { evaluator in
        await evaluator.measurements(of: Scoop(configuration: c).cavity
            .withSegmentation(minAngle: 2°, minSize: 0.2)).volume
    }
    #expect(abs(volume - capacity * 1000) / (capacity * 1000) < 0.001)
}

@Test("Bowl opens on the bed and has a closed dome above it")
func dimensionsAndOrientation() async throws {
    let c = ScoopConfiguration()
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        let bounds = try #require(await evaluator.bounds(of: model))
        #expect(abs(c.effectiveInnerDiameter - 44.2) < 0.05)
        #expect(abs(bounds.size.x - (c.outerRadius + c.handleEnd)) < 0.01)
        #expect(abs(bounds.size.y - c.outerRadius * 2) < 0.01)
        #expect(abs(bounds.minimum.z) < 0.01)
        #expect(abs(bounds.maximum.z - c.bowlHeight) < 0.01)
        #expect(await evaluator.components(of: model).count == 1)

        // The center is empty at the bed. A ray from above crosses the dome
        // exterior and the flat interior bridge, both above the bed.
        let surfaces = await evaluator.surfaces(of: model, from: [0, 0, c.bowlHeight + 10], in: .down)
        // A ray on a shared edge can hit several triangles at the same point.
        let heights = surfaces.map(\.position.z).reduce(into: [Double]()) { heights, z in
            if !heights.contains(where: { abs($0 - z) < 0.001 }) {
                heights.append(z)
            }
        }
        #expect(heights.count == 2)
        #expect(abs(surfaces.first!.position.z - c.bowlHeight) < 0.01)
        #expect(abs(surfaces.last!.position.z - c.innerRoofHeight) < 0.01)
        let opening = await evaluator.surfaces(of: model, from: [0, 0, 0], in: .up)
        #expect(abs(opening.first!.position.z - c.innerRoofHeight) < 0.01)
    }
}

@Test("Layers below the bridge stay within 45 degrees", arguments: [
    ScoopConfiguration(),
    ScoopConfiguration(capacity: 5, depthRatio: 0.5, wallThickness: 1.2),
    ScoopConfiguration(capacity: 250, depthRatio: 2)
])
func printableLayers(configuration c: ScoopConfiguration) async throws {
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        let layerHeight = 0.2
        let tangentHeight = c.straightHeight + c.innerRadius / Double(2).squareRoot()
        let heights = [0.05, c.straightHeight - 0.1,
                       c.straightHeight + c.innerRadius * 0.3,
                       tangentHeight - 0.1, tangentHeight + 0.1,
                       c.innerRoofHeight - layerHeight - 0.05]
        for height in heights {
            let unsupported = model.sliced(atZ: height + layerHeight)
                .subtracting {
                    model.sliced(atZ: height)
                        .offset(amount: layerHeight + 0.001, style: .round)
                }
            let area = await evaluator.measurements(of: unsupported).area
            #expect(area < 0.002, "Unsupported layer growth at z=\(height): \(area) mm²")
        }
    }
}

@Test("Positive diameters open a hole while zero leaves a solid handle", arguments: BowlShape.allCases, [0.5, 6.0])
func hangingHole(shape: BowlShape, diameter: Double) async throws {
    try await ModelFileGenerator.evaluate { evaluator in
        let c = ScoopConfiguration(bowlShape: shape, holeDiameter: diameter)
        let open = Scoop(configuration: c)
        var closedConfiguration = c
        closedConfiguration.holeDiameter = 0
        let closed = Scoop(configuration: closedConfiguration)
        let openHits = await evaluator.surfaces(of: open, from: [c.holeCenter, 0, c.bowlHeight + 1], in: .down)
        let closedHits = await evaluator.surfaces(of: closed, from: [c.holeCenter, 0, c.bowlHeight + 1], in: .down)
        #expect(openHits.isEmpty)
        #expect(closedHits.count == 2)
        let difference = await evaluator.measurements(of: closed).volume
            - evaluator.measurements(of: open).volume
        // Cylinder plus the extra volume from the 45° entrance chamfer.
        let bevel = ScoopConfiguration.bottomChamfer
        let radius = diameter / 2
        let expectedRemoval = Double.pi * (radius * radius * c.gripThickness
            + radius * bevel * bevel + bevel * bevel * bevel / 3)
        #expect(abs(difference - expectedRemoval) < 0.15)
    }
}

@Test("Cavity is spherical below the 45 degree tangent and stays enclosed")
func sphericalInterior() async throws {
    let c = ScoopConfiguration()
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        // At 90% of the inner radius the sphere is still curved. A full cone
        // would put this ceiling at only 10% of the radius above the rim.
        let x = c.innerRadius * 0.9
        let surfaces = await evaluator.surfaces(of: model, from: [x, 0, 0], in: .up)
        let expectedInnerZ = c.straightHeight + c.innerRadius * (1 - 0.9 * 0.9).squareRoot()
        let inner = try #require(surfaces.first)
        #expect(abs(inner.position.z - expectedInnerZ) < 0.05)

        let scoop = Scoop(configuration: c)
        let outsideOuter = await evaluator.measurements(of: scoop.cavity
            .subtracting { scoop.exterior }).volume
        #expect(outsideOuter < 0.001)
    }
}

@Test("Outer bottom stays hemispherical and the bridge has enough roof material", arguments: [
    ScoopConfiguration(),
    ScoopConfiguration(capacity: 250, depthRatio: 0.5, wallThickness: 1.2)
])
func roundedOutside(configuration c: ScoopConfiguration) async throws {
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        for fraction in [0.0, 0.3, 0.6, 0.9] {
            // Sample away from the handle's intentional blend into the sphere.
            let x = -c.outerRadius * fraction
            let hits = await evaluator.surfaces(of: model, from: [x, 0, c.bowlHeight + 10], in: .down)
            let outer = try #require(hits.first)
            let expectedZ = c.outerStraightHeight + c.outerRadius * (1 - fraction * fraction).squareRoot()
            #expect(abs(outer.position.z - expectedZ) < 0.05)
        }

        // The sharp inner bridge corner is closest to the outer sphere.
        // Cast outward along the sphere's radius to measure actual material.
        let nx = c.bridgeRadius / c.innerRadius
        let nz = (c.innerRadius - c.sphereCenterOffset) / c.innerRadius
        let hits = await evaluator.surfaces(of: model,
                                          from: [c.bridgeRadius - nx * 0.1, 0, c.innerRoofHeight - nz * 0.1],
                                          in: Direction3D([nx, 0, nz]))
        let inner = try #require(hits.first)
        let outer = try #require(hits.last)
        #expect(outer.distance - inner.distance >= c.wallThickness - 0.05)

        let bridgeCenter = await evaluator.firstSurface(of: model, from: [0, 0, 0], in: .up)
        let bridgeEdge = await evaluator.firstSurface(of: model,
                                                      from: [c.bridgeRadius - 0.1, 0, 0], in: .up)
        #expect(abs(try #require(bridgeCenter).position.z - c.innerRoofHeight) < 0.01)
        #expect(abs(try #require(bridgeEdge).position.z - c.innerRoofHeight) < 0.01)
    }
}

@Test("Bottom chamfer continues under the brace and around the hole", arguments: BowlShape.allCases)
func completeBottomChamfer(shape: BowlShape) async throws {
    let c = ScoopConfiguration(bowlShape: shape, holeDiameter: 6)
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        for x in [c.outerRadius + 2, c.braceEnd + 5] {
            for z in [0.05, 0.35] {
                let hit = try #require(await evaluator.firstSurface(of: model,
                    from: [x, c.effectiveHandleWidth / 2 + 1, z], in: .negativeY))
                let inset = max(0, 0.3 - z)
                #expect(abs(hit.position.y - (c.effectiveHandleWidth / 2 - inset)) < 0.01)
            }
        }
        for z in [0.05, 0.35] {
            let hit = try #require(await evaluator.firstSurface(of: model,
                from: [c.holeCenter, 0, z], in: .positiveY))
            let entranceRelief = max(0, 0.3 - z)
            #expect(abs(hit.position.y - (c.effectiveHoleDiameter / 2 + entranceRelief)) < 0.01)
        }
    }
}

@Test("Handle width cannot exceed the bowl outside width")
func handleWidthLimit() async throws {
    let c = ScoopConfiguration(capacity: 5, depthRatio: 0.5, wallThickness: 1.2,
                               handleLength: 40, handleWidth: 30)
    #expect(c.effectiveHandleWidth < 30)
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        let handleBounds = try #require(await evaluator.bounds(of: model.handleOutline))
        #expect(abs(handleBounds.size.y - c.outerRadius * 2) < 0.01)
        let bounds = try #require(await evaluator.bounds(of: model))
        #expect(bounds.size.y <= c.outerRadius * 2 + 0.01)
        #expect(await evaluator.components(of: model).count == 1)
    }
}

@Test("Brace curves smoothly into the sphere and flat grip")
func curvedBrace() async throws {
    let c = ScoopConfiguration()
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        var heights: [Double] = []
        for x in [c.outerRadius + 2, c.outerRadius + c.neckLength / 2, c.braceEnd - 2] {
            let hit = try #require(await evaluator.firstSurface(of: model,
                from: [x, 0, c.bowlHeight + 10], in: .down))
            heights.append(hit.position.z)
        }
        #expect(heights[1] < (heights[0] + heights[2]) / 2 - 0.2)
        #expect(heights[1] > c.gripThickness + 0.2)

        let before = try #require(await evaluator.firstSurface(of: model,
            from: [c.braceEnd - 0.5, 0, c.bowlHeight], in: .down))
        let after = try #require(await evaluator.firstSurface(of: model,
            from: [c.braceEnd + 0.5, 0, c.bowlHeight], in: .down))
        #expect(abs(before.position.z - after.position.z) < 0.03)

        // The blend is radial about the sphere center, not a curve simply
        // extruded across the width of the handle.
        let wing = try #require(await evaluator.firstSurface(of: model,
            from: [c.outerRadius + c.neckLength / 2, 4, c.bowlHeight], in: .down))
        #expect(wing.position.z < heights[1] - 0.02)
    }
}

@Test("Engraving removes material only from the visible face in use", arguments: BowlShape.allCases)
func lettering(shape: BowlShape) async throws {
    let c = ScoopConfiguration(bowlShape: shape, text: "30 ml")
    try await ModelFileGenerator.evaluate { evaluator in
        let labeled = Scoop(configuration: c)
        let plain = Scoop(configuration: ScoopConfiguration(bowlShape: shape))
        let labeledVolume = await evaluator.measurements(of: labeled).volume
        let plainVolume = await evaluator.measurements(of: plain).volume
        #expect(labeledVolume < plainVolume - 1)
        #expect(await evaluator.components(of: labeled).count == 1)
        let upperDifference = plain.subtracting { labeled }
            .trimmed(along: .z(c.textDepth + 0.01))
        #expect(await evaluator.measurements(of: upperDifference).volume < 0.001)
        let removedBounds = try #require(await evaluator.bounds(of: plain.subtracting { labeled }))
        #expect(abs(removedBounds.minimum.z) < 0.01)
        #expect(abs(removedBounds.maximum.z - c.textDepth) < 0.01)

        // Mirrored in the print XY plane, the underside engraving reads
        // correctly after flipping the scoop about the handle axis for use.
        let removed = plain.subtracting { labeled }
        let expected = labeled.engraving
        #expect(await evaluator.measurements(of: removed.subtracting { expected }).volume < 0.001)
        #expect(await evaluator.measurements(of: expected.subtracting { removed }).volume < 0.001)
    }
}

@Test("Top fillet continues from the curved brace onto the flat handle", arguments: [
    ScoopConfiguration(),
    ScoopConfiguration(bowlShape: .cylindrical),
    ScoopConfiguration(bowlShape: .cylindrical, capacity: 5, depthRatio: 0.5,
                       wallThickness: 4, handleWidth: 30)
])
func continuousTopFillet(configuration c: ScoopConfiguration) async throws {
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        for side in [-1.0, 1.0] {
            let y = side * (c.effectiveHandleWidth / 2 - 0.2)
            for x in [c.outerRadius + c.neckLength / 2, c.braceEnd - 2, c.braceEnd + 2] {
                let radius = (x * x + y * y).squareRoot()
                let sharpRoof = radius < c.braceEnd
                    ? c.braceCenterHeight - (c.braceRadius * c.braceRadius
                        - (c.braceEnd - radius) * (c.braceEnd - radius)).squareRoot()
                    : c.gripThickness
                let hit = try #require(await evaluator.firstSurface(of: model,
                    from: [x, y, c.bowlHeight], in: .down))
                // The same rounding must remove the sharp corner on both
                // the curved and flat portions, on both sides of the handle.
                #expect(sharpRoof - hit.position.z > 0.1)
                #expect(sharpRoof - hit.position.z < 0.25)
            }

            let seamX = (c.braceEnd * c.braceEnd - y * y).squareRoot()
            let before = try #require(await evaluator.firstSurface(of: model,
                from: [seamX - 0.2, y, c.bowlHeight], in: .down))
            let after = try #require(await evaluator.firstSurface(of: model,
                from: [seamX + 0.2, y, c.bowlHeight], in: .down))
            #expect(abs(before.position.z - after.position.z) < 0.02)
        }
    }
}

@Test("Lettering uses the requested font size and ends beside the hole", arguments: [
    ScoopConfiguration(holeDiameter: 6, text: "30 ml"),
    ScoopConfiguration(text: "30 ml", textSize: 10),
    ScoopConfiguration(bowlShape: .cylindrical, handleWidth: 30, holeDiameter: 8, text: "Tea", textSize: 20)
])
func labelLayout(configuration c: ScoopConfiguration) async throws {
    let label = try #require(c.label)
    let area = c.labelArea
    #expect(label.fontSize == c.textSize)
    try await ModelFileGenerator.evaluate { evaluator in
        let bounds = try #require(await evaluator.bounds(of: label))
        // Right-aligned by advance width: only the last glyph's side bearing remains.
        #expect(bounds.maximum.x <= area.maximum.x + 0.01)
        #expect(bounds.maximum.x > area.maximum.x - label.fontSize * 0.15)
        #expect(bounds.minimum.x >= area.minimum.x)
        #expect(bounds.minimum.y >= area.minimum.y && bounds.maximum.y <= area.maximum.y)
        #expect(bounds.size.y < label.fontSize)
    }
    if c.hasHole {
        #expect(area.maximum.x < c.holeCenter - c.effectiveHoleDiameter / 2)
    }
}

@Test("Proportions set depth relative to diameter as capacity changes", arguments: BowlShape.allCases, [
    (30.0, 0.8), (100.0, 0.8), (250.0, 1.5)
])
func proportions(shape: BowlShape, values: (Double, Double)) {
    let (capacity, depthRatio) = values
    let c = ScoopConfiguration(bowlShape: shape, capacity: capacity, depthRatio: depthRatio)
    #expect(!c.isDepthLimited)
    #expect(abs(c.actualDepthRatio - depthRatio) < 0.001)
    #expect(abs(c.volume(radius: c.innerRadius, depth: c.innerRoofHeight) - capacity * 1000) < 0.01)
    #expect(c.summary.hasPrefix("Inner diameter: "))
}

@Test("Text size does not depend on which characters are used")
func characterIndependentSize() async throws {
    let low = try #require(ScoopConfiguration(text: "ace").label)
    let tall = try #require(ScoopConfiguration(text: "Tlg").label)
    #expect(low.fontSize == tall.fontSize)
    #expect(low.anchor == tall.anchor)
}

@Test("Long labels shrink to fit, but not below the minimum size")
func fittedLabel() async throws {
    let c = ScoopConfiguration(holeDiameter: 6, text: "Coffee beans", textSize: 12)
    let label = try #require(c.label)
    #expect(label.fontSize < c.textSize)
    #expect(label.fontSize >= HandleLabel.minimumFontSize)
    #expect(c.summary.contains("Text size reduced to"))
    try await ModelFileGenerator.evaluate { evaluator in
        let bounds = try #require(await evaluator.bounds(of: label))
        #expect(bounds.size.x <= c.labelArea.size.x + 0.01)
        #expect(bounds.size.x > c.labelArea.size.x - label.fontSize * 0.3)
    }
    #expect(!ScoopConfiguration(text: "30 ml").summary.contains("Text size"))

    let tooLong = ScoopConfiguration(text: "A long label that cannot fit at a legible size")
    #expect(tooLong.hasText)
    #expect(tooLong.label == nil)
    #expect(tooLong.summary.contains("Text doesn't fit"))
}

@Test("Hole diameter leaves a minimum margin on both sides", arguments: [12.0, 18.0, 30.0])
func holeLimit(handleWidth: Double) {
    let c = ScoopConfiguration(handleWidth: handleWidth, holeDiameter: 100)
    #expect(c.effectiveHoleDiameter == c.maximumHoleDiameter)
    #expect(c.effectiveHandleWidth - c.effectiveHoleDiameter >= 2 * ScoopConfiguration.minimumHoleMargin)
    #expect(c.effectiveHandleWidth - c.effectiveHoleDiameter < 2 * ScoopConfiguration.minimumHoleMargin + 0.5)
}

@Test("Handle keeps its full width up to the bowl", arguments: [
    ScoopConfiguration(),
    ScoopConfiguration(bowlShape: .cylindrical, capacity: 5, depthRatio: 0.5,
                       wallThickness: 4, handleWidth: 30)
])
func straightHandle(configuration c: ScoopConfiguration) async throws {
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        let halfWidth = c.effectiveHandleWidth / 2
        // Just outside where the handle side meets the bowl, at bed level above the chamfer.
        let junction = (c.outerRadius * c.outerRadius - halfWidth * halfWidth).squareRoot()
        for x in [junction + 0.2, c.outerRadius + 0.5, c.holeCenter - 1] {
            let hit = try #require(await evaluator.firstSurface(of: model,
                from: [x, halfWidth + 1, 0.5], in: .negativeY))
            #expect(abs(hit.position.y - halfWidth) < 0.01, "x=\(x)")
        }
    }
}

@Test("Cylindrical bowl has tapered walls, a flat bottom, and minimum material", arguments: [
    ScoopConfiguration(bowlShape: .cylindrical),
    ScoopConfiguration(bowlShape: .cylindrical, capacity: 5, depthRatio: 0.5,
                       wallThickness: 1.2, handleLength: 40, handleWidth: 30, handleThickness: 8),
    ScoopConfiguration(bowlShape: .cylindrical, capacity: 5, depthRatio: 0.5, wallThickness: 4),
    ScoopConfiguration(bowlShape: .cylindrical, capacity: 250, depthRatio: 2),
    ScoopConfiguration(bowlShape: .cylindrical, capacity: 250, depthRatio: 0.5, wallThickness: 1.2)
])
func cylindricalBowl(configuration c: ScoopConfiguration) async throws {
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        let bounds = try #require(await evaluator.bounds(of: model))
        #expect(abs(bounds.minimum.z) < 0.01)
        #expect(abs(bounds.maximum.z - c.bowlHeight) < 0.01)
        #expect(bounds.size.y <= c.outerRadius * 2 + 0.01)
        #expect(await evaluator.components(of: model).count == 1)
        let volume = await evaluator.measurements(of: model.cavity
            .withSegmentation(minAngle: 1°, minSize: 0.15)).volume
        #expect(abs(volume - c.capacity * 1000) / (c.capacity * 1000) < 0.001)

        // The outer floor and inner floor must each remain flat well away
        // from the small outside edge fillet, with the requested floor thickness.
        for fraction in [0.0, 0.4, 0.8] {
            let x = -c.cylindricalBottomRadius * fraction
            let outside = try #require(await evaluator.firstSurface(of: model,
                from: [x, 0, c.bowlHeight + 1], in: .down))
            let inside = try #require(await evaluator.firstSurface(of: model,
                from: [x, 0, 0], in: .up))
            #expect(abs(outside.position.z - c.bowlHeight) < 0.01)
            #expect(abs(inside.position.z - c.cylindricalDepth) < 0.01)
            #expect(outside.position.z - inside.position.z >= c.wallThickness - 0.01)
        }

        // The outside bottom corner must actually be rounded, including
        // heights that do not land exactly on the profile mesh's precision.
        let capRadius = c.outerRadius - c.cylindricalSlope
            * (c.bowlHeight - ScoopConfiguration.bottomChamfer)
        let corner = try #require(await evaluator.firstSurface(of: model,
            from: [-capRadius + 0.1, 0, c.bowlHeight + 1], in: .down))
        #expect(corner.position.z < c.bowlHeight - 0.1)

        var openingRadius = 0.0
        var bottomRadius = 0.0
        for z in [0.5, c.cylindricalDepth - 0.5] {
            let hits = await evaluator.surfaces(of: model, from: [0, 0, z], in: .negativeX)
            let inner = try #require(hits.first)
            let outer = try #require(hits.last)
            let normalThickness = (outer.distance - inner.distance)
                / (1 + c.cylindricalSlope * c.cylindricalSlope).squareRoot()
            #expect(normalThickness >= c.wallThickness - 0.01)
            if z == 0.5 { openingRadius = -inner.position.x }
            else { bottomRadius = -inner.position.x }
        }
        #expect(bottomRadius < openingRadius)
        #expect((openingRadius - bottomRadius) / (c.cylindricalDepth - 1) <= tan(3°) + 0.001)
        #expect(c.cylindricalBottomRadius >= c.innerRadius * 0.9 - 0.001)
        #expect(await evaluator.measurements(of: model.cavity.subtracting { model.exterior }).volume < 0.001)

        // Mouth-down cylinder walls grow safely until the flat bottom begins
        // bridging. Its full bridge diameter is reported separately.
        for z in [0.05, c.cylindricalDepth / 2, c.cylindricalDepth - 0.25] {
            let unsupported = model.sliced(atZ: z + 0.2)
                .subtracting { model.sliced(atZ: z).offset(amount: 0.201, style: .round) }
            let area = await evaluator.measurements(of: unsupported).area
            #expect(area < 0.002, "Unsupported cylinder layer at z=\(z): \(area) mm²")
        }
    }
}

@Test("Shallow proportions deepen a small bowl and keep handle and lettering connected")
func shallowScoop() async throws {
    let c = ScoopConfiguration(capacity: 5, depthRatio: 0.5, wallThickness: 1.2,
                               handleLength: 40, handleWidth: 12, handleThickness: 8,
                               holeDiameter: 10,
                               text: "5 ml", textDepth: 1.2)
    #expect(c.isDepthLimited)
    #expect(c.actualDepthRatio > c.depthRatio)
    #expect(c.summary.contains("Bowl deepened"))
    #expect(c.straightHeight >= 3 - 0.001)
    try await ModelFileGenerator.evaluate { evaluator in
        let model = Scoop(configuration: c)
        #expect(await evaluator.components(of: model).count == 1)
        let bounds = try #require(await evaluator.bounds(of: model))
        #expect(abs(bounds.minimum.z) < 0.01)
        #expect(bounds.maximum.z > 1.2)
        let neck = await evaluator.surfaces(of: model,
                                          from: [c.outerRadius + c.neckLength / 2, 0, 20], in: .down)
        #expect(neck.count == 2)
    }
}

@Test("Blank labels leave the solid unchanged")
func blankText() async throws {
    try await ModelFileGenerator.evaluate { evaluator in
        let blank = Scoop(configuration: ScoopConfiguration(text: " \n "))
        let plain = Scoop(configuration: ScoopConfiguration())
        let a = await evaluator.measurements(of: blank).volume
        let b = await evaluator.measurements(of: plain).volume
        #expect(abs(a - b) < 0.001)
    }
}
