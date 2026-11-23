# convert_all.py - RUN THIS ONCE on your PC, in your project folder
# It converts ALL your pages at once, you don't upload them one by one.
#
# HOW TO RUN:
#  1. Copy this file into your project folder (same folder as lib/)
#  2. Open terminal / CMD in that folder
#  3. Run:  python convert_all.py
#  4. It will backup + convert every .dart file in lib/
#  5. Then run: flutter build apk --release  (or your GitHub Action)
#
# WHAT IT DOES:
#  Text('Book Nurse')  ->  TText('Book Nurse')
#  Text("Book Nurse")  ->  TText("Book Nurse")
#  It SKIPS: already converted TText, Text with variables, Text with .tr, TextField hints, etc.
#  It ADDS: import for t_text_helper.dart if missing
#  It COLLECTS: all English phrases into untranslated.txt so you can add translations
import re, pathlib

root = pathlib.Path("lib")
all_phrases = set()

for f in root.rglob("*.dart"):
    if f.name in ("language_service.dart", "t_text_helper.dart", "main.dart"):
        continue
    text = f.read_text(encoding="utf-8", errors="ignore")
    orig = text
    # Find Text('...') / Text("...") with plain string literal only
    def repl(m):
        quote = m.group(1)
        inner = m.group(2)
        # skip if contains $ , { , \n, or is empty / single char / number
        if "$" in inner or "{" in inner or len(inner.strip()) < 2:
            return m.group(0)
        # skip if already inside TText - handled by not matching TText
        all_phrases.add(inner)
        return f"TText({quote}{inner}{quote}"
    # Only match Text( not TText( - use negative lookbehind
    text = re.sub(r"(?<!\w)Text\((['\"])([^'\"\n]{2,}?)\1", repl, text)
    if text != orig:
        # add import if not present
        if "t_text_helper" not in text:
            # try to add after first import
            text = re.sub(r"(import [^;]+;\n)", r"\1import '../t_text_helper.dart';\n", text, count=1) if "screens/" in str(f) else re.sub(r"(import [^;]+;\n)", r"\1import 't_text_helper.dart';\n", text, count=1)
        f.write_text(text, encoding="utf-8")
        print(f"Converted: {f}")

pathlib.Path("untranslated.txt").write_text("\n".join(sorted(all_phrases)), encoding="utf-8")
print(f"\nDone! {len(all_phrases)} phrases collected in untranslated.txt")
print("Copy phrases from untranslated.txt into language_service.dart _byEnglish to translate them.")
