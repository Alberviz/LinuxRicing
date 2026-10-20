"""Edge TTS (nube de Microsoft). Config: [tts.edge] voice. Si falla (p. ej. 403) cae al siguiente motor."""
from __future__ import annotations

import subprocess

from . import Engine, engine


@engine("edge")
class Edge(Engine):
    def synth(self, text: str, out_wav: str) -> None:
        import asyncio

        import edge_tts
        voice = self.cfg.get("voice", "es-ES-ElviraNeural")
        mp3 = out_wav + ".mp3"

        async def _run():
            await edge_tts.Communicate(text, voice).save(mp3)

        asyncio.run(_run())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3, out_wav], check=True)
