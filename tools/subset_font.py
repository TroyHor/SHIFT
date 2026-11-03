"""把 Noto Sans SC / Noto Serif SC 裁成只含游戏用到的字，网页版加载更快。

用法：python3 tools/subset_font.py <NotoSansSC 字体路径> [NotoSerifSC 字体路径]
完整字体可从 https://github.com/google/fonts/tree/main/ofl/notosanssc 和 .../notoserifsc 下载。
正文用 Sans（500 字重），标题用 Serif（700 字重）。
"""
import glob
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "fonts", "NotoSansSC-Subset.ttf")
OUT_SERIF = os.path.join(ROOT, "assets", "fonts", "NotoSerifSC-Subset.ttf")
EXTRA = "↑↓✓□·…—『』【】（）：，。？！、×"


def subset(src: str, out: str, weight: int, text: str, tmp: str) -> None:
    static = os.path.join(tmp, f"static{weight}.ttf")
    # 可变字体先固定字重；静态字体会直接报错跳过
    r = subprocess.run([sys.executable, "-m", "fontTools.varLib.instancer", src, f"wght={weight}", "-o", static])
    if r.returncode != 0:
        static = src
    subprocess.run(
        ["pyftsubset", static, f"--text-file={text}", f"--output-file={out}", "--layout-features=*"],
        check=True,
    )


def main() -> None:
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    chars = set(chr(c) for c in range(0x20, 0x7F)) | set(EXTRA)
    for path in glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True):
        with open(path, encoding="utf-8") as f:
            chars |= set(f.read())
    chars.discard("\n")
    chars.discard("\t")
    with tempfile.TemporaryDirectory() as tmp:
        text = os.path.join(tmp, "chars.txt")
        with open(text, "w", encoding="utf-8") as f:
            f.write("".join(sorted(chars)))
        subset(sys.argv[1], OUT, 500, text, tmp)
        print(f"{len(chars)} chars -> {OUT}")
        if len(sys.argv) == 3:
            subset(sys.argv[2], OUT_SERIF, 700, text, tmp)
            print(f"{len(chars)} chars -> {OUT_SERIF}")


if __name__ == "__main__":
    main()
