# adds core library desugaring (flutter_local_notifications needs it)
import pathlib
import re
import sys

kts = pathlib.Path("android/app/build.gradle.kts")
groovy = pathlib.Path("android/app/build.gradle")

if kts.exists():
    path, flag, dep = (
        kts,
        "isCoreLibraryDesugaringEnabled = true",
        'dependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n',
    )
elif groovy.exists():
    path, flag, dep = (
        groovy,
        "coreLibraryDesugaringEnabled true",
        "dependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n",
    )
else:
    sys.exit("No android/app/build.gradle(.kts) found. Run flutter create first.")

text = path.read_text()
if "oreLibraryDesugaring" in text:
    print(f"{path} already patched")
    sys.exit(0)

text, count = re.subn(r"compileOptions\s*\{", "compileOptions {\n        " + flag, text, count=1)
if count == 0:
    sys.exit(f"Could not find a compileOptions block in {path}")
text += "\n" + dep
path.write_text(text)
print(f"Patched {path}")
