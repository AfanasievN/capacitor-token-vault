import {spawnSync} from "node:child_process";
import {existsSync, readFileSync} from "node:fs";
import {resolve} from "node:path";
import {pathToFileURL} from "node:url";

const packageJson = JSON.parse(readFileSync(resolve("package.json"), "utf8"));
const packageExport = packageJson.exports?.["."];
const requiredFiles = [
  packageJson.main,
  packageJson.types,
  packageExport?.import,
  packageExport?.require,
  "ios/Sources/TokenVaultPlugin/TokenVault.swift",
  "ios/Sources/TokenVaultPlugin/TokenVaultPlugin.swift",
  "android/src/main/java/com/afanasievn/tokenvault/TokenVault.kt",
  "android/src/main/java/com/afanasievn/tokenvault/TokenVaultPlugin.kt",
  "CapacitorTokenVault.podspec",
  "Package.swift",
  "README.md",
  "LICENSE",
];

const errors = [];

for (const file of requiredFiles) {
  if (typeof file !== "string" || !existsSync(resolve(file))) {
    errors.push(`missing required package file: ${String(file)}`);
  }
}

if (packageJson.private === true) errors.push("package.json must not set private=true");
if (Object.keys(packageJson.dependencies ?? {}).length > 0) {
  errors.push("runtime dependencies must remain empty");
}

if (errors.length === 0) {
  const esmUrl = JSON.stringify(pathToFileURL(resolve(packageExport.import)).href);
  const cjsPath = JSON.stringify(resolve(packageExport.require));
  const checks = [
    ["ESM", ["--input-type=module", "--eval", `const m = await import(${esmUrl}); if (!m.TokenVault) process.exit(1);`]],
    ["CommonJS", ["--eval", `const m = require(${cjsPath}); if (!m.TokenVault) process.exit(1);`]],
  ];
  for (const [label, args] of checks) {
    const result = spawnSync(process.execPath, args, {encoding: "utf8"});
    if (result.status !== 0) {
      errors.push(`${label} entrypoint does not load and export TokenVault: ${result.stderr.trim()}`);
    }
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exitCode = 1;
} else {
  console.log(`Verified ${packageJson.name}@${packageJson.version}: ESM, CommonJS, and native sources are present.`);
}
