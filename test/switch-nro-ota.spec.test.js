import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');

function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

function sha256Hex(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

/** JS mirror of src/update/SwitchOta.lua — contract under test. */
function createSwitchOta() {
  const OTA_RE = /^gen1recomp-(\d+\.\d+\.\d+)-switch\.zip$/;
  const CHECK_TIMEOUT_SEC = 6;
  const GAME_NRO_NAME = 'gen1recomp-game.nro';
  const LAUNCHER_NRO_NAME = 'gen1recomp.nro';
  const SAVE_DIR_NAME = 'pokemon-love2d';
  const INSTALL_DIR = 'switch/gen1recomp';

  function parseSemver(s) {
    if (typeof s !== 'string') return null;
    const m = s.match(/^v?(\d+)\.(\d+)\.(\d+)$/);
    if (!m) return null;
    return { major: +m[1], minor: +m[2], patch: +m[3] };
  }

  function compareSemver(a, b) {
    const pa = parseSemver(a);
    const pb = parseSemver(b);
    if (!pa && !pb) return 0;
    if (!pa) return -1;
    if (!pb) return 1;
    for (const f of ['major', 'minor', 'patch']) {
      if (pa[f] < pb[f]) return -1;
      if (pa[f] > pb[f]) return 1;
    }
    return 0;
  }

  function isOtaAssetName(name) {
    return typeof name === 'string' && OTA_RE.test(name);
  }

  function findJsonObjectStart(jsonText, pos) {
    if (!jsonText || pos < 1) return null;
    let depth = 0;
    for (let p = pos; p >= 1; p--) {
      const c = jsonText[p - 1];
      if (c === '}') depth += 1;
      else if (c === '{') {
        if (depth === 0) return p;
        depth -= 1;
      }
    }
    return null;
  }

  function findJsonObjectEnd(jsonText, objectStart) {
    if (!jsonText || objectStart < 1) return null;
    if (jsonText[objectStart - 1] !== '{') return null;
    let depth = 1;
    for (let p = objectStart + 1; p <= jsonText.length; p++) {
      const c = jsonText[p - 1];
      if (c === '{') depth += 1;
      else if (c === '}') {
        depth -= 1;
        if (depth === 0) return p + 1;
      }
    }
    return null;
  }

  function parseRelease(jsonText) {
    if (!jsonText) return { ok: false, reason: 'empty_json' };
    const tagM = jsonText.match(/"tag_name"\s*:\s*"([^"]+)"/);
    if (!tagM) return { ok: false, reason: 'missing_tag' };
    const tag = tagM[1];
    const versionM = tag.match(/^v?(\d+\.\d+\.\d+)$/);
    if (!versionM) return { ok: false, reason: 'bad_tag' };
    const version = versionM[1];

    let cursor = 0;
    while (true) {
      const nameKeyPos = jsonText.indexOf('"name"', cursor);
      if (nameKeyPos === -1) break;
      const tail = jsonText.slice(nameKeyPos);
      const nameM = tail.match(/"name"\s*:\s*"([^"]+)"/);
      const name = nameM?.[1];
      if (name && isOtaAssetName(name)) {
        const assetStart = findJsonObjectStart(jsonText, nameKeyPos + 1);
        const assetEnd = assetStart ? findJsonObjectEnd(jsonText, assetStart) : null;
        if (assetStart && assetEnd && assetEnd > nameKeyPos + 1) {
          const assetBlock = jsonText.slice(assetStart - 1, assetEnd - 1);
          const urlM = assetBlock.match(/"browser_download_url"\s*:\s*"([^"]+)"/);
          const downloadUrl = urlM?.[1];
          if (downloadUrl) {
            return {
              ok: true,
              tag,
              version,
              assetName: name,
              downloadUrl,
            };
          }
        }
      }
      cursor = nameKeyPos + 6;
    }
    return { ok: false, reason: 'missing_ota_asset' };
  }

  function decideUpdate(installed, release) {
    if (!parseSemver(installed)) return { status: 'error', reason: 'bad_installed_version' };
    if (!release?.ok || !release.version) return { status: 'error', reason: 'bad_release' };
    if (compareSemver(release.version, installed) <= 0) {
      return { status: 'uptodate', version: installed };
    }
    return {
      status: 'available',
      version: release.version,
      assetName: release.assetName,
      downloadUrl: release.downloadUrl,
    };
  }

  function parseSums(text) {
    const sums = {};
    if (typeof text !== 'string') return sums;
    for (const line of text.split(/\r?\n/)) {
      const m = line.match(/^([0-9a-fA-F]+)\s+\*?\.?\/?(.*?)\s*$/);
      if (m) sums[m[2]] = m[1].toLowerCase();
    }
    return sums;
  }

  function verifySha256(assetName, actualHex, sums) {
    if (!assetName) return { ok: false, reason: 'bad_asset_name' };
    if (!sums || typeof sums !== 'object') return { ok: false, reason: 'missing_sums' };
    const expected = sums[assetName];
    if (!expected) return { ok: false, reason: 'sum_not_found' };
    if (!actualHex) return { ok: false, reason: 'missing_actual_hash' };
    if (actualHex.toLowerCase() !== expected.toLowerCase()) {
      return { ok: false, reason: 'hash_mismatch' };
    }
    return { ok: true };
  }

  function planAtomicApply(installDir, verifiedTempPath) {
    installDir = installDir || INSTALL_DIR;
    const gameNro = `${installDir}/${GAME_NRO_NAME}`;
    const launcherNro = `${installDir}/${LAUNCHER_NRO_NAME}`;
    const partPath = `${gameNro}.part`;
    const launcherPart = `${launcherNro}.part`;
    return {
      steps: [
        { op: 'copy_to_part', from: verifiedTempPath, to: partPath },
        { op: 'rename', from: partPath, to: gameNro },
        { op: 'copy_to_part', from: 'launcher', to: launcherPart },
        { op: 'rename', from: launcherPart, to: launcherNro },
        { op: 'env_set_next_load', target: gameNro },
      ],
      preserve: [`${installDir}/${SAVE_DIR_NAME}`],
      forbidden: [`delete:${installDir}/${SAVE_DIR_NAME}`, `write_direct:${gameNro}`],
    };
  }

  function offlinePolicy(elapsedSec, events = {}) {
    if (events.userSkip) {
      return { action: 'play_installed', reason: 'user_skip', message: 'update skipped' };
    }
    if (events.apiError || events.networkOk === false) {
      return {
        action: 'play_installed',
        reason: 'offline_or_error',
        message: 'offline or update check failed — play installed version',
      };
    }
    if (typeof elapsedSec === 'number' && elapsedSec >= CHECK_TIMEOUT_SEC) {
      return {
        action: 'play_installed',
        reason: 'timeout',
        message: `update check timed out after ${CHECK_TIMEOUT_SEC}s`,
      };
    }
    return { action: 'keep_checking', reason: 'in_flight' };
  }

  return {
    CHECK_TIMEOUT_SEC,
    GAME_NRO_NAME,
    LAUNCHER_NRO_NAME,
    SAVE_DIR_NAME,
    compareSemver,
    isOtaAssetName,
    parseRelease,
    decideUpdate,
    parseSums,
    verifySha256,
    planAtomicApply,
    offlinePolicy,
  };
}

