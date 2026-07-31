// The package is "type": "module", so the CommonJS output needs its own manifest
// saying otherwise — otherwise node reads dist/cjs/*.js as ESM and require() fails.
// Done in four lines instead of adding a bundler and its dependency chain.
import {writeFileSync} from "node:fs";

writeFileSync("dist/cjs/package.json", `${JSON.stringify({type: "commonjs"}, null, 2)}\n`);
console.log("dist/cjs/package.json written (type: commonjs)");
