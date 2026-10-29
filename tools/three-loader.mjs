// Resolve the customizer's import map for its Node regression tests.
export async function resolve(specifier, context, nextResolve) {
    if (specifier === "three") {
        return {
            url: new URL("../Customizer/vendor/three-0.170.0/build/three.module.min.js", import.meta.url).href,
            shortCircuit: true,
        };
    }
    return nextResolve(specifier, context);
}