const M = createSwitchOta();

const GITHUB_UPLOADER =
  '"login":"github-actions[bot]",' +
  '"id":41898282,' +
  '"node_id":"MDM6Qm90NDE4OTgyODI=",' +
  '"avatar_url":"https://avatars.githubusercontent.com/in/15368?v=4",' +
  '"gravatar_id":"",' +
  '"url":"https://api.github.com/users/github-actions%5Bbot%5D",' +
  '"html_url":"https://github.com/apps/github-actions",' +
  '"followers_url":"https://api.github.com/users/github-actions%5Bbot%5D/followers",' +
  '"following_url":"https://api.github.com/users/github-actions%5Bbot%5D/following{/other_user}",' +
  '"gists_url":"https://api.github.com/users/github-actions%5Bbot%5D/gists{/gist_id}",' +
  '"starred_url":"https://api.github.com/users/github-actions%5Bbot%5D/starred{/owner}{/repo}",' +
  '"subscriptions_url":"https://api.github.com/users/github-actions%5Bbot%5D/subscriptions",' +
  '"organizations_url":"https://api.github.com/users/github-actions%5Bbot%5D/orgs",' +
  '"repos_url":"https://api.github.com/users/github-actions%5Bbot%5D/repos",' +
  '"events_url":"https://api.github.com/users/github-actions%5Bbot%5D/events{/privacy}",' +
  '"received_events_url":"https://api.github.com/users/github-actions%5Bbot%5D/received_events",' +
  '"type":"Bot",' +
  '"user_view_type":"public",' +
  '"site_admin":false';

