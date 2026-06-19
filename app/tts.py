"""
tts.py - text-to-speech for sonelle's voice narrator.

synth(text, cfg) -> (mime, raw_bytes) or None. Three engines, tried in order of quality:

  1. kokoro - a real, modern NEURAL voice that runs LOCALLY (Kokoro, ONNX). Free, no API key, fully
              offline. The voice MODEL is VENDORED IN THE REPO (app/voice/: the ~88 MB int8 build +
              the voice pack) - NO download, it ships with sonelle. Only the small runtime package
              (kokoro-onnx) installs via pip. Returns WAV. Default.
  2. edge   - Microsoft's free neural voices via edge-tts (no key; needs internet). A clean cloud
              fallback if Kokoro isn't installed yet / the model can't be fetched. Returns MP3.
  3. sapi   - the always-present Windows System.Speech voice, via a tiny PowerShell call. Robotic
              but fully OFFLINE, so the narrator still talks with nothing installed and no network.

Every engine is best-effort and swallows all errors: if none works, synth returns None and the
narrator simply shows its inline text line without audio. Kept ASCII for consistency with the
rest of the engine.
"""
import os
import io
import wave
import base64
import tempfile
import threading
import subprocess

_CREATE_NO_WINDOW = 0x08000000

# ---------------------------------------------------------------------------------------------
# Engine 1: Kokoro - local neural voice (the good one). The model files are VENDORED IN THE REPO
# (app/voice/) and loaded directly from there - no download, fully offline. onnxruntime runs inference
# on the CPU. (To de-bloat the repo this is the file to move to Git LFS or a first-run download.)
# ---------------------------------------------------------------------------------------------
# Pinned model-files-v1.0 release of kokoro-onnx (the model + the bundled multi-voice pack).
_KOKORO_DEFAULT_VOICE = "af_heart"   # the warm, natural flagship female voice in the v1.0 pack

_KOKORO_LOCK = threading.Lock()      # single-flight: one model load across tabs
_kokoro_obj = None                   # cached Kokoro instance (load the model once)


