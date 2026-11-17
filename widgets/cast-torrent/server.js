#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const http = require("http");
const os = require("os");
const torrentStream = require("torrent-stream");

const VIDEO_EXTS = new Set([".mp4", ".m4v", ".mkv", ".webm", ".avi", ".mov", ".ts"]);
const AUDIO_EXTS = new Set([".mp3", ".flac", ".wav", ".ogg", ".m4a", ".aac", ".opus"]);
const SUB_EXTS = new Set([".srt", ".vtt", ".ass", ".ssa"]);

const MIME_MAP = {
  ".mp4": "video/mp4",
  ".m4v": "video/mp4",
  ".webm": "video/webm",
  ".mkv": "video/x-matroska",
  ".avi": "video/x-msvideo",
  ".mov": "video/quicktime",
  ".ts": "video/mp2t",
  ".mp3": "audio/mpeg",
  ".flac": "audio/flac",
  ".wav": "audio/wav",
  ".ogg": "audio/ogg",
  ".m4a": "audio/mp4",
  ".aac": "audio/aac",
  ".opus": "audio/opus",
};

function parseArgs(argv) {
  const args = { source: null, port: 0, tmp: null, fileIndex: null };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--port" && i + 1 < argv.length) {
      args.port = parseInt(argv[++i], 10) || 0;
    } else if (a === "--tmp" && i + 1 < argv.length) {
      args.tmp = argv[++i];
    } else if (a === "--file" && i + 1 < argv.length) {
      args.fileIndex = parseInt(argv[++i], 10);
    } else if (!args.source) {
      args.source = a;
    }
  }
  return args;
}

function cleanupStaleDirs(baseTmp) {
  try {
    for (const entry of fs.readdirSync(baseTmp)) {
      const m = /^ct-(\d+)-/.exec(entry);
      if (!m) continue;
      const pid = parseInt(m[1], 10);
      let alive = true;
      try {
        process.kill(pid, 0);
      } catch (e) {
        if (e.code === "ESRCH") alive = false;
      }
      if (!alive) {
        fs.rmSync(path.join(baseTmp, entry), { recursive: true, force: true });
      }
    }
  } catch (_) {}
}

async function resolveTorrentInput(source) {
  if (source.startsWith("magnet:")) {
    return source;
  }
  if (/^https?:\/\//i.test(source)) {
    const res = await fetch(source);
    if (!res.ok) {
      throw new Error(`HTTP ${res.status} al descargar .torrent`);
    }
    const ab = await res.arrayBuffer();
    return Buffer.from(ab);
  }
  const abs = path.resolve(source);
  if (!fs.existsSync(abs)) {
    throw new Error(`No existe el archivo torrent: ${abs}`);
  }
  return fs.readFileSync(abs);
}

function pickTargetFile(files, fileIndex) {
  if (fileIndex !== null && !Number.isNaN(fileIndex) && files[fileIndex]) {
    return files[fileIndex];
  }
  const videos = files.filter((f) => VIDEO_EXTS.has(path.extname(f.name).toLowerCase()));
  if (videos.length > 0) {
    return videos.reduce((a, b) => (b.length > a.length ? b : a));
  }
  const audios = files.filter((f) => AUDIO_EXTS.has(path.extname(f.name).toLowerCase()));
  if (audios.length > 0) {
    return audios.reduce((a, b) => (b.length > a.length ? b : a));
  }
  return files.reduce((a, b) => (b.length > a.length ? b : a));
}

function downloadSubFile(file, destDir) {
  return new Promise((resolve) => {
    try {
      file.select();
      const outPath = path.join(destDir, path.basename(file.name));
      const ws = fs.createWriteStream(outPath);
      const rs = file.createReadStream();
      const timer = setTimeout(() => {
        try { rs.destroy(); } catch (_) {}
        try { ws.destroy(); } catch (_) {}
        resolve(null);
      }, 15000);
      rs.pipe(ws);
      ws.on("finish", () => {
        clearTimeout(timer);
        resolve(outPath);
      });
      ws.on("error", () => {
        clearTimeout(timer);
        resolve(null);
      });
      rs.on("error", () => {
        clearTimeout(timer);
        resolve(null);
      });
    } catch (_) {
      resolve(null);
    }
  });
}

// RFC 7233: «a-b», «a-» y sufijo «-n» (últimos n bytes); un fin pasado el EOF se recorta.
// Devuelve null (cabecera ilegible → se sirve entero), {unsatisfiable:true} o {start,end}.
function parseRange(header, total) {
  const m = /^bytes=(\d*)-(\d*)$/.exec(String(header).trim());
  if (!m || (!m[1] && !m[2])) return null;
  let start;
  let end;
  if (m[1]) {
    start = parseInt(m[1], 10);
    end = m[2] ? Math.min(parseInt(m[2], 10), total - 1) : total - 1;
  } else {
    start = Math.max(0, total - parseInt(m[2], 10));
    end = total - 1;
  }
  if (start >= total || start > end) return { unsatisfiable: true };
  return { start, end };
}

