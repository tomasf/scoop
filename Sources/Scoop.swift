import Cadova
import Foundation

enum BowlShape: String, ParameterChoice {
    case roundBottom, cylindrical

    var displayName: String {
        switch self {
        case .roundBottom: "Round bottom"
        case .cylindrical: "Cylindrical"
        }
    }
}

struct ScoopConfiguration: Sendable {
    static let bottomChamfer = 0.3
    static let maximumCylinderTaper = 3°
    static let maximumCylinderRadiusReduction = 0.1
    static let minimumHoleMargin = 3.0

    var bowlShape = BowlShape.roundBottom
    var capacity = 30.0
    var depthRatio = 0.6
    var wallThickness = 2.0
    var handleLength = 80.0
    var handleWidth = 18.0
    var handleThickness = 5.0
    var holeDiameter = 0.0
    var text = ""
    var textSize = 7.0
    var textDepth = 0.6

    // Keep enough depth at the opening to attach the handle, deepening the
    // bowl when the chosen proportions would otherwise be too shallow.
    var minimumRimHeight: Double { max(3, wallThickness * 2) }
    func innerDepth(radius: Double) -> Double {
        let rimDepth = bowlShape == .roundBottom ? minimumRimHeight + radius : minimumRimHeight
        return max(radius * 2 * depthRatio, rimDepth)
    }
    func volume(radius: Double, depth: Double) -> Double {
        switch bowlShape {
        case .roundBottom:
            .pi * radius * radius * (depth - radius + radius * Self.domeVolumeFactor)
        case .cylindrical:
            Self.cylindricalVolume(radius: radius, depth: depth)
        }
    }
    var innerRadius: Double {
        let volume = capacity * 1000
        // Any bowl holds at least a cylinder of its narrowest radius and rim height.
        let upper = (volume / (.pi * minimumRimHeight)).squareRoot() / (1 - Self.maximumCylinderRadiusReduction)
        return Self.largestValue(below: upper) { radius in
            self.volume(radius: radius, depth: innerDepth(radius: radius)) <= volume
        }
    }
    var isDepthLimited: Bool { innerDepth(radius: innerRadius) > innerRadius * 2 * depthRatio + 0.01 }
    var actualDepthRatio: Double { innerRoofHeight / (innerRadius * 2) }

    /// The largest value in 0...upper satisfying a condition that holds below some threshold.
    static func largestValue(below upper: Double, where condition: (Double) -> Bool) -> Double {
        var lower = 0.0, upper = upper
        for _ in 0..<60 {
            let value = (lower + upper) / 2
            if condition(value) { lower = value } else { upper = value }
        }
        return lower
    }
    var effectiveInnerDiameter: Double { innerRadius * 2 }
    var outerRadius: Double {
        let radialThickness = bowlShape == .cylindrical
            ? wallThickness * sqrt(1 + cylindricalSlope * cylindricalSlope) : wallThickness
        return innerRadius + radialThickness
    }
    var innerArea: Double { .pi * innerRadius * innerRadius }
    // Upper teardrop volume minus its tip above the sphere's original height.
    static var domeVolumeFactor: Double {
        let tipHeight = sqrt(2) - 1
        return 1 / sqrt(2) - tipHeight * tipHeight * tipHeight / 3
    }
    var domeVolume: Double { .pi * innerRadius * innerRadius * innerRadius * Self.domeVolumeFactor }
    var straightHeight: Double {
        bowlShape == .roundBottom ? (capacity * 1000 - domeVolume) / innerArea : cylindricalDepth
    }
    var bridgeRadius: Double {
        bowlShape == .roundBottom ? innerRadius * (sqrt(2) - 1) : cylindricalBottomRadius
    }
    var bridgeSpan: Double { bridgeRadius * 2 }
    // Raise the outer hemisphere's center so the bridge's outer corner stays
    // within a concentric radius-r sphere. Radius r+t then leaves at least t
    // of material there without changing the rounded outside or bowl diameter.
    var sphereCenterOffset: Double {
        innerRadius - sqrt(innerRadius * innerRadius - bridgeRadius * bridgeRadius)
    }
    var outerStraightHeight: Double { straightHeight + sphereCenterOffset }
    var innerRoofHeight: Double {
        bowlShape == .roundBottom ? straightHeight + innerRadius : cylindricalDepth
    }
    var bowlHeight: Double {
        bowlShape == .roundBottom ? outerStraightHeight + outerRadius : cylindricalDepth + wallThickness
    }