function buildGithubReleaseJson() {
  return (
    '{' +
    '"tag_name":"v0.1.70",' +
    '"name":"0.1.70",' +
    '"assets":[' +
    '{' +
    '"url":"https://api.github.com/repos/bryanthaboi/gen1recomp/releases/assets/502823880",' +
    '"id":502823880,' +
    '"name":"gen1recomp-0.1.70-switch.zip",' +
    '"label":"",' +
    '"uploader":{' +
    GITHUB_UPLOADER +
    '},' +
    '"content_type":"application/zip",' +
    '"state":"uploaded",' +
    '"size":9000573,' +
    '"browser_download_url":"https://github.com/bryanthaboi/gen1recomp/releases/download/v0.1.70/gen1recomp-0.1.70-switch.zip"' +
    '}' +
    ']' +
    '}'
  );
}

const sampleRelease = M.parseRelease(
  JSON.stringify({
    tag_name: 'v1.5.0',
    assets: [
      {
        name: 'gen1recomp-1.5.0-switch.zip',
        browser_download_url: 'https://example/switch.zip',
      },
      { name: 'sha256sums.txt', browser_download_url: 'https://example/sums' },
    ],
  })
);

test('AC-001: Launcher nativo verifica release no GitHub @spec:AC-001', () => {
  assert.equal(M.compareSemver('1.2.0', '1.1.0'), 1);
  assert.equal(M.compareSemver('1.1.0', '1.1.0'), 0);
  assert.equal(M.compareSemver('1.0.0', '1.1.0'), -1);

  assert.equal(sampleRelease.ok, true);
  assert.equal(sampleRelease.version, '1.5.0');
  assert.equal(sampleRelease.assetName, 'gen1recomp-1.5.0-switch.zip');

  assert.equal(M.decideUpdate('1.4.0', sampleRelease).status, 'available');
  assert.equal(M.decideUpdate('1.5.0', sampleRelease).status, 'uptodate');
  assert.equal(M.decideUpdate('1.6.0', sampleRelease).status, 'uptodate');

  const missing = M.parseRelease(JSON.stringify({ tag_name: 'v1.5.0', assets: [] }));
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, 'missing_ota_asset');

  const githubRelease = M.parseRelease(buildGithubReleaseJson());
  assert.equal(githubRelease.ok, true);
  assert.equal(githubRelease.version, '0.1.70');
  assert.equal(githubRelease.assetName, 'gen1recomp-0.1.70-switch.zip');
  assert.equal(
    githubRelease.downloadUrl,
    'https://github.com/bryanthaboi/gen1recomp/releases/download/v0.1.70/gen1recomp-0.1.70-switch.zip'
  );
  assert.equal(M.decideUpdate('0.1.69', githubRelease).status, 'available');
});

test('AC-002: Download com verificação SHA-256 @spec:AC-002', () => {
  const name = 'gen1recomp-1.5.0-switch.zip';
  const payload = Buffer.from('switch-sd-payload');
  const hex = sha256Hex(payload);
  const sums = M.parseSums(`${hex}  ${name}\n`);

  assert.equal(M.verifySha256(name, hex, sums).ok, true);
  assert.equal(M.verifySha256(name, 'deadbeef', sums).reason, 'hash_mismatch');
  // Invisible-error guard: download without a sum MUST NOT verify.
  assert.equal(M.verifySha256(name, hex, {}).ok, false);
  assert.equal(M.verifySha256(name, hex, {}).reason, 'sum_not_found');
  assert.equal(M.verifySha256(name, '', sums).reason, 'missing_actual_hash');
});