async function main() {
  const args = parseArgs(process.argv);
  if (!args.source) {
    console.error("Uso: cast-torrent <magnet|ruta.torrent|url.torrent> [--port N] [--tmp DIR] [--file N]");
    process.exit(2);
  }

  const baseTmp = args.tmp || path.join(os.homedir(), ".cache", "cast-torrent");
  fs.mkdirSync(baseTmp, { recursive: true });
  cleanupStaleDirs(baseTmp);

  const sessionTmp = path.join(baseTmp, `ct-${process.pid}-${Date.now()}`);
  fs.mkdirSync(sessionTmp, { recursive: true });

  let engine = null;
  let server = null;
  let shuttingDown = false;

  function shutdown(code = 0) {
    if (shuttingDown) return;
    shuttingDown = true;
    const forceTimer = setTimeout(() => {
      try { fs.rmSync(sessionTmp, { recursive: true, force: true }); } catch (_) {}
      process.exit(code);
    }, 2500);
    forceTimer.unref();

    if (server) {
      try { server.close(); } catch (_) {}
    }
    if (engine) {
      try {
        engine.destroy(() => {
          try { fs.rmSync(sessionTmp, { recursive: true, force: true }); } catch (_) {}
          process.exit(code);
        });
        return;
      } catch (_) {}
    }
    try { fs.rmSync(sessionTmp, { recursive: true, force: true }); } catch (_) {}
    process.exit(code);
  }

  process.on("SIGINT", () => shutdown(0));
  process.on("SIGTERM", () => shutdown(0));

  let input;
  try {
    input = await resolveTorrentInput(args.source);
  } catch (err) {
    console.log(JSON.stringify({ ready: false, error: err.message }));
    shutdown(1);
    return;
  }

  engine = torrentStream(input, {
    tmp: sessionTmp,
    connections: 80,
    uploads: 5,
    verify: true,
  });

  engine.on("error", (err) => {
    console.error("torrent-stream error:", err.message);
  });

  engine.on("ready", async () => {
    if (!engine.files || engine.files.length === 0) {
      console.log(JSON.stringify({ ready: false, error: "El torrent no contiene archivos" }));
      shutdown(1);
      return;
    }

    for (const f of engine.files) {
      f.deselect();
    }

    const target = pickTargetFile(engine.files, args.fileIndex);
    target.select();
    // Pre-buffer the first 1 MiB immediately so torrent-stream starts fetching sequential pieces before ffprobe connects.
    try {
      const preEnd = Math.min(target.length - 1, 1024 * 1024 - 1);
      if (preEnd >= 0) {
        const pre = target.createReadStream({ start: 0, end: preEnd });
        pre.on("data", () => {});
        pre.on("error", () => {});
      }
    } catch (_) {}

    const ext = path.extname(target.name).toLowerCase();
    const mime = MIME_MAP[ext] || "application/octet-stream";

    // Descargar subtítulos externos pequeños del torrent si existen (en paralelo, máx 4)
    const subFiles = engine.files
      .filter((f) => f !== target && SUB_EXTS.has(path.extname(f.name).toLowerCase()) && f.length > 0 && f.length < 5 * 1024 * 1024)
      .slice(0, 4);

    let subPaths = [];
    if (subFiles.length > 0) {
      const subDir = path.join(sessionTmp, "subs");
      fs.mkdirSync(subDir, { recursive: true });
      const results = await Promise.all(subFiles.map((sf) => downloadSubFile(sf, subDir)));
      subPaths = results.filter(Boolean);
    }

    server = http.createServer((req, res) => {
      const urlPath = (req.url || "/").split("?")[0];

      if (urlPath === "/status") {
        const downloaded = engine.swarm ? engine.swarm.downloaded : 0;
        const payload = {
          downloaded,
          downloadSpeed: engine.swarm ? engine.swarm.downloadSpeed() : 0,
          uploadSpeed: engine.swarm ? engine.swarm.uploadSpeed() : 0,
          peers: engine.swarm ? engine.swarm.wires.length : 0,
          length: target.length,
        };
        res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
        res.end(JSON.stringify(payload));
        return;
      }

      if (urlPath !== "/video" && !urlPath.startsWith("/video/")) {
        res.writeHead(404);
        res.end("Not found");
        return;
      }

      const total = target.length;
      const rangeHeader = req.headers.range;
      res.setHeader("Accept-Ranges", "bytes");
      res.setHeader("Content-Type", mime);
      res.setHeader("Cache-Control", "no-store");

      let start = 0;
      let end = total - 1;
      let status = 200;

      if (rangeHeader) {
        const r = parseRange(rangeHeader, total);
        if (r && r.unsatisfiable) {
          res.writeHead(416, { "Content-Range": `bytes */${total}` });
          res.end();
          return;
        }
        if (r) {
          start = r.start;
          end = r.end;
          status = 206;
          res.setHeader("Content-Range", `bytes ${start}-${end}/${total}`);
        }
      }

      res.writeHead(status, { "Content-Length": end - start + 1 });
      if (req.method === "HEAD") {
        res.end();
        return;
      }

      const stream = target.createReadStream({ start, end });
      const destroyStream = () => {
        try { stream.destroy(); } catch (_) {}
      };
      req.on("close", destroyStream);
      res.on("close", destroyStream);
      stream.on("error", () => {
        if (!res.headersSent) res.writeHead(500);
        res.end();
      });
      stream.pipe(res);
    });

    server.listen(args.port, "127.0.0.1", () => {
      const addr = server.address();
      const out = {
        ready: true,
        url: `http://127.0.0.1:${addr.port}/video`,
        statusUrl: `http://127.0.0.1:${addr.port}/status`,
        name: target.name,
        length: target.length,
        infoHash: engine.infoHash,
        subs: subPaths,
      };
      process.stdout.write(JSON.stringify(out) + "\n");
    });
  });
}

if (require.main === module) {
  main().catch((err) => {
    console.log(JSON.stringify({ ready: false, error: err.message }));
    process.exit(1);
  });
}

module.exports = { parseRange, pickTargetFile };