def kokoro_dir():
    """The voice model is VENDORED IN THE REPO (app/voice/) - no download, ships with sonelle."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "voice")


def _kokoro_files():
    """Return (model_path, voices_path) for the bundled int8 model (small enough to live in git)."""
    d = kokoro_dir()
    return (os.path.join(d, "kokoro-v1.0.int8.onnx"), os.path.join(d, "voices-v1.0.bin"))


def _get_kokoro():
    """Lazily import kokoro-onnx and build the (cached) Kokoro instance from the BUNDLED model."""
    global _kokoro_obj
    if _kokoro_obj is not None:
        return _kokoro_obj
    from kokoro_onnx import Kokoro   # raises if the optional runtime package isn't installed
    model, voices = _kokoro_files()
    if not (os.path.isfile(model) and os.path.isfile(voices)):
        raise RuntimeError("bundled kokoro model missing under app/voice/")
    _kokoro_obj = Kokoro(model, voices)
    return _kokoro_obj


def _wav_bytes(samples, sample_rate):
    """Pack float32 [-1,1] mono samples into in-memory WAV bytes (no soundfile dependency)."""
    import numpy as np
    arr = np.asarray(samples, dtype="float32")
    pcm = (np.clip(arr, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    buf = io.BytesIO()
    w = wave.open(buf, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(int(sample_rate))
    w.writeframes(pcm)
    w.close()
    return buf.getvalue()


def _synth_kokoro(text, voice, speed):
    """Local neural TTS via kokoro-onnx. Returns WAV bytes or None.

    Best-effort and NON-latching: if the package isn't installed yet (it's fetched in the background
    on first launch), or the model can't load, this returns None and the caller falls back to
    edge/SAPI - and a LATER call retries from scratch, so the moment the install finishes the voice
    upgrades itself to Kokoro with no restart."""
    try:
        v = voice or _KOKORO_DEFAULT_VOICE
        # an edge-style voice name ("en-US-AriaNeural") in the config -> use the Kokoro default
        if "neural" in str(v).lower():
            v = _KOKORO_DEFAULT_VOICE
        try:
            sp = float(speed)
        except Exception:
            sp = 1.0
        if sp <= 0:
            sp = 1.0
        with _KOKORO_LOCK:
            k = _get_kokoro()
            samples, sr = k.create(text, voice=v, speed=sp, lang="en-us")
        return _wav_bytes(samples, sr)
    except Exception:
        # not installed yet / offline / model hiccup -> fall back this time; the next line retries.
        return None


# ---------------------------------------------------------------------------------------------
# Engine 2: edge-tts - Microsoft neural voices (cloud, free, no key).
# ---------------------------------------------------------------------------------------------
def _synth_edge(text, voice, rate, pitch):
    """Microsoft neural TTS via the edge-tts package. Returns MP3 bytes or None."""
    try:
        import asyncio
        import edge_tts
    except Exception:
        return None

    # a Kokoro-style voice id ("af_heart") in the config -> use a sane edge default instead
    if "neural" not in str(voice or "").lower():
        voice = "en-US-AriaNeural"

    async def _go():
        comm = edge_tts.Communicate(text, voice=voice, rate=rate, pitch=pitch)
        buf = bytearray()
        async for chunk in comm.stream():
            if chunk.get("type") == "audio" and chunk.get("data"):
                buf.extend(chunk["data"])
        return bytes(buf)

    loop = None
    try:
        loop = asyncio.new_event_loop()
        data = loop.run_until_complete(_go())
        return data or None
    except Exception:
        return None
    finally:
        try:
            if loop is not None:
                loop.close()
        except Exception:
            pass


def _ps_exe():
    import shutil
    exe = shutil.which("powershell.exe")
    if exe:
        return exe
    sysroot = os.environ.get("SystemRoot", r"C:\Windows")
    return os.path.join(sysroot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")


# ---------------------------------------------------------------------------------------------
# Engine 3: Windows SAPI - the offline last resort (robotic, but always there).
# ---------------------------------------------------------------------------------------------
def _synth_sapi(text):
    """Offline fallback: drive Windows System.Speech to a temp WAV, read it back. WAV bytes or None."""
    if os.name != "nt":
        return None
    wav = None
    try:
        fd, wav = tempfile.mkstemp(suffix=".wav", prefix="sonelle_tts_")
        os.close(fd)
        # Speak the text (passed via env so no quoting/escaping games) into a wave file.
        script = (
            "$ErrorActionPreference='SilentlyContinue';"
            "Add-Type -AssemblyName System.Speech;"
            "$s=New-Object System.Speech.Synthesis.SpeechSynthesizer;"
            "try{$s.SelectVoiceByHints('Female')}catch{};"
            "$s.SetOutputToWaveFile($env:SONELLE_TTS_WAV);"
            "$s.Speak($env:SONELLE_TTS_TEXT);"
            "$s.Dispose()"
        )
        env = os.environ.copy()
        env["SONELLE_TTS_WAV"] = wav
        env["SONELLE_TTS_TEXT"] = text
        subprocess.run(
            [_ps_exe(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
            env=env, creationflags=_CREATE_NO_WINDOW, timeout=20,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        with open(wav, "rb") as f:
            data = f.read()
        return data or None
    except Exception:
        return None
    finally:
        try:
            if wav and os.path.isfile(wav):
                os.remove(wav)
        except Exception:
            pass


def synth(text, cfg=None):
    """Return (mime, raw_bytes) for spoken `text`, or None if no engine could produce audio.

    Engine order is best-quality-first: kokoro (local neural) -> edge (cloud neural) -> sapi
    (offline). cfg.engine pins a starting point: "kokoro" (default), "edge", or "sapi".
    """
    text = (text or "").strip()
    if not text:
        return None
    cfg = cfg or {}
    engine = (cfg.get("engine") or "kokoro").lower()
    voice = cfg.get("voice", _KOKORO_DEFAULT_VOICE)

    if engine == "kokoro":
        data = _synth_kokoro(text, voice, cfg.get("speed", 1.0))
        if data:
            return ("audio/wav", data)
        engine = "edge"   # Kokoro unavailable this time -> try the cloud neural voice

    if engine == "edge":
        data = _synth_edge(text, voice, cfg.get("rate", "+0%"), cfg.get("pitch", "+0Hz"))
        if data:
            return ("audio/mpeg", data)

    data = _synth_sapi(text)
    if data:
        return ("audio/wav", data)
    return None


def synth_b64(text, cfg=None):
    """Convenience: synth() then base64-encode. Returns (mime, b64str) or None."""
    out = synth(text, cfg)
    if not out:
        return None
    mime, data = out
    return (mime, base64.b64encode(data).decode("ascii"))
