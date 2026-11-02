# Third-party software

OpenListen's own source is MIT-licensed. That license does not replace the licenses below or grant rights to media content.

| Component | Use | Upstream license |
| --- | --- | --- |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp#license) | Separate Python process resolving and downloading media | Unlicense for the upstream source; some distributions and dependencies have other terms |
| [yt-dlp-ejs](https://github.com/yt-dlp/ejs) | Installed yt-dlp JavaScript support | Consult the installed upstream package's license |
| [FFmpeg](https://ffmpeg.org/legal.html) | User-installed command-line audio conversion | LGPL/GPL depending on the user's build configuration |
| [FastAPI](https://github.com/fastapi/fastapi) | Local HTTP API | MIT |
| [Uvicorn](https://github.com/encode/uvicorn) | Local HTTP server | BSD-3-Clause |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Developer-installed project generator | MIT |

This repository does not bundle FFmpeg, yt-dlp executables, Apple SDKs, or downloaded media. Dependency versions are recorded in `companion/uv.lock`; their license files remain with the installed packages. If redistributing a packaged companion, inspect and include the relevant notices and source obligations for every dependency and binary included in that distribution.

Apple frameworks and Xcode are supplied by Apple under Apple's own terms. YouTube and other referenced product names belong to their owners; this project is not affiliated with them.