    // Limit both the wall angle and total narrowing: a shallow scoop stays
    // gently tapered, while a tall, narrow scoop never tapers to a point.
    static func cylindricalBottomRadius(radius: Double, depth: Double) -> Double {
        radius - min(radius * maximumCylinderRadiusReduction,
                     max(0, depth - bottomChamfer) * tan(maximumCylinderTaper))
    }
    static func cylindricalVolume(radius: Double, depth: Double) -> Double {
        let bottomRadius = cylindricalBottomRadius(radius: radius, depth: depth)
        let rimHeight = min(depth, bottomChamfer)
        return .pi * radius * radius * rimHeight + .pi * (depth - rimHeight) / 3
            * (radius * radius + radius * bottomRadius + bottomRadius * bottomRadius)
    }
    var cylindricalDepth: Double {
        let radius = innerRadius
        let volume = capacity * 1000
        let upper = volume / (.pi * radius * radius * pow(1 - Self.maximumCylinderRadiusReduction, 2))
        return Self.largestValue(below: upper) { depth in
            Self.cylindricalVolume(radius: radius, depth: depth) < volume
        }
    }
    var cylindricalBottomRadius: Double {
        Self.cylindricalBottomRadius(radius: innerRadius, depth: cylindricalDepth)
    }
    var cylindricalSlope: Double {
        (innerRadius - cylindricalBottomRadius) / (cylindricalDepth - Self.bottomChamfer)
    }
    var cylindricalBottomFillet: Double { min(1, wallThickness / 2) }
    var gripThickness: Double { min(handleThickness, straightHeight) }
    var effectiveHandleWidth: Double { min(handleWidth, outerRadius * 2) }
    var handleEnd: Double { outerRadius + handleLength }
    var holeCenter: Double { handleEnd - effectiveHandleWidth / 2 }
    // Leave solid material on both sides of the hole, in half-millimeter steps.
    var maximumHoleDiameter: Double {
        max(0, ((effectiveHandleWidth - 2 * Self.minimumHoleMargin) * 2).rounded(.down) / 2)
    }
    var effectiveHoleDiameter: Double { max(0, min(holeDiameter, maximumHoleDiameter)) }
    var hasHole: Bool { effectiveHoleDiameter > 0 }
    var neckLength: Double {
        let requested = min(18, handleLength * 0.3)
        guard bowlShape == .cylindrical else { return requested }
        let slope = cylindricalSlope
        let normalLength = sqrt(1 + slope * slope)
        let maximumRadius = (bowlHeight - cylindricalBottomFillet - gripThickness)
            / (1 - slope / normalLength)
        // Keep the tangent point below the flat bottom's rounded edge.
        let maximumLength = maximumRadius * (normalLength - slope)
            - slope * (gripThickness - Self.bottomChamfer)
        return min(requested, maximumLength)
    }
    var braceEnd: Double { outerRadius + neckLength }
    var braceRadius: Double {
        if bowlShape == .cylindrical {
            let slope = cylindricalSlope
            return (neckLength + slope * (gripThickness - Self.bottomChamfer))
                / (sqrt(1 + slope * slope) - slope)
        }
        let rise = outerStraightHeight - gripThickness
        return (braceEnd * braceEnd - outerRadius * outerRadius + rise * rise)
            / (2 * (outerRadius + rise))
    }
    var braceCenterHeight: Double { gripThickness + braceRadius }
    var braceTop: Double {
        if bowlShape == .cylindrical {
            let slope = cylindricalSlope
            return braceCenterHeight - braceRadius * slope / sqrt(1 + slope * slope)
        }
        return max(gripThickness, outerStraightHeight + outerRadius *
            (braceCenterHeight - outerStraightHeight) / (outerRadius + braceRadius))
    }

