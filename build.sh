#!/usr/bin/env bash
# ============================================
# 生活工作台 · 一键构建脚本
# 用法: bash build.sh
# 产物: releases/LifeWorkbench_v<versionName>.apk
#   （版本号自动读取 app/AndroidManifest.xml 的 versionName）
# 依赖: C:\wb-tools（JDK17 + Android SDK）与 keystore/（签名密钥）
# ============================================
set -e
WS="C:\\Users\\稚鹿\\Desktop\\工作台"
TOOLS="/c/wb-tools"
BT="$TOOLS\\android-sdk\\build-tools\\34.0.0"
JAVA="$TOOLS\\jdk-17.0.2\\bin\\java.exe"
JAVAC="$TOOLS\\jdk-17.0.2\\bin\\javac.exe"
PY="C:\\Users\\稚鹿\\.workbuddy\\binaries\\python\\versions\\3.13.12\\python.exe"
B="/c/wb-build"

# 读取版本号与签名密码
VER=$(grep -o 'versionName="[^"]*"' app/AndroidManifest.xml | cut -d'"' -f2)
[ -z "$VER" ] && { echo "错误：无法从 app/AndroidManifest.xml 读取 versionName"; exit 1; }
[ -f keystore/pass.txt ] || { echo "错误：缺少 keystore/pass.txt（签名密码文件，不入库）"; exit 1; }
KS_PASS=$(cat keystore/pass.txt)
echo "===== 构建 v$VER ====="

# 1. 暂存到纯英文构建目录（工具链对中文路径敏感）
rm -rf "$B/app" "$B/out"
mkdir -p "$B/app/assets" "$B/app/java/com/lifewb/app" "$B/out/classes" "$B/out/dex" "$B/lib"
cp "$WS/app/index.html" "$B/app/assets/index.html"
cp "$WS/app/AndroidManifest.xml" "$B/app/AndroidManifest.xml"
cp -r "$WS/app/res" "$B/app/res"
cp "$WS/app/java/com/lifewb/app/MainActivity.java" "$B/app/java/com/lifewb/app/MainActivity.java"
cp "$TOOLS/android-sdk/platforms/android-34/android.jar" "$B/" 2>/dev/null || true
cp "$BT/lib/d8.jar" "$BT/lib/apksigner.jar" "$B/lib/" 2>/dev/null || true
echo "[1/7] 源码已暂存"

# 2. aapt2 资源编译 + 链接
"$BT\\aapt2.exe" compile --dir "C:\\wb-build\\app\\res" -o "C:\\wb-build\\out\\res.zip"
"$BT\\aapt2.exe" link -o "C:\\wb-build\\out\\app-unaligned.apk" -I "C:\\wb-build\\android.jar" --manifest "C:\\wb-build\\app\\AndroidManifest.xml" "C:\\wb-build\\out\\res.zip" -A "C:\\wb-build\\app\\assets" --min-sdk-version 24 --target-sdk-version 34
echo "[2/7] aapt2 完成"

# 3. javac 编译壳
"$JAVAC" -encoding UTF-8 -classpath "C:\\wb-build\\android.jar" -d "C:\\wb-build\\out\\classes" "C:\\wb-build\\app\\java\\com\\lifewb\\app\\MainActivity.java"
echo "[3/7] javac 完成"

# 4. d8 转 dex（含全部内部类）
cd "$B/out/classes"
"$JAVA" -cp "C:\\wb-build\\lib\\d8.jar" com.android.tools.r8.D8 --lib "C:\\wb-build\\android.jar" --output "C:\\wb-build\\out\\dex" com/lifewb/app/*.class
cd "$WS"
echo "[4/7] d8 完成"

# 5. 注入 dex
"$PY" -c "
import zipfile, shutil
shutil.copy(r'C:\wb-build\out\app-unaligned.apk', r'C:\wb-build\out\app-withdex.apk')
with zipfile.ZipFile(r'C:\wb-build\out\app-withdex.apk', 'a', zipfile.ZIP_DEFLATED) as z:
    z.write(r'C:\wb-build\out\dex\classes.dex', 'classes.dex')
"
echo "[5/7] dex 已注入"

# 6. zipalign
"$BT\\zipalign.exe" -f 4 "C:\\wb-build\\out\\app-withdex.apk" "C:\\wb-build\\out\\app-unsigned.apk"
echo "[6/7] zipalign 完成"

# 7. 签名（同一 keystore → 覆盖安装数据保留）
"$JAVA" -cp "C:\\wb-build\\lib\\apksigner.jar" com.android.apksigner.ApkSignerTool sign --ks "$WS\\keystore\\wb.keystore" --ks-pass pass:$KS_PASS --key-pass pass:$KS_PASS --out "C:\\wb-build\\out\\LifeWorkbench_v$VER.apk" "C:\\wb-build\\out\\app-unsigned.apk"
"$JAVA" -cp "C:\\wb-build\\lib\\apksigner.jar" com.android.apksigner.ApkSignerTool verify "C:\\wb-build\\out\\LifeWorkbench_v$VER.apk"
cp "$B/out/LifeWorkbench_v$VER.apk" "$WS/releases/LifeWorkbench_v$VER.apk"
echo "[7/7] 构建完成 -> releases/LifeWorkbench_v$VER.apk"