test('AC-003: Aplicação atômica e handoff para o jogo @spec:AC-003', () => {
  const plan = M.planAtomicApply('switch/gen1recomp', '/tmp/verified.zip');
  assert.ok(plan.steps.some((s) => s.op === 'copy_to_part'));
  assert.ok(plan.steps.some((s) => s.op === 'rename'));
  assert.ok(plan.steps.some((s) => s.op === 'env_set_next_load'));
  assert.ok(plan.steps.filter((s) => s.op === 'rename').length >= 2, 'renames game + launcher');
  assert.ok(plan.preserve.some((p) => p.endsWith('pokemon-love2d')));
  assert.ok(plan.forbidden.some((f) => f.startsWith('delete:') && f.includes('pokemon-love2d')));
  assert.ok(plan.forbidden.some((f) => f.startsWith('write_direct:')));
  const renameGame = plan.steps.find((s) => s.op === 'rename' && s.to.endsWith('gen1recomp-game.nro'));
  assert.ok(renameGame);
  assert.ok(renameGame.from.endsWith('.part'));
  const renameLauncher = plan.steps.find((s) => s.op === 'rename' && s.to.endsWith('gen1recomp.nro'));
  assert.ok(renameLauncher, 'launcher NRO replaced so NACP version stays in sync');
});

test('AC-004: Offline ou falha de rede não trava o jogo @spec:AC-004', () => {
  assert.equal(M.CHECK_TIMEOUT_SEC, 6);
  assert.equal(M.offlinePolicy(1, { userSkip: true }).action, 'play_installed');
  assert.equal(M.offlinePolicy(1, { networkOk: false }).action, 'play_installed');
  assert.equal(M.offlinePolicy(6, { networkOk: true }).action, 'play_installed');
  assert.equal(M.offlinePolicy(6, { networkOk: true }).reason, 'timeout');
  assert.equal(M.offlinePolicy(2, { networkOk: true }).action, 'keep_checking');
});

test('AC-005: Documentação Switch descreve o launcher OTA @spec:AC-005', () => {
  const install = read('docs/switch-install.md');
  const build = read('docs/switch-build.md');
  const updater = read('docs/updater.md');

  for (const [name, text] of [
    ['switch-install', install],
    ['switch-build', build],
    ['updater', updater],
  ]) {
    assert.match(text, /native OTA launcher|launcher nativo/i, `${name} mentions native OTA launcher`);
  }

  assert.match(install, /manual|zip|microSD/i, 'manual zip fallback still documented');
  assert.match(install, /gen1recomp-\*-switch\.zip|switch\.zip/i, 'unified Switch zip documented');
  assert.doesNotMatch(install, /switch-ota\.zip/, 'legacy separate OTA zip must not be documented');
  assert.match(install, /Sphaira|forwarder/i, 'Sphaira shortcut version note documented');
  assert.doesNotMatch(
    install,
    /Switch OTA uses `src\/update\/Check\.lua`/i,
    'must not claim Switch OTA uses LÖVE Check.lua'
  );
  assert.match(updater, /Nintendo Switch/i);
  assert.match(updater, /networkValidated|disabled|desligado|off/i);
});

test('AC-006: LOVE no NX continua sem rede de updater @spec:AC-006', () => {
  const platform = read('src/core/Platform.lua');
  assert.match(
    platform,
    /networkValidated\s*=\s*not nx/,
    'Platform.networkValidated must stay false on NX'
  );
  assert.doesNotMatch(platform, /networkValidated\s*=\s*true/);

  const boot = read('src/update/Boot.lua');
  assert.match(boot, /networkValidated/, 'Boot still gates on networkValidated');

  assert.ok(read('src/update/Check.lua').length > 0);
  assert.ok(read('src/update/check_worker.lua').length > 0);
  assert.ok(read('src/core/HostShell.lua').length > 0);
  assert.match(read('src/import/RomImporter.lua'), /updaterAllowed|networkValidated|Check/);
  assert.ok(read('src/import/LauncherView.lua').length > 0);

  const switchOta = read('src/update/SwitchOta.lua');
  assert.doesNotMatch(switchOta, /networkValidated\s*=\s*true/);
  assert.match(switchOta, /never runs this path|remains gated off on NX/i);
});

