import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import * as THREE from "three";
import { readPreview } from "../Customizer/preview.js";
import { createSharpEdges } from "../Customizer/edges.js";
import { ModelSession } from "../Customizer/runner.js";

// A real pair of almost coplanar scoop triangles. Float32 conversion changes
// their shared edge into a >30° crease, reproducing the unwanted vertical lines.
const fixture = JSON.parse(await readFile(new URL("../Tests/Customizer/smooth-sliver.json", import.meta.url)));
const indices = new Uint32Array(fixture.indices.flat());
const materials = fixture.indices.map(() => new THREE.MeshStandardMaterial({ color: "white" }));
assert.equal(createSharpEdges(new Float64Array(fixture.positions), indices, materials), null);
const roundedEdges = createSharpEdges(new Float32Array(fixture.positions), indices, materials);
assert.ok(roundedEdges?.geometry.attributes.position.count > 0, "Fixture must reproduce the Float32 artifact");

function preview(version, positions, triangles, name) {
    const chunks = [];
    let length = 0;
    const append = bytes => { chunks.push(bytes); length += bytes.length; };
    const u32 = n => { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0); append(b); };
    const pad = n => { while (length % n) append(Buffer.alloc(1)); };
    const string = s => { const b = Buffer.from(s); u32(b.length); append(b); pad(4); };
    append(Buffer.from("CDVP")); u32(version); u32(1);
    string("mesh"); string(name); string("solid");
    u32(positions.length / 3);
    if (version === 2) pad(8);
    for (const value of positions) {
        const bytes = Buffer.alloc(version === 2 ? 8 : 4);
        if (version === 2) bytes.writeDoubleLE(value); else bytes.writeFloatLE(value);
        append(bytes);
    }
    u32(triangles.length / 3);
    for (const index of triangles) u32(index);
    for (let i = 0; i < triangles.length / 3; i++) u32(-1);
    u32(-1); u32(0);
    const bytes = Buffer.concat(chunks);
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

for (const name of ["mesh", "abcdef"]) {
    // Exercise both padded and already-aligned Float64 arrays.
    const group = readPreview(preview(2, fixture.positions, indices, name), "#ffffff");
    assert.equal(group.getObjectByName("sharp-edges"), undefined, "Smooth sliver must not acquire an outline");
    assert.ok(group.children[0].geometry.attributes.position.array instanceof Float32Array,
        "Only the GPU vertex buffer should be rounded to Float32");
}

// Preserve real creases and compatibility with existing version-1 previews.
const corner = [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1];
const cornerFaces = [0, 1, 2, 1, 0, 3];
for (const version of [1, 2]) {
    const group = readPreview(preview(version, corner, cornerFaces, "corner"), "#ffffff");
    assert.equal(group.getObjectByName("sharp-edges")?.geometry.attributes.position.count, 2);
}

// Exercise the actual Swift -> WebAssembly -> preview decoder path too.
const root = new URL("../Customizer/", import.meta.url);
const paths = JSON.parse(await readFile(new URL("resources.json", root)));
const resources = await Promise.all(paths.map(async path => [path,
    new Uint8Array(await readFile(new URL("resources/" + path, root)))]));
const wasm = await WebAssembly.compile(await readFile(new URL("model.wasm", root)));
const session = new ModelSession(wasm, resources);
const { catalog } = await session.listParameters();
assert.ok(catalog.models.every(model => model.parameters.every(parameter => parameter.label !== "Surface quality")));
const built = await session.build("scoop", {});
assert.equal(built.exitCode, 0);
const bytes = built.data;
const data = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
assert.equal(new DataView(data).getUint32(4, true), 2, "Actual model must send full-precision preview coordinates");
const actual = readPreview(data, "#ffffff");
assert.ok(actual.getObjectByName("sharp-edges")?.geometry.attributes.position.count > 0,
    "Real scoop outlines must remain visible");

console.log("Customizer edge regressions passed: smooth slivers, real creases, alignment, legacy previews, GPU buffers, actual WASM preview, no quality control.");