    // The flat underside runs from the bowl to the handle's rounded end.
    // Keep lettering clear of the bowl, the long edges and the hole.
    var labelArea: BoundingBox2D {
        let end = hasHole ? holeCenter - effectiveHoleDiameter / 2 - 2 : holeCenter
        let halfWidth = effectiveHandleWidth / 2 - 1.5
        return BoundingBox2D(minimum: [outerRadius + 2, -halfWidth], maximum: [end, halfWidth])
    }
    var hasText: Bool { !HandleLabel.normalized(text).isEmpty }
    var label: HandleLabel? {
        HandleLabel(text: text, requestedSize: textSize, area: labelArea)
    }

    /// Inner diameter, bowl height, bridge span and any automatic adjustments.
    var summary: String {
        var lines = ["Inner diameter: \(effectiveInnerDiameter.formatted) mm · Bowl height: \(bowlHeight.formatted) mm"
                     + " · Bridge span: \(bridgeSpan.formatted) mm."]
        if isDepthLimited {
            lines.append("Bowl deepened to leave room for the handle.")
        }
        if effectiveHandleWidth < handleWidth - 0.01 {
            lines.append("Handle width reduced to \(effectiveHandleWidth.formatted) mm.")
        }
        if let label, label.fontSize < textSize - 0.01 {
            lines.append("Text size reduced to \(label.fontSize.formatted) mm to fit.")
        } else if hasText && label == nil {
            lines.append("Text doesn't fit at \(HandleLabel.minimumFontSize.formatted) mm; shorten it.")
        }
        return lines.joined(separator: "\n")
    }
}