test('AC-007: Funções puras do protocolo OTA têm testes host-side @spec:AC-007', () => {
  assert.ok(M.isOtaAssetName('gen1recomp-1.2.3-switch.zip'));
  assert.equal(M.isOtaAssetName('gen1recomp-1.2.3-switch-ota.zip'), false);
  assert.equal(M.isOtaAssetName('gen1recomp-1.2.3.love'), false);
  assert.equal(M.compareSemver('2.0.0', '1.9.9'), 1);
  assert.equal(M.compareSemver('1.0.0', '1.0.0'), 0);
  assert.equal(M.compareSemver('0.9.0', '1.0.0'), -1);

  const rel = M.parseRelease(
    JSON.stringify({
      tag_name: 'v9.9.9',
      assets: [
        {
          name: 'gen1recomp-9.9.9-switch.zip',
          browser_download_url: 'https://example/x',
        },
      ],
    })
  );
  assert.equal(rel.version, '9.9.9');

  const sums = M.parseSums('deadbeef  unexpected-name.zip\n');
  assert.equal(
    M.verifySha256('gen1recomp-9.9.9-switch.zip', 'deadbeef', sums).ok,
    false,
    'unexpected filename in sums must not verify OTA asset'
  );
  assert.equal(M.verifySha256('gen1recomp-9.9.9-switch.zip', 'anything', {}).ok, false);

  const lua = read('src/update/SwitchOta.lua');
  assert.ok(fs.existsSync(path.join(root, 'src/update/SwitchOta.lua')));
  for (const fn of [
    'compareSemver',
    'parseRelease',
    'decideUpdate',
    'parseSums',
    'verifySha256',
    'planAtomicApply',
    'offlinePolicy',
  ]) {
    assert.match(lua, new RegExp(`function SwitchOta\\.${fn}`), `Lua exports ${fn}`);
  }
  assert.match(lua, /CHECK_TIMEOUT_SEC\s*=\s*6/);
  assert.match(lua, /switch%.zip|%-switch%.zip/);
  assert.doesNotMatch(lua, /switch%-ota%.zip|switch-ota\.zip/);
});

test('AC-008: Gates de regressão anti-“erro invisível” @spec:AC-008', () => {
  const platform = read('src/core/Platform.lua');
  assert.match(platform, /networkValidated\s*=\s*not nx\s+and\s+not uwp/);

  for (const rel of ['docs/switch-install.md', 'docs/switch-build.md', 'docs/updater.md']) {
    const text = read(rel);
    assert.match(text, /native OTA launcher|launcher nativo/i, rel);
    assert.match(
      text,
      /LÖVE self-updater|LOVE self-updater|self-updater LÖVE|updater LÖVE|Check\.lua/i,
      `${rel} contrasts with LÖVE updater`
    );
  }

  const manifest = read('scripts/switch/ota_launcher.manifest');
  assert.match(manifest, /^OTA_ENABLED=1$/m);
  assert.match(manifest, /ENTRY_NRO=switch\/gen1recomp\/gen1recomp\.nro/);
  assert.match(manifest, /GAME_NRO=switch\/gen1recomp\/gen1recomp-game\.nro/);
  assert.match(manifest, /OTA_ASSET_GLOB=gen1recomp-\*-switch\.zip/);
  assert.doesNotMatch(manifest, /switch-ota\.zip/);
  assert.match(manifest, /REQUIRE_SHA256SUMS=1/);
});

test('AC-009: Protocolo C host-testável espelha SwitchOta.lua @spec:AC-009', () => {
  const proto = read('ports/switch/ota-launcher/src/ota_protocol.c');
  const header = read('ports/switch/ota-launcher/include/ota_protocol.h');
  assert.match(header, /OTA_CHECK_TIMEOUT_SEC\s+6/);
  assert.match(header, /ota_compare_semver/);
  assert.match(header, /ota_parse_release/);
  assert.match(header, /ota_verify_sha256/);
  assert.match(header, /ota_plan_atomic_apply/);
  assert.match(header, /ota_offline_policy/);
  assert.match(proto, /sum_not_found/);
  assert.match(proto, /env_set_next_load/);
  assert.match(header, /pokemon-love2d/);
  assert.match(proto, /OTA_SAVE_DIR_NAME/);

  const lua = read('src/update/SwitchOta.lua');
  assert.match(lua, /CHECK_TIMEOUT_SEC\s*=\s*6/);

  // Compile + run C host tests (gcc)
  const r = spawnSync(
    'make',
    ['-C', path.join(root, 'ports/switch/ota-launcher'), 'host-test'],
    { encoding: 'utf8' }
  );
  assert.equal(r.status, 0, `host-test failed:\n${r.stdout}\n${r.stderr}`);
  assert.match(r.stdout, /all ota_protocol host tests passed/);
});

