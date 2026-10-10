// Batch icon generation through the installed dsh-image-gen plugin's own image
// service — the same module the dsh_image_gen tool calls inside DSH.
//
// Why this exists: a running DSH session resolves the plugin config once at
// load, so if ~/.dsh/dsh-image-gen.json is written afterwards the in-chat tool
// still reports "not configured". Restarting DSH fixes that; this script is the
// non-disruptive path and uses the identical gateway, model and output dir.
//
// Usage: node scripts/icongen/generate-icons.mjs <jobs.json>
//   jobs.json: [{ "name": "...", "prompt": "prompts/x.txt", "out": "out/x.png" }]
//   DSH_IMAGE_PLUGIN overrides the plugin location.
import { existsSync, readFileSync, copyFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';

function resolvePlugin() {
  const candidates = [
    process.env.DSH_IMAGE_PLUGIN,
    path.join(homedir(), '.dsh', 'profiles', 'desktop', 'node_modules',
      '@dsh-external', 'dsh-image-gen', 'lib', 'image-service.js'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  throw new Error('dsh-image-gen plugin not found. Install it in DSH, or set DSH_IMAGE_PLUGIN to its lib/image-service.js.');
}

const plugin = resolvePlugin();
const {
  generateImage,
  DEFAULT_MODEL,
  DEFAULT_IMAGES_PATH,
  DEFAULT_OUTPUT_DIRECTORY,
  DEFAULT_TIMEOUT_MS,
} = await import(plugin);

const configPath = process.env.DSH_IMAGE_CONFIG ?? path.join(homedir(), '.dsh', 'dsh-image-gen.json');
const cfg = JSON.parse(readFileSync(configPath, 'utf8'));

const resolved = {
  baseUrl: cfg.baseUrl,
  model: cfg.model || DEFAULT_MODEL,
  imagesPath: cfg.imagesPath || DEFAULT_IMAGES_PATH,
  apiKey: cfg.apiKey,
  outputDirectory: cfg.outputDirectory || DEFAULT_OUTPUT_DIRECTORY,
  timeoutMs: Number(cfg.timeoutMs) || DEFAULT_TIMEOUT_MS,
};

const [, , jobFile, size = '1024x1024', quality = 'high'] = process.argv;
if (!jobFile) {
  console.error('Usage: node scripts/icongen/generate-icons.mjs <jobs.json> [size] [quality]');
  process.exit(2);
}
const jobs = JSON.parse(readFileSync(jobFile, 'utf8'));

let ok = 0;
for (const job of jobs) {
  const prompt = readFileSync(job.prompt, 'utf8').trim();
  try {
    const result = await generateImage({ prompt, size, quality }, resolved);
    copyFileSync(result.path, job.out);
    ok += 1;
    console.log(JSON.stringify({ ok: true, name: job.name, out: job.out, bytes: result.bytes }));
  } catch (error) {
    const message = String(error && error.message ? error.message : error).slice(0, 300);
    console.log(JSON.stringify({ ok: false, name: job.name, error: message }));
  }
}
console.log(`generated ${ok}/${jobs.length}`);
if (ok !== jobs.length) process.exit(1);

