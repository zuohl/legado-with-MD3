#!/usr/bin/env bash
# ==============================================================================
# 构建与原版共存的测试 APK
# 用法:
#   ./build_coexist_apk.sh [包名] [应用名称]
# 示例:
#   ./build_coexist_apk.sh
#   ./build_coexist_apk.sh io.legato.kazusa.preview "阅读(测试)"
# ==============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

APP_ID="${1:-io.legato.kazusa.coexist}"
APP_NAME="${2:-阅读(测试)}"
OUTPUT_DIR="$PROJECT_DIR/outputs"

echo "=========================================="
echo "开始构建共存测试安装包..."
echo "包名 (Application ID): $APP_ID"
echo "应用名称 (App Name):   $APP_NAME"
echo "=========================================="

mkdir -p "$OUTPUT_DIR"

chmod +x ./gradlew

# 临时给 google-services.json 增加自定义包名以通过 google-services 插件校验
GOOGLE_SERVICES_BACKUP="$PROJECT_DIR/app/google-services.json.bak"
cp -f "$PROJECT_DIR/app/google-services.json" "$GOOGLE_SERVICES_BACKUP"
cleanup() {
    if [[ -f "$GOOGLE_SERVICES_BACKUP" ]]; then
        mv -f "$GOOGLE_SERVICES_BACKUP" "$PROJECT_DIR/app/google-services.json"
    fi
}
trap cleanup EXIT INT TERM

python3 -c "
import json
with open('app/google-services.json', 'r') as f:
    data = json.load(f)
packages = [c['client_info']['android_client_info']['package_name'] for c in data.get('client', [])]
for pkg in ['$APP_ID', f'${APP_ID}.debug']:
    if pkg not in packages:
        new_client = json.loads(json.dumps(data['client'][0]))
        new_client['client_info']['android_client_info']['package_name'] = pkg
        data['client'].append(new_client)
with open('app/google-services.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 临时创建一个空 init.gradle 避免用户环境中的全局 init.gradle 覆盖仓库配置导致构建失败
EMPTY_INIT_FILE="/tmp/legado_empty_init.gradle"
touch "$EMPTY_INIT_FILE"

./gradlew assembleAppDebug \
  -PcustomAppId="$APP_ID" \
  -PcustomAppName="$APP_NAME" \
  -PenableAbiSplits=false \
  --no-daemon \
  --no-configuration-cache

# 复制生成的 APK 到输出目录
SRC_APK_DIR="$PROJECT_DIR/app/build/outputs/apk/app/debug"
GENERATED_APK=$(find "$SRC_APK_DIR" -maxdepth 1 -name "*.apk" | head -n 1)

if [[ -n "$GENERATED_APK" && -f "$GENERATED_APK" ]]; then
    TARGET_APK="$OUTPUT_DIR/legado-coexist-debug.apk"
    cp -f "$GENERATED_APK" "$TARGET_APK"
    echo "=========================================="
    echo "🎉 构建成功！共存安装包路径:"
    echo "$TARGET_APK"
    echo "文件大小: $(du -h "$TARGET_APK" | cut -f1)"
    echo "你可以直接将此 APK 安装到手机，与原有阅读完全共存！"
    echo "=========================================="
else
    echo "❌ 未找到构建生成的 APK，请检查构建日志！"
    exit 1
fi
