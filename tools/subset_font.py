"""把 Noto Sans SC 裁成只含游戏用到的字，网页版加载更快。

用法：python3 tools/subset_font.py <NotoSansSC 字体路径（静态或可变字体均可）>
完整字体可从 https://github.com/google/fonts/tree/main/ofl/notosanssc 下载。
"""
import glob
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "fonts", "NotoSansSC-Subset.ttf")
EXTRA = "✓□·…—『』【】（）：，。？！、×"


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = sys.argv[1]
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
        static = os.path.join(tmp, "static.ttf")
        # 可变字体先固定在 500 字重；静态字体会直接报错跳过
        r = subprocess.run([sys.executable, "-m", "fontTools.varLib.instancer", src, "wght=500", "-o", static])
        if r.returncode != 0:
            static = src
        subprocess.run(
            ["pyftsubset", static, f"--text-file={text}", f"--output-file={OUT}", "--layout-features=*"],
            check=True,
        )
    print(f"{len(chars)} chars -> {OUT}")


if __name__ == "__main__":
    main()
