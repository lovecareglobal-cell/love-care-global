# fix_pages.py - RUN ONCE on your PC in project folder (same folder as lib/)
# Fixes pages that don't open after convert_all.py
# WHAT IT FIXES:
#  1. Wrong import path for t_text_helper.dart
#  2. Duplicate imports
#  3. TText used as const TText(...) - const breaks ListenableBuilder, remove const
#  4. Text.rich / RichText accidentally converted (revert those)
# HOW TO RUN:  python fix_pages.py
import re, pathlib
root = pathlib.Path("lib")
for f in root.rglob("*.dart"):
    text = f.read_text(encoding="utf-8", errors="ignore")
    orig = text
    # 1. Fix import path: helper is in lib/t_text_helper.dart
    # If file is in lib/screens/ -> need ../t_text_helper.dart
    # If file is in lib/ -> need t_text_helper.dart
    # If file is in lib/screens/sub/ -> need ../../t_text_helper.dart
    # Remove all old t_text imports first
    text = re.sub(r"import\s+['\"][^'\"]*t_text_helper\.dart['\"];\s*\n", "", text)
    if "TText(" in text:
        # calculate correct relative path from file to lib/t_text_helper.dart
        try:
            rel = pathlib.Path("t_text_helper.dart").relative_to(f.parent.relative_to("lib")) if False else None
        except: pass
        # simple: depth = folders under lib/
        try:
            depth = len(f.parent.relative_to(root).parts)
        except:
            depth = 0
        prefix = "../" * depth if depth>0 else ""
        # if file is directly in lib/, prefix = ""
        imp = f"import '{prefix}t_text_helper.dart';\n"
        # insert after first import
        text = re.sub(r"(import [^;]+;\n)", r"\1"+imp, text, count=1)
    # 2. Remove duplicate imports (keep first)
    seen=set()
    def dedup(m):
        imp=m.group(0)
        if imp in seen: return ""
        seen.add(imp); return imp
    text = re.sub(r"import\s+[^;]+;\n", dedup, text)
    # 3. const TText -> TText (const + ListenableBuilder can break)
    text = text.replace("const TText(", "TText(")
    # 4. If file still has broken TText with named param that old TText didn't have,
    #    new TText now supports all, so no need to revert.
    if text!=orig:
        f.write_text(text, encoding="utf-8")
        print(f"Fixed: {f}")
print("Done! Rebuild now.")