fileprivate extension Double {
    /// Rounded to a tenth, without a trailing ".0".
    var formatted: String {
        let tenths = Int((self * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }
}

struct Scoop: Geometry3D {
    let configuration: ScoopConfiguration

    var body: any Geometry3D {
        @Environment(\.buildDestination) var destination

        // Show the customizer preview the way the scoop is used, with the bowl
        // opening and the engraved face upward.
        printable
            .rotated(x: destination == .customizerPreview ? 180° : 0°)
            .translated(z: destination == .customizerPreview ? configuration.bowlHeight : 0)
    }

    @GeometryBuilder3D
    var printable: any Geometry3D {
        let c = configuration

        exterior
            .adding {
                handle
            }
            .subtracting {
                cavity

                if c.hasHole {
                    Cylinder(diameter: c.effectiveHoleDiameter, height: c.bowlHeight)
                        .translated(x: c.holeCenter)
                }

            }
            // Profile the completed footprint, including the brace, inner rim
            // and hanging hole. Later unions can no longer fill in the bevel.
            .cuttingEdgeProfile(.chamfer(depth: ScoopConfiguration.bottomChamfer), on: .bottom,
                                using: { footprint })
            .subtracting {
                engraving
            }
            .withSegmentation(minAngle: 1°, minSize: 0.15)
    }

    @GeometryBuilder3D
    var engraving: any Geometry3D {
        if let label = configuration.label {
            // The bed face becomes the visible upper face in use. Mirror
            // across the handle axis so it reads correctly from that side.
            label
                .flipped(along: .y)
                .extruded(height: configuration.textDepth)
        }
    }

    @GeometryBuilder2D
    var footprint: any Geometry2D {
        let c = configuration

        // Use the actual bed outline: sampling above the bed on a tapered
        // wall would leave a thin, detached ring outside the chamfer cutter.
        Circle(radius: c.outerRadius)
            .adding { handleOutline }
            .subtracting {
                Circle(radius: c.innerRadius)
                if c.hasHole {
                    Circle(diameter: c.effectiveHoleDiameter)
                        .translated(x: c.holeCenter)
                }
            }
    }

    @GeometryBuilder3D
    var handle: any Geometry3D {
        let c = configuration
        @Environment(\.segmentation) var segmentation
        let sweep: Angle = acos((c.braceCenterHeight - c.braceTop) / c.braceRadius)
        let segmentCount = segmentation.segmentCount(arcRadius: c.braceRadius, angle: sweep)
        let roof: [Vector2D] = (0...segmentCount).map { index in
            if index == 0 { return [c.braceEnd, c.gripThickness] }
            let angle = sweep * (Double(index) / Double(segmentCount))
            return [c.braceEnd - c.braceRadius * sin(angle),
                    index == segmentCount ? c.braceTop
                        : c.gripThickness + c.braceRadius * (1 - cos(angle))]
        }

        // Leave the bowl surface at 45° from the tangent point and end inside
        // the wall. Running flat inward could hug the bowl's surface, and the
        // fillet along the straight sides would graze it.
        let inset = min(c.wallThickness, c.braceTop)
        let innerEnd = roof.last!.x - inset

        // Build the brace and grip together in one radial profile, so both
        // sides of their tangent junction share exactly the same roof plane.
        // Sample the circular roof in its final coordinates: transforming a
        // separately tessellated circle can quantize its tangent off that plane.
        // Then round the continuous upper perimeter of the assembled handle.
        Polygon([[innerEnd, 0], [c.handleEnd, 0], [c.handleEnd, c.gripThickness]]
                + roof + [[innerEnd, c.braceTop - inset]])
            .revolved()
            .intersecting {
                handleOutline.extruded(height: c.braceTop)
            }
            .shapingEdges(.fillet(radius: 0.6),
                          matching: .convex.above(.z(c.gripThickness / 2)))
    }

    @GeometryBuilder3D
    var exterior: any Geometry3D {
        let c = configuration

        switch c.bowlShape {
        case .roundBottom:
            // Keep the round variant truly hemispherical; relief stays inside.
            Arc(range: 0°..<90°, radius: c.outerRadius)
                .translated(y: c.outerStraightHeight)
                .adding {
                    Rectangle(x: c.outerRadius, y: c.outerStraightHeight)
                }
                .revolved()
        case .cylindrical:
            // A short vertical rim lets the full 45° bed chamfer finish
            // before the taper begins, without a lip or detached ring.
            Polygon([[0, 0], [c.outerRadius, 0],
                     [c.outerRadius, ScoopConfiguration.bottomChamfer],
                     [c.outerRadius - c.cylindricalSlope * (c.bowlHeight - ScoopConfiguration.bottomChamfer),
                      c.bowlHeight], [0, c.bowlHeight]])
                .revolved()
                .shapingEdges(.fillet(radius: c.cylindricalBottomFillet),
                              matching: .convex.on(.z(c.bowlHeight)))
        }
    }

    @GeometryBuilder3D
    var cavity: any Geometry3D {
        let c = configuration

        switch c.bowlShape {
        case .roundBottom:
            ScoopDome(radius: c.innerRadius)
                .translated(z: c.straightHeight)
                .adding {
                    Cylinder(radius: c.innerRadius, height: c.straightHeight)
                }
        case .cylindrical:
            Polygon([[0, 0], [c.innerRadius, 0],
                     [c.innerRadius, ScoopConfiguration.bottomChamfer],
                     [c.cylindricalBottomRadius, c.cylindricalDepth], [0, c.cylindricalDepth]])
                .revolved()
        }
    }

    @GeometryBuilder2D
    var handleOutline: any Geometry2D {
        let c = configuration

        // Run the straight sides from the bowl axis, so the handle keeps its
        // full width until it disappears into the bowl wall.
        Rectangle(x: c.holeCenter, y: c.effectiveHandleWidth)
            .translated(y: -c.effectiveHandleWidth / 2)
            .adding {
                Circle(diameter: c.effectiveHandleWidth)
                    .translated(x: c.holeCenter)
            }
    }
}

/// An upper half-sphere with 45° relief and a flat bridge at the original top.
/// Keep relief upward both as a cutter and when measured independently.
struct ScoopDome: Geometry3D {
    let radius: Double

    var body: any Geometry3D {
        @Environment(\.operation) var operation

        Sphere(radius: radius)
            .overhangSafe(.bridge)
            .definingNaturalUpDirection(operation == .subtraction ? .positiveZ : .negativeZ)
            .trimmed(along: .z(0))
            .withOverhangAngle(45°)
    }
}
