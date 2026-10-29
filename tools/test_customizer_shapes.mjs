import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { ModelSession } from '../Customizer/runner.js';

const root = new URL('../Customizer/', import.meta.url);
const paths = JSON.parse(await readFile(new URL('resources.json', root)));
const resources = await Promise.all(paths.map(async path => [path,
    new Uint8Array(await readFile(new URL('resources/' + path, root)))]));
const session = new ModelSession(await WebAssembly.compile(await readFile(new URL('model.wasm', root))), resources);
const model = (await session.listParameters()).catalog.models.find(model => model.name === 'scoop');
const parameter = label => model.parameters.find(parameter => parameter.label === label);
const shape = parameter('Bowl shape');
assert.equal(shape.default, 'roundBottom');
assert.deepEqual(shape.options, [
    { label: 'Round bottom', value: 'roundBottom' },
    { label: 'Cylindrical (tapered)', value: 'cylindrical' },
]);
assert.equal(parameter('Lettering'), undefined);
assert.equal(parameter('Handle text').default, '');
const labels = model.parameters.map(parameter => parameter.label);
assert.ok(!labels.includes('Hanging hole'));
assert.equal(parameter('Hole diameter').default, 0);
assert.equal(parameter('Hole diameter').minimum, 0);

const round = await session.build('scoop', {});
assert.equal(round.exitCode, 0);
assert.equal(round.metadata.description, 'Bowl height: 30.7 mm · Bridge span: 18.2 mm.');

const cylindrical = { [shape.key]: 'cylindrical' };
const withoutHole = await session.build('scoop', { ...cylindrical,
    [parameter('Hole diameter').key]: 0 });
assert.equal(withoutHole.exitCode, 0);
assert.ok(withoutHole.parameterList.some(parameter => parameter.label === 'Hole diameter'));
const preview = await session.build('scoop', cylindrical);
assert.equal(preview.exitCode, 0);
assert.equal(preview.stackOverflow, false);
assert.ok(preview.data.length > 1000);
assert.ok(!preview.metadata.description.includes('Bowl shape'));
assert.ok(!preview.metadata.description.includes('Cylindrical'));
const span = Number(preview.metadata.description.match(/Bridge span: ([0-9.]+)/)[1]);
assert.ok(span > 40 && span < 44, 'Cylinder must report the full flat-bottom bridge span');
const exported = await session.export('scoop', cylindrical);
assert.equal(exported.exitCode, 0);
await writeFile(new URL('../.build/wasm-cylindrical.3mf', import.meta.url), exported.data);
const withHole = await session.export('scoop', { ...cylindrical, [parameter('Hole diameter').key]: 6 });
assert.equal(withHole.exitCode, 0);
assert.ok(!Buffer.from(withHole.data).equals(Buffer.from(exported.data)),
    'A positive hole diameter must change the exported geometry');
await writeFile(new URL('../.build/wasm-cylindrical-with-hole.3mf', import.meta.url), withHole.data);

const small = { ...cylindrical, [parameter('Capacity').key]: 5,
    [parameter('Bowl inner diameter').key]: 90, [parameter('Wall thickness').key]: 4,
    [parameter('Handle width').key]: 30, [parameter('Handle text').key]: '5 ml' };
const smallPreview = await session.build('scoop', small);
assert.equal(smallPreview.exitCode, 0);
assert.equal(smallPreview.stackOverflow, false);
const diameter = Number(smallPreview.metadata.description.match(/Inner diameter reduced to ([0-9.]+)/)[1]);
assert.ok(diameter > 25 && diameter < 30, 'Cylinder diameter must adjust to preserve a 5 ml capacity');
const widthControl = smallPreview.parameterList.find(parameter => parameter.label === 'Handle width');
assert.ok(!smallPreview.metadata.description.includes('Handle width'));
const height = smallPreview.parameterList.find(parameter => parameter.label === 'Text height');
assert.equal(height.default, 6);
const depth = smallPreview.parameterList.find(parameter => parameter.label === 'Engraving depth');
assert.ok(!depth.description, 'Unchanged text height must not be repeated');
const shown = smallPreview.parameterList.map(parameter => parameter.label);
assert.ok(!shown.includes('Hanging hole'));
assert.ok(shown.includes('Hole diameter'));
const engraved = await session.export('scoop', small);
assert.equal(engraved.exitCode, 0);
await writeFile(new URL('../.build/wasm-cylindrical-small.3mf', import.meta.url), engraved.data);
const deeper = await session.export('scoop', { ...small, [depth.key]: 1.2 });
assert.equal(deeper.exitCode, 0);
assert.ok(!Buffer.from(deeper.data).equals(Buffer.from(engraved.data)),
    'Changing engraving depth must change exported geometry');

const longPreview = await session.build('scoop', { ...small,
    [parameter('Handle length').key]: 40,
    [parameter('Handle text').key]: 'A long label that must shrink to fit' });
assert.equal(longPreview.exitCode, 0);
assert.ok(longPreview.parameterList.find(parameter => parameter.label === 'Engraving depth')
    .description.includes('Text height reduced to'));

// Changing shape must also recalculate controls derived from bowl diameter.
const smallRound = await session.build('scoop', { ...small, [shape.key]: 'roundBottom' });
assert.equal(smallRound.exitCode, 0);
const roundWidth = smallRound.parameterList.find(parameter => parameter.label === 'Handle width');
assert.ok(roundWidth.maximum < widthControl.maximum);
assert.ok(smallRound.metadata.description.includes('Inner diameter reduced to'));
console.log('Customizer checks passed: zero-default hole diameter without switch, hole preview/export, bowl choices, bridge span, conditional adjustments, handle width, engraving and fitting feedback.');
