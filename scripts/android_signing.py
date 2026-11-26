#!/usr/bin/env python3
"""Подключает подпись ключом из android/key.properties в android/app/build.gradle.kts (Flutter).
Идемпотентно: повторный запуск ничего не меняет. Нет key.properties при сборке → подпись отладочным ключом.
  python3 scripts/android_signing.py projects/<slug>/android/app/build.gradle.kts"""
import re, sys
from pathlib import Path
for _s in (sys.stdout, sys.stderr):
    _s.reconfigure(encoding="utf-8")  # Windows-консоль: кириллица

MARK = "// ai-studio: release signing"
HEAD = f'''{MARK}
val keystoreProperties = Properties().apply {{
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use {{ load(it) }}
}}
'''
CONFIG = '''    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

'''
RELEASE = ('signingConfig = if (keystoreProperties.isNotEmpty()) signingConfigs.getByName("release") '
           'else signingConfigs.getByName("debug")')

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
if MARK in t:
    print(f"Подпись уже подключена: {p}")
    sys.exit()
if p.suffix != ".kts":
    sys.exit(f"Ошибка: ожидался build.gradle.kts, а это {p.name}. Подключи подпись вручную (навык flutter-android-release).")
# import — только в самом начале файла (внутри Gradle `java.` занято расширением, полное имя не работает)
m = re.search(r"^plugins \{.*?^\}\n", t, re.S | re.M)
t = (t[:m.end()] + "\n" + HEAD + t[m.end():]) if m else HEAD + "\n" + t
t = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + t
t, n1 = re.subn(r"^(\s*)buildTypes \{", lambda mm: CONFIG + mm.group(0), t, count=1, flags=re.M)
t, n2 = re.subn(r'signingConfig = signingConfigs\.getByName\("debug"\)', RELEASE, t, count=1)
if not (n1 and n2):
    sys.exit("Ошибка: не нашёл buildTypes/signingConfig в build.gradle.kts — формат изменился, подключи вручную.")
p.write_text(t, encoding="utf-8")
print(f"Подпись подключена: {p}")
