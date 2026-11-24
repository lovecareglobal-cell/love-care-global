import pathlib
import re

p = pathlib.Path("lib/main.dart")
t = p.read_text(encoding="utf-8", errors="ignore")

t = t.replace("import 'main_translations.dart';", "")
t = t.replace("await MainTranslations.load();", "")

t = re.sub(r"MainTranslations\.t\('([^']+)'\)", r"'\1'", t)

lines = []
for line in t.splitlines():
    if "MainTranslations" in line:
        continue
    lines.append(line)

t = "\n".join(lines)
p.write_text(t, encoding="utf-8")
print("DONE - Left:", t.count("MainTranslations"))