test('AC-010: Fonte do launcher e Makefile DEVKITPRO existem @spec:AC-010', () => {
  for (const rel of [
    'ports/switch/ota-launcher/Makefile',
    'ports/switch/ota-launcher/README.md',
    'ports/switch/ota-launcher/src/main.c',
    'ports/switch/ota-launcher/src/ota_net.c',
    'ports/switch/ota-launcher/src/ota_fs.c',
    'scripts/switch/build_ota_launcher.sh',
    'docs/switch-build.md',
  ]) {
    assert.ok(fs.existsSync(path.join(root, rel)), `missing ${rel}`);
  }
  const main = read('ports/switch/ota-launcher/src/main.c');
  assert.match(main, /envSetNextLoad|ota_fs_handoff_to_game/);
  assert.match(main, /gen1recomp-game\.nro|OTA_GAME_NRO_NAME/);
  assert.match(main, /Quiet by default|stays quiet|LÖVE self-updater stays off|self-updater stays off/i);
  assert.match(main, /ota_ui_prompt_update|ota_ui_show_progress/);
  assert.match(main, /ota_ui_alert_error/);
  assert.match(main, /Step 1\/3: Downloading/);
  assert.doesNotMatch(main, /\u2026/, 'OTA UI strings must be ASCII (no Unicode ellipsis)');
  assert.doesNotMatch(main, /ota_ui_alert\([^)]*Install failed/, 'generic install alert removed');
  assert.doesNotMatch(main, /consoleInit/, 'no terminal console UI');
  assert.ok(fs.existsSync(path.join(root, 'ports/switch/ota-launcher/src/ota_ui.c')));
  const otaUi = read('ports/switch/ota-launcher/src/ota_ui.c');
  assert.match(otaUi, /COL_RAIL_R|rail|FFD600|255,\s*214/);
  assert.match(otaUi, /logo\.rgba/);
  assert.doesNotMatch(otaUi, /stb_image/);
  assert.ok(
    fs.existsSync(path.join(root, 'ports/switch/assets/logo.rgba')),
    'pre-baked OTA logo asset'
  );
  assert.ok(
    fs.existsSync(path.join(root, 'scripts/switch/bake_ota_logo.py')),
    'logo bake script for regenerating logo.rgba'
  );
  assert.match(otaUi, /ota_ui_sanitize_ascii/);
  assert.match(otaUi, /draw_text_wrapped_centered/);
  assert.match(otaUi, /ota_ui_alert_error/);
  assert.match(read('ports/switch/ota-launcher/src/ota_net.c'), /ota_net_init/);
  assert.match(read('ports/switch/ota-launcher/src/main.c'), /ota_net_init/);
  assert.match(read('ports/switch/ota-launcher/src/ota_net.c'), /CURLOPT_SSL_VERIFYPEER,\s*1L/);
  assert.match(read('ports/switch/ota-launcher/src/ota_net.c'), /romfs:\/cacert\.pem/);
  assert.doesNotMatch(read('ports/switch/ota-launcher/src/ota_net.c'), /CURLOPT_SSL_VERIFYPEER,\s*0L/);
  assert.match(read('ports/switch/ota-launcher/Makefile'), /^ROMFS\s*:=/m);
  assert.match(read('ports/switch/ota-launcher/Makefile'), /cacert\.pem/);
  assert.match(read('ports/switch/ota-launcher/Makefile'), /logo\.rgba/);

  const mk = read('ports/switch/ota-launcher/Makefile');
  assert.match(mk, /libnx\/switch_rules|DEVKITPRO/);
  assert.match(mk, /-lcurl/);
  assert.match(mk, /-lzzip/);
  assert.match(mk, /ports\/switch\/assets\/icon\.jpg|assets\/icon\.jpg/, 'uses project Switch icon');

  assert.ok(fs.existsSync(path.join(root, 'ports/switch/ota-launcher/src/ota_unzip.c')));
  assert.match(read('ports/switch/ota-launcher/src/ota_unzip.c'), /zzip\/zzip\.h/);
  assert.match(read('ports/switch/ota-launcher/src/main.c'), /ota_unzip_extract_file/);
  assert.match(read('ports/switch/ota-launcher/src/main.c'), /GAME_MEMBER_IN_ZIP|switch\/gen1recomp\//);
  assert.match(read('ports/switch/ota-launcher/src/main.c'), /LAUNCHER_MEMBER_IN_ZIP|ota_fs_stage_launcher_bootstrap/);
  assert.match(read('ports/switch/ota-launcher/src/main.c'), /ota_fs_stage_launcher_bootstrap\([\s\S]*\) != 0/);
  assert.match(read('ports/switch/ota-launcher/src/main.c'), /return 2.*bootstrap|bootstrap.*return 2/i);
  assert.match(read('ports/switch/ota-launcher/src/ota_fs.c'), /ota_fs_atomic_replace_nro/);
  assert.match(read('ports/switch/ota-launcher/src/ota_fs.c'), /remove\(dest\)/);
  assert.doesNotMatch(read('ports/switch/ota-launcher/src/ota_fs.c'), /#ifdef _WIN32[\s\S]*remove\(dest\)/);
  assert.doesNotMatch(read('scripts/switch/install_devkitpro_deps.sh'), /switch-minizip/);
  assert.match(read('scripts/switch/install_devkitpro_deps.sh'), /switch-zziplib/);
  assert.match(read('scripts/switch/install_devkitpro_deps.sh'), /switch-dev/);

  const buildDoc = read('docs/switch-build.md');
  assert.match(buildDoc, /ports\/switch\/ota-launcher|build_ota_launcher/);
  assert.match(buildDoc, /native packages.*or.*Docker|native or Docker/i);
  assert.match(buildDoc, /--fused|install_devkitpro_deps/);
  assert.match(buildDoc, /Requires DEVKITPRO|DEVKITPRO is[\s\S]*required/i);
  assert.doesNotMatch(buildDoc, /switch-ota\.zip/);
  assert.doesNotMatch(buildDoc, /--ota\b/);

  const readme = read('ports/switch/ota-launcher/README.md');
  assert.match(readme, /DEVKITPRO|devkitPro/i);
  assert.match(readme, /Docker|devkita64/i);
  assert.match(readme, /Quiet|quiet|silen/i);
});

test('AC-011: Empacotamento dual-NRO e selftest @spec:AC-011', () => {
  const pack = read('scripts/switch/pack_sd_zip.sh');
  assert.match(pack, /LAUNCHER_NRO/);
  assert.match(pack, /gen1recomp-game\.nro/);
  assert.match(pack, /version\.txt/);

  assert.equal(
    fs.existsSync(path.join(root, 'scripts/switch/pack_ota_zip.sh')),
    false,
    'separate pack_ota_zip.sh removed — unified *-switch.zip'
  );

  const buildSwitch = read('scripts/build_switch.sh');
  assert.doesNotMatch(buildSwitch, /--ota\b/);
  assert.doesNotMatch(buildSwitch, /pack_ota_zip\.sh/);
  assert.match(buildSwitch, /build_ota_launcher\.sh/);
  assert.match(buildSwitch, /dual-NRO SD zip|OTA download asset/i);

  const buildOtaLauncher = read('scripts/switch/build_ota_launcher.sh');
  assert.match(buildOtaLauncher, /ota_launcher_deps_ready/);
  assert.match(buildOtaLauncher, /fail_missing_devkitpro/);
  assert.match(buildSwitch, /preflight_fused_build/);

  const selftest = read('scripts/switch/selftest_build_switch.sh');
  assert.match(selftest, /dual-NRO|gen1recomp-game\.nro/);
  assert.match(selftest, /ota_launcher\.manifest/);
  assert.match(selftest, /OTA uses the same SD zip|same SD zip|legacy OTA-only/i);
  assert.match(selftest, /ota_ui|framebuffer|no prompt when up to date/i);

  const manifest = read('scripts/switch/ota_launcher.manifest');
  assert.match(manifest, /^OTA_ENABLED=1$/m);
  assert.match(manifest, /OTA_ASSET_GLOB=gen1recomp-\*-switch\.zip/);

  // Run the dual-NRO portion via full offline selftest (includes legacy + OTA)
  const r = spawnSync('bash', [path.join(root, 'scripts/switch/selftest_build_switch.sh')], {
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, `selftest failed:\n${r.stdout}\n${r.stderr}`);
  assert.match(r.stdout, /dual-NRO OTA layout/);
});
