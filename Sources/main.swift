import Cadova

await Model("scoop") {
    @Parameter("Capacity", in: 5...250, step: 1, unit: "ml",
               description: "Level capacity, measured to the rim")
    var capacity = 30.0

    @Parameter("Bowl shape")
    var bowlShape = BowlShape.roundBottom

    @Parameter("Proportions", in: 0.5...2, step: 0.05,
               description: "Inner depth ÷ diameter; higher is deeper.")
    var depthRatio = 0.6

    @Parameter("Wall thickness", in: 1.2...4, step: 0.1, unit: "mm",
               description: "Includes the base.")
    var wallThickness = 2.0

    @Parameter("Handle length", in: 40...120, step: 1, unit: "mm",
               description: "Length beyond the bowl.")
    var handleLength = 80.0

    let maximumHandleWidth = min(30, ScoopConfiguration(
        bowlShape: bowlShape, capacity: capacity, depthRatio: depthRatio, wallThickness: wallThickness
    ).outerRadius * 2)
    @Parameter("Handle width", in: 12...maximumHandleWidth, step: 1, unit: "mm",
               description: "Limited to bowl width.")
    var handleWidth = 18.0

    @Parameter("Handle thickness", in: 3...8, step: 0.5, unit: "mm",
               description: "Limited to available bowl depth.")
    var handleThickness = 5.0

    var configuration = ScoopConfiguration(
        bowlShape: bowlShape, capacity: capacity, depthRatio: depthRatio, wallThickness: wallThickness,
        handleLength: handleLength, handleWidth: handleWidth, handleThickness: handleThickness
    )

    @Parameter("Hole diameter", in: 0...configuration.maximumHoleDiameter, step: 0.5, unit: "mm",
               description: "0 for none. Limited by handle width.")
    var holeDiameter = 0.0
    configuration.holeDiameter = holeDiameter

    @Parameter("Handle text", description: "Engraved; blank for none.")
    var text = ""
    configuration.text = text

    if configuration.hasText {
        @Parameter("Text size", in: HandleLabel.minimumFontSize...20, step: 0.5, unit: "mm",
                   description: "Font size; shrinks to fit.")
        var textSize = 7.0
        configuration.textSize = textSize

        @Parameter("Engraving depth", in: 0.3...1.2, step: 0.1, unit: "mm")
        var textDepth = 0.6
        configuration.textDepth = textDepth
    }

    Metadata(title: "Customizable Scoop", description: configuration.summary)
    Scoop(configuration: configuration)
}

if CommandLine.arguments.contains("--examples") {
    await Model("scoop-with-hole") {
        Scoop(configuration: ScoopConfiguration(holeDiameter: 6, text: "30 ml"))
    }
    await Model("scoop-cylindrical") {
        Scoop(configuration: ScoopConfiguration(bowlShape: .cylindrical,
                                               text: "30 ml"))
    }
    await Model("scoop-cylindrical-5ml") {
        Scoop(configuration: ScoopConfiguration(bowlShape: .cylindrical, capacity: 5, depthRatio: 0.5,
                                               wallThickness: 1.2, handleLength: 40, handleWidth: 30,
                                               handleThickness: 8, text: "5 ml"))
    }
    await Model("scoop-engraved") {
        Scoop(configuration: ScoopConfiguration(text: "30 ml"))
    }
    await Model("scoop-cylindrical-wide-handle") {
        Scoop(configuration: ScoopConfiguration(bowlShape: .cylindrical, capacity: 5, depthRatio: 0.5,
                                               wallThickness: 4, handleWidth: 30, text: "5 ml"))
    }
    await Model("scoop-5ml") {
        Scoop(configuration: ScoopConfiguration(capacity: 5,
                                               handleLength: 50, handleWidth: 14,
                                               text: "5 ml"))
    }
    await Model("scoop-100ml") {
        Scoop(configuration: ScoopConfiguration(capacity: 100,
                                               handleLength: 100, handleWidth: 22,
                                               handleThickness: 6,
                                               text: "100 ml"))
    }
}
